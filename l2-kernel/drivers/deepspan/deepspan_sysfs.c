// SPDX-License-Identifier: GPL-2.0
/*
 * deepspan_sysfs.c - sysfs device attributes for /sys/class/hwip/hwipN/
 *
 * Exported attributes:
 *   version  — DEEPSPAN_UAPI_VERSION (read-only)
 */

#include <linux/device.h>
#include <linux/sysfs.h>

#include "deepspan_priv.h"

/* Kernel headers do not pull in the UAPI header — include it explicitly */
#include "../../include/uapi/linux/deepspan.h"

/* ── Attributes ─────────────────────────────────────────────────────── */

static ssize_t version_show(struct device *dev,
                             struct device_attribute *attr,
                             char *buf)
{
    return sysfs_emit(buf, "%u\n", DEEPSPAN_UAPI_VERSION);
}
static DEVICE_ATTR_RO(version);

static struct attribute *deepspan_dev_attrs[] = {
    &dev_attr_version.attr,
    NULL,
};
ATTRIBUTE_GROUPS(deepspan_dev);

/* ── Init / exit ─────────────────────────────────────────────────────── */

int deepspan_sysfs_init(struct deepspan_device *ddev)
{
    return sysfs_create_groups(&ddev->dev->kobj, deepspan_dev_groups);
}

void deepspan_sysfs_exit(struct deepspan_device *ddev)
{
    sysfs_remove_groups(&ddev->dev->kobj, deepspan_dev_groups);
}
