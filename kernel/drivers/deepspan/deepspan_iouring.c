// SPDX-License-Identifier: GPL-2.0
/*
 * deepspan_iouring.c - io_uring asynchronous command processing
 *
 * Flow:
 *   1. User submits IORING_OP_URING_CMD
 *   2. .uring_cmd() called → request_id issued via xa_alloc()
 *   3. Buffer added to virtio TX VQ → virtqueue_kick()
 *   4. Returns -EIOCBQUEUED (async in progress)
 *   5. Firmware completion → RX VQ IRQ → xa_erase() in vqueue.c → io_uring_cmd_done()
 */

#include <linux/io_uring/cmd.h>
#include <linux/virtio.h>
#include <linux/slab.h>
#include <linux/xarray.h>
#include <linux/uaccess.h>

#include "deepspan_priv.h"

/* UAPI structure (same as include/uapi/linux/deepspan.h) */
struct deepspan_cmd_req {
    __u32 opcode;
    __u32 flags;
    __u64 data_ptr;
    __u32 data_len;
    __u32 timeout_ms;
};

int deepspan_uring_cmd_issue(struct io_uring_cmd *cmd, unsigned int issue_flags)
{
    struct deepspan_device *ddev =
        container_of(cmd->file->f_inode->i_cdev, struct deepspan_device, cdev);
    const struct deepspan_cmd_req *ureq =
        io_uring_sqe_cmd(cmd->sqe);
    struct deepspan_request *req;
    u32 req_id;
    int ret;

    req = kzalloc(sizeof(*req), GFP_KERNEL);
    if (!req)
        return -ENOMEM;

    req->cmd     = cmd;
    req->buf_len = ureq->data_len;
    req->buf     = kzalloc(req->buf_len, GFP_KERNEL);
    if (!req->buf) {
        kfree(req);
        return -ENOMEM;
    }

    /* Copy user buffer */
    if (copy_from_user(req->buf, u64_to_user_ptr(ureq->data_ptr),
                       req->buf_len)) {
        kfree(req->buf);
        kfree(req);
        return -EFAULT;
    }

    /* Register request in XArray (auto-assign ID) */
    ret = xa_alloc(&ddev->pending, &req_id, req,
                   XA_LIMIT(1, DEEPSPAN_MAX_REQUESTS), GFP_KERNEL);
    if (ret) {
        kfree(req->buf);
        kfree(req);
        return ret;
    }
    req->req_id = req_id;

    /* Add buffer to virtio TX VQ */
    struct scatterlist sg;
    sg_init_one(&sg, req->buf, req->buf_len);

    spin_lock_bh(&ddev->vq_lock);
    ret = virtqueue_add_outbuf(ddev->vqs[VQ_DATA_TX], &sg, 1, req, GFP_ATOMIC);
    if (ret == 0)
        virtqueue_kick(ddev->vqs[VQ_DATA_TX]);
    spin_unlock_bh(&ddev->vq_lock);

    if (ret) {
        xa_erase(&ddev->pending, req_id);
        kfree(req->buf);
        kfree(req);
        return ret;
    }

    return -EIOCBQUEUED;  /* async: io_uring_cmd_done() called on completion */
}
