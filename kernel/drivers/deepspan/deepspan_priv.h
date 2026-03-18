/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _DEEPSPAN_PRIV_H
#define _DEEPSPAN_PRIV_H

#include <linux/cdev.h>
#include <linux/virtio.h>
#include <linux/virtio_ring.h>
#include <linux/xarray.h>
#include <linux/ida.h>
#include <linux/io_uring/cmd.h>
#include <linux/spinlock.h>
#include <linux/workqueue.h>

#define DEEPSPAN_DRIVER_NAME    "deepspan"
#define DEEPSPAN_MAX_DEVICES    16
#define DEEPSPAN_MAX_REQUESTS   4096

/* virtio device/vendor ID */
#define VIRTIO_ID_DEEPSPAN_DATA 0x105A   /* data plane VQ */
#define VIRTIO_ID_DEEPSPAN_MGMT 0x105B   /* management VQ */

/* virtqueue index */
#define VQ_DATA_TX  0
#define VQ_DATA_RX  1
#define VQ_COUNT    2

/**
 * struct deepspan_device - device instance (per /dev/hwipN)
 * @vdev:        virtio device
 * @vqs:         virtqueue array [VQ_DATA_TX, VQ_DATA_RX]
 * @pending:     XArray: request_id → io_uring_cmd (async tracking)
 * @cdev:        character device
 * @dev:         sysfs device
 * @minor:       minor number allocated by IDA
 * @vq_lock:     virtqueue access spinlock
 * @tx_work:     TX completion workqueue item
 */
struct deepspan_device {
    struct virtio_device    *vdev;
    struct virtqueue        *vqs[VQ_COUNT];
    struct xarray            pending;       /* xa_limit: 1..MAX_REQUESTS */
    struct cdev              cdev;
    struct device           *dev;
    int                      minor;
    spinlock_t               vq_lock;
    struct work_struct       tx_work;
};

/**
 * struct deepspan_request - single io_uring request tracking structure
 * @cmd:      original io_uring_cmd (io_uring_cmd_done() called on completion)
 * @req_id:   XArray-assigned ID
 * @buf:      DMA buffer (virtio scatterlist)
 * @buf_len:  buffer size
 */
struct deepspan_request {
    struct io_uring_cmd *cmd;
    u32                  req_id;
    void                *buf;
    u32                  buf_len;
};

/* Global IDA for minor number allocation */
extern struct ida deepspan_ida;
extern struct class *deepspan_class;
extern dev_t deepspan_devt;

/* Function prototypes */
int  deepspan_cdev_add(struct deepspan_device *ddev);
void deepspan_cdev_del(struct deepspan_device *ddev);
int  deepspan_iouring_register(struct deepspan_device *ddev);

#endif /* _DEEPSPAN_PRIV_H */
