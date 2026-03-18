// SPDX-License-Identifier: GPL-2.0
/*
 * deepspan_virtio.c - virtio driver probe/remove
 *
 * Linux is virtio master (driver), Zephyr is virtio slave (device).
 * probe: virtqueue setup, cdev registration
 * remove: cdev release, XArray cleanup
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
    vq_callback_t *cbs[VQ_COUNT] = { NULL, NULL };  /* set in vqueue.c */
    const char *names[VQ_COUNT]  = { "tx", "rx" };
    int ret;

    ddev = kzalloc(sizeof(*ddev), GFP_KERNEL);
    if (!ddev)
        return -ENOMEM;

    ddev->vdev = vdev;
    vdev->priv = ddev;
    spin_lock_init(&ddev->vq_lock);
    xa_init(&ddev->pending);
    INIT_WORK(&ddev->tx_work, NULL);  /* set in iouring.c */

    /* Allocate virtqueues */
    ret = virtio_find_vqs(vdev, VQ_COUNT, vqs, cbs, names, NULL);
    if (ret)
        goto err_free;

    ddev->vqs[VQ_DATA_TX] = vqs[VQ_DATA_TX];
    ddev->vqs[VQ_DATA_RX] = vqs[VQ_DATA_RX];

    virtio_device_ready(vdev);

    ret = deepspan_cdev_add(ddev);
    if (ret)
        goto err_vqs;

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

/* Called from module_init in deepspan_main.c */
int deepspan_virtio_register(void)
{
    return register_virtio_driver(&deepspan_virtio_driver);
}

void deepspan_virtio_unregister(void)
{
    unregister_virtio_driver(&deepspan_virtio_driver);
}
