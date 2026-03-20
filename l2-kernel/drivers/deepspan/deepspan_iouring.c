// SPDX-License-Identifier: GPL-2.0
/*
 * deepspan_iouring.c - io_uring asynchronous command processing
 *
 * Flow:
 *   1. User submits IORING_OP_URING_CMD
 *   2. deepspan_uring_cmd_issue() called → xa_alloc() assigns request_id
 *   3. deepspan_req (outbuf) + deepspan_result slot (inbuf) added to TX VQ
 *      via virtqueue_add_sgs() → virtqueue_kick()
 *   4. Returns -EIOCBQUEUED (async in progress)
 *   5. Firmware writes result to inbuf, returns descriptor chain
 *   6. TX VQ IRQ → deepspan_vq_tx_cb() → tx_work → xa_erase() → io_uring_cmd_done()
 */

#include <linux/io_uring/cmd.h>
#include <linux/virtio.h>
#include <linux/slab.h>
#include <linux/xarray.h>
#include <linux/scatterlist.h>
#include <linux/uaccess.h>

#include "deepspan_priv.h"

/* UAPI structures — must match include/uapi/linux/deepspan.h */
struct deepspan_cmd_req {
    __u32 opcode;
    __u32 flags;
    __u64 data_ptr;
    __u32 data_len;
    __u32 timeout_ms;
};

struct deepspan_cmd_result {
    __s32 status;
    __u32 result_lo;
    __u32 result_hi;
    __u32 _pad;
};

int deepspan_uring_cmd_issue(struct io_uring_cmd *cmd, unsigned int issue_flags)
{
    struct deepspan_device *ddev =
        container_of(cmd->file->f_inode->i_cdev, struct deepspan_device, cdev);
    const struct deepspan_cmd_req *ureq =
        io_uring_sqe_cmd(cmd->sqe);
    struct deepspan_request *req;
    struct scatterlist sg_out, sg_in;
    struct scatterlist *sgs[2] = { &sg_out, &sg_in };
    u32 req_id;
    int ret;

    req = kzalloc(sizeof(*req), GFP_KERNEL);
    if (!req)
        return -ENOMEM;

    req->cmd     = cmd;
    req->buf_len = ureq->data_len ?: sizeof(struct deepspan_cmd_req);
    req->buf     = kzalloc(req->buf_len, GFP_KERNEL);
    if (!req->buf) {
        ret = -ENOMEM;
        goto err_free_req;
    }

    /* Allocate response slot (firmware writes result here) */
    req->resp_len = sizeof(struct deepspan_cmd_result);
    req->resp_buf = kzalloc(req->resp_len, GFP_KERNEL);
    if (!req->resp_buf) {
        ret = -ENOMEM;
        goto err_free_buf;
    }

    /* Copy user buffer (the request data) */
    if (ureq->data_len && ureq->data_ptr) {
        if (copy_from_user(req->buf, u64_to_user_ptr(ureq->data_ptr),
                           ureq->data_len)) {
            ret = -EFAULT;
            goto err_free_resp;
        }
    } else {
        /* No payload: embed the SQE command inline as the request */
        memcpy(req->buf, ureq, min_t(u32, req->buf_len,
                                     sizeof(struct deepspan_cmd_req)));
    }

    /* Register request in XArray (auto-assign ID) */
    ret = xa_alloc(&ddev->pending, &req_id, req,
                   XA_LIMIT(1, DEEPSPAN_MAX_REQUESTS), GFP_KERNEL);
    if (ret)
        goto err_free_resp;
    req->req_id = req_id;

    /*
     * Build scatter-gather list:
     *   sgs[0] = outbuf (request → firmware)
     *   sgs[1] = inbuf  (result  ← firmware)
     */
    sg_init_one(&sg_out, req->buf,      req->buf_len);
    sg_init_one(&sg_in,  req->resp_buf, req->resp_len);

    spin_lock_bh(&ddev->vq_lock);
    ret = virtqueue_add_sgs(ddev->vqs[VQ_DATA_TX], sgs, 1, 1,
                             req, GFP_ATOMIC);
    if (ret == 0)
        virtqueue_kick(ddev->vqs[VQ_DATA_TX]);
    spin_unlock_bh(&ddev->vq_lock);

    if (ret)
        goto err_xa_erase;

    return -EIOCBQUEUED;  /* async: io_uring_cmd_done() called on TX completion */

err_xa_erase:
    xa_erase(&ddev->pending, req_id);
err_free_resp:
    kfree(req->resp_buf);
err_free_buf:
    kfree(req->buf);
err_free_req:
    kfree(req);
    return ret;
}
