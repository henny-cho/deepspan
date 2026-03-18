// SPDX-License-Identifier: GPL-2.0
/*
 * deepspan_vqueue.c - VirtQueue RX/TX callbacks and workqueue completion handlers
 *
 * TX VQ (host→firmware): carries deepspan_req (outbuf) + deepspan_result slot (inbuf).
 *   - Firmware reads the request, writes the result, and returns the descriptor.
 *   - TX VQ IRQ → deepspan_vq_tx_cb() → schedules tx_work.
 *   - tx_work drains used TX descriptors → io_uring_cmd_done() on each.
 *
 * RX VQ (firmware→host): used for unsolicited firmware notifications (future).
 *   - RX VQ IRQ → deepspan_vq_rx_cb() → schedules rx_work.
 *   - rx_work drains used RX descriptors (stubbed for now).
 *
 * deepspan_vqueue_init() must be called before virtio_find_vqs() to populate
 * the cbs[] array and initialise the workqueue items.
 */

#include <linux/virtio.h>
#include <linux/virtio_config.h>
#include <linux/slab.h>
#include <linux/io_uring/cmd.h>

#include "deepspan_priv.h"

/* UAPI result struct — must match include/uapi/linux/deepspan.h */
struct deepspan_result_hdr {
    __s32 status;
    __u32 result_lo;
    __u32 result_hi;
    __u32 _pad;
};

/* ── TX workqueue handler ────────────────────────────────────────────── */

/*
 * deepspan_tx_work_fn - drain TX VQ used descriptors and complete io_uring ops.
 *
 * Called from process context via workqueue.  Firmware has written the result
 * into req->resp_buf and returned the descriptor chain.
 */
static void deepspan_tx_work_fn(struct work_struct *work)
{
    struct deepspan_device *ddev =
        container_of(work, struct deepspan_device, tx_work);
    struct virtqueue *tx_vq = ddev->vqs[VQ_DATA_TX];
    struct deepspan_request *req;
    unsigned int len;

    spin_lock_bh(&ddev->vq_lock);
    while ((req = virtqueue_get_buf(tx_vq, &len)) != NULL) {
        spin_unlock_bh(&ddev->vq_lock);

        /* Remove from pending XArray before completion */
        xa_erase(&ddev->pending, req->req_id);

        /* Extract result written by firmware into the inbuf slot */
        ssize_t status = 0;
        u64     res2   = 0;

        if (req->resp_buf && req->resp_len >= sizeof(struct deepspan_result_hdr)) {
            const struct deepspan_result_hdr *r = req->resp_buf;
            status = r->status;
            res2   = (u64)r->result_lo | ((u64)r->result_hi << 32);
        }

        /* Signal io_uring completion — issue_flags=0: called from process ctx */
        io_uring_cmd_done(req->cmd, status, res2, 0);

        kfree(req->resp_buf);
        kfree(req->buf);
        kfree(req);

        spin_lock_bh(&ddev->vq_lock);
    }

    /* Re-enable callbacks so we get notified on the next batch */
    virtqueue_enable_cb(tx_vq);
    spin_unlock_bh(&ddev->vq_lock);
}

/* ── TX VQ callback (softirq context) ───────────────────────────────── */

static void deepspan_vq_tx_cb(struct virtqueue *vq)
{
    struct deepspan_device *ddev = vq->vdev->priv;

    /*
     * Disable callbacks to avoid re-entrancy while the work function is
     * processing: the work function re-enables them after draining the VQ.
     */
    virtqueue_disable_cb(vq);
    schedule_work(&ddev->tx_work);
}

/* ── RX workqueue handler ────────────────────────────────────────────── */

/*
 * deepspan_rx_work_fn - drain RX VQ used descriptors.
 *
 * The RX VQ carries unsolicited notifications from firmware (e.g. log entries,
 * state-change events).  Placeholder for future event streaming support.
 */
static void deepspan_rx_work_fn(struct work_struct *work)
{
    struct deepspan_device *ddev =
        container_of(work, struct deepspan_device, rx_work);
    struct virtqueue *rx_vq = ddev->vqs[VQ_DATA_RX];
    void *token;
    unsigned int len;

    spin_lock_bh(&ddev->vq_lock);
    while ((token = virtqueue_get_buf(rx_vq, &len)) != NULL) {
        /* TODO: dispatch firmware event notification (Phase 3+) */
        (void)token;
        (void)len;
    }
    virtqueue_enable_cb(rx_vq);
    spin_unlock_bh(&ddev->vq_lock);
}

/* ── RX VQ callback (softirq context) ───────────────────────────────── */

static void deepspan_vq_rx_cb(struct virtqueue *vq)
{
    struct deepspan_device *ddev = vq->vdev->priv;

    virtqueue_disable_cb(vq);
    schedule_work(&ddev->rx_work);
}

/* ── Public init / cleanup ───────────────────────────────────────────── */

/**
 * deepspan_vqueue_init - wire VQ callbacks and initialise workqueue items.
 * @ddev:     deepspan device
 * @vqs_info: virtqueue_info array passed to virtio_find_vqs() — populated here
 *
 * Must be called BEFORE virtio_find_vqs().
 */
void deepspan_vqueue_init(struct deepspan_device *ddev,
                          struct virtqueue_info vqs_info[VQ_COUNT])
{
    vqs_info[VQ_DATA_TX].name     = "tx";
    vqs_info[VQ_DATA_TX].callback = deepspan_vq_tx_cb;

    vqs_info[VQ_DATA_RX].name     = "rx";
    vqs_info[VQ_DATA_RX].callback = deepspan_vq_rx_cb;

    INIT_WORK(&ddev->tx_work, deepspan_tx_work_fn);
    INIT_WORK(&ddev->rx_work, deepspan_rx_work_fn);
}

/**
 * deepspan_vqueue_cleanup - cancel pending work items on device removal.
 * @ddev: deepspan device
 */
void deepspan_vqueue_cleanup(struct deepspan_device *ddev)
{
    cancel_work_sync(&ddev->tx_work);
    cancel_work_sync(&ddev->rx_work);
}
