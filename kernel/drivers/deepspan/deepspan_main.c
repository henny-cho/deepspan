// SPDX-License-Identifier: GPL-2.0
/*
 * deepspan_main.c - Deepspan HWIP driver module initialization
 *
 * Responsibilities:
 *   - IDA (minor number allocator) management
 *   - class/chrdev region registration
 *   - virtio driver registration
 */

#include <linux/module.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/device.h>
#include <linux/idr.h>	/* IDA — ida.h merged into idr.h in kernel 6.x */
#include <linux/uaccess.h>

#include "deepspan_priv.h"

MODULE_LICENSE("GPL");
MODULE_AUTHOR("myorg");
MODULE_DESCRIPTION("Deepspan HWIP driver");
MODULE_VERSION("0.1.0");

DEFINE_IDA(deepspan_ida);
EXPORT_SYMBOL_GPL(deepspan_ida);

struct class *deepspan_class;
EXPORT_SYMBOL_GPL(deepspan_class);

dev_t deepspan_devt;
EXPORT_SYMBOL_GPL(deepspan_devt);

/* ── file operations ────────────────────────────────────────────── */

static int deepspan_open(struct inode *inode, struct file *filp)
{
    struct deepspan_device *ddev =
        container_of(inode->i_cdev, struct deepspan_device, cdev);
    filp->private_data = ddev;
    return 0;
}

static int deepspan_release(struct inode *inode, struct file *filp)
{
    return 0;
}

static int deepspan_uring_cmd(struct io_uring_cmd *cmd, unsigned int issue_flags)
{
    return deepspan_uring_cmd_issue(cmd, issue_flags);
}

static const struct file_operations deepspan_fops = {
    .owner          = THIS_MODULE,
    .open           = deepspan_open,
    .release        = deepspan_release,
    .uring_cmd      = deepspan_uring_cmd,
    .llseek         = noop_llseek,
};

/* ── cdev helpers ───────────────────────────────────────────────── */

int deepspan_cdev_add(struct deepspan_device *ddev)
{
    int ret;

    ddev->minor = ida_alloc_range(&deepspan_ida, 0,
                                  DEEPSPAN_MAX_DEVICES - 1, GFP_KERNEL);
    if (ddev->minor < 0)
        return ddev->minor;

    cdev_init(&ddev->cdev, &deepspan_fops);
    ddev->cdev.owner = THIS_MODULE;

    ret = cdev_add(&ddev->cdev,
                   MKDEV(MAJOR(deepspan_devt), ddev->minor), 1);
    if (ret) {
        ida_free(&deepspan_ida, ddev->minor);
        return ret;
    }

    ddev->dev = device_create(deepspan_class, NULL,
                              MKDEV(MAJOR(deepspan_devt), ddev->minor),
                              ddev, "hwip%d", ddev->minor);
    if (IS_ERR(ddev->dev)) {
        cdev_del(&ddev->cdev);
        ida_free(&deepspan_ida, ddev->minor);
        return PTR_ERR(ddev->dev);
    }

    return 0;
}

void deepspan_cdev_del(struct deepspan_device *ddev)
{
    device_destroy(deepspan_class,
                   MKDEV(MAJOR(deepspan_devt), ddev->minor));
    cdev_del(&ddev->cdev);
    ida_free(&deepspan_ida, ddev->minor);
}

/* ── module initialization ──────────────────────────────────────── */

static int __init deepspan_init(void)
{
    int ret;

    ret = alloc_chrdev_region(&deepspan_devt, 0,
                              DEEPSPAN_MAX_DEVICES, DEEPSPAN_DRIVER_NAME);
    if (ret)
        return ret;

    deepspan_class = class_create(DEEPSPAN_DRIVER_NAME);
    if (IS_ERR(deepspan_class)) {
        ret = PTR_ERR(deepspan_class);
        goto err_chrdev;
    }

    ret = deepspan_virtio_register();
    if (ret)
        goto err_class;

    pr_info("deepspan: driver loaded (major=%d)\n", MAJOR(deepspan_devt));
    return 0;

err_class:
    class_destroy(deepspan_class);
err_chrdev:
    unregister_chrdev_region(deepspan_devt, DEEPSPAN_MAX_DEVICES);
    return ret;
}

static void __exit deepspan_exit(void)
{
    deepspan_virtio_unregister();
    class_destroy(deepspan_class);
    unregister_chrdev_region(deepspan_devt, DEEPSPAN_MAX_DEVICES);
    ida_destroy(&deepspan_ida);
    pr_info("deepspan: driver unloaded\n");
}

module_init(deepspan_init);
module_exit(deepspan_exit);
