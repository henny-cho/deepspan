// SPDX-License-Identifier: GPL-2.0
/*
 * deepspan_virtio.c - virtio driver probe/remove
 *
 * Linux is virtio master (driver), Zephyr is virtio slave (device).
 * probe: virtqueue setup (callbacks wired by deepspan_vqueue_init),
 *        cdev registration, sysfs init
 * remove: workqueue flush, cdev release, XArray cleanup
 */

#include <linux/module.h>
#include <linux/virtio.h>
#include <linux/virtio_ids.h>
#include <linux/slab.h>

#include "deepspan_priv.h"

static int deepspan_virtio_probe(struct virtio_device *vdev)
{
    struct deepspan_device *ddev;
    struct virtqueue *vqs[VQ_COUNT];
    struct virtqueue_info vqs_info[VQ_COUNT] = {};
    int ret;

    ddev = kzalloc(sizeof(*ddev), GFP_KERNEL);
    if (!ddev)
        return -ENOMEM;

    ddev->vdev = vdev;
    vdev->priv = ddev;
    spin_lock_init(&ddev->vq_lock);
    xa_init(&ddev->pending);

    /* Wire VQ callbacks and initialise workqueue items */
    deepspan_vqueue_init(ddev, vqs_info);

    /* Allocate virtqueues with callbacks */
    ret = virtio_find_vqs(vdev, VQ_COUNT, vqs, vqs_info, NULL);
    if (ret)
        goto err_free;

    ddev->vqs[VQ_DATA_TX] = vqs[VQ_DATA_TX];
    ddev->vqs[VQ_DATA_RX] = vqs[VQ_DATA_RX];

    virtio_device_ready(vdev);

    ret = deepspan_cdev_add(ddev);
    if (ret)
        goto err_vqs;

    ret = deepspan_sysfs_init(ddev);
    if (ret) {
        /* Non-fatal: sysfs failure does not prevent device operation */
        dev_warn(ddev->dev, "sysfs init failed (%d), continuing\n", ret);
    }

    dev_info(ddev->dev, "deepspan: hwip%d probed\n", ddev->minor);
    return 0;

err_vqs:
    vdev->config->del_vqs(vdev);
err_free:
    xa_destroy(&ddev->pending);
    kfree(ddev);
    return ret;
}

static void deepspan_virtio_remove(struct virtio_device *vdev)
{
    struct deepspan_device *ddev = vdev->priv;

    deepspan_sysfs_exit(ddev);
    deepspan_vqueue_cleanup(ddev);
    deepspan_cdev_del(ddev);
    vdev->config->reset(vdev);
    vdev->config->del_vqs(vdev);
    xa_destroy(&ddev->pending);
    kfree(ddev);
}

static const struct virtio_device_id deepspan_virtio_id_table[] = {
    { VIRTIO_ID_DEEPSPAN_DATA, VIRTIO_DEV_ANY_ID },
    { 0 },
};
MODULE_DEVICE_TABLE(virtio, deepspan_virtio_id_table);

static struct virtio_driver deepspan_virtio_driver = {
    .driver.name    = DEEPSPAN_DRIVER_NAME,
    .driver.owner   = THIS_MODULE,
    .id_table       = deepspan_virtio_id_table,
    .probe          = deepspan_virtio_probe,
    .remove         = deepspan_virtio_remove,
};

int deepspan_virtio_register(void)
{
    return register_virtio_driver(&deepspan_virtio_driver);
}

void deepspan_virtio_unregister(void)
{
    unregister_virtio_driver(&deepspan_virtio_driver);
}
