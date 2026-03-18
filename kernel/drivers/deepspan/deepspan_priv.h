/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _DEEPSPAN_PRIV_H
#define _DEEPSPAN_PRIV_H

#include <linux/cdev.h>
#include <linux/virtio.h>
#include <linux/virtio_config.h>  /* vq_callback_t, virtqueue_info, virtio_find_vqs */
#include <linux/virtio_ring.h>
#include <linux/xarray.h>
#include <linux/idr.h>	/* IDA — ida.h merged into idr.h in kernel 6.x */
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
 * @tx_work:     workqueue item — drain TX VQ used buffers (firmware completions)
 * @rx_work:     workqueue item — drain RX VQ (firmware event notifications)
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
    struct work_struct       rx_work;
};

/**
 * struct deepspan_request - single io_uring request tracking structure
 * @cmd:       original io_uring_cmd (io_uring_cmd_done() called on completion)
 * @req_id:    XArray-assigned ID
 * @buf:       outbuf — request data sent to firmware (virtio outbuf)
 * @buf_len:   outbuf size
 * @resp_buf:  inbuf — firmware writes response here (virtio inbuf)
 * @resp_len:  inbuf size (sizeof(struct deepspan_result))
 */
struct deepspan_request {
    struct io_uring_cmd *cmd;
    u32                  req_id;
    void                *buf;
    u32                  buf_len;
    void                *resp_buf;
    u32                  resp_len;
};

/* Global IDA for minor number allocation */
extern struct ida deepspan_ida;
extern struct class *deepspan_class;
extern dev_t deepspan_devt;

/* Function prototypes — deepspan_main.c */
int  deepspan_cdev_add(struct deepspan_device *ddev);
void deepspan_cdev_del(struct deepspan_device *ddev);

/* Function prototypes — deepspan_iouring.c */
int  deepspan_uring_cmd_issue(struct io_uring_cmd *cmd, unsigned int issue_flags);

/* Function prototypes — deepspan_vqueue.c */
void deepspan_vqueue_init(struct deepspan_device *ddev,
                          struct virtqueue_info vqs_info[VQ_COUNT]);
void deepspan_vqueue_cleanup(struct deepspan_device *ddev);

/* Function prototypes — deepspan_virtio.c */
int  deepspan_virtio_register(void);
void deepspan_virtio_unregister(void);

/* Function prototypes — deepspan_sysfs.c */
int  deepspan_sysfs_init(struct deepspan_device *ddev);
void deepspan_sysfs_exit(struct deepspan_device *ddev);

#endif /* _DEEPSPAN_PRIV_H */
