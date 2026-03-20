#include <linux/module.h>
#include <linux/export-internal.h>
#include <linux/compiler.h>

MODULE_INFO(name, KBUILD_MODNAME);

__visible struct module __this_module
__section(".gnu.linkonce.this_module") = {
	.name = KBUILD_MODNAME,
	.init = init_module,
#ifdef CONFIG_MODULE_UNLOAD
	.exit = cleanup_module,
#endif
	.arch = MODULE_ARCH_INIT,
};

KSYMTAB_DATA(deepspan_ida, "_gpl", "");
KSYMTAB_DATA(deepspan_class, "_gpl", "");
KSYMTAB_DATA(deepspan_devt, "_gpl", "");

SYMBOL_CRC(deepspan_ida, 0xfffef4ad, "_gpl");
SYMBOL_CRC(deepspan_class, 0xbe44457f, "_gpl");
SYMBOL_CRC(deepspan_devt, 0xe29f8ce1, "_gpl");

static const struct modversion_info ____versions[]
__used __section("__versions") = {
	{ 0xd98156e2, "ida_alloc_range" },
	{ 0x9f222e1e, "alloc_chrdev_region" },
	{ 0xa61fd7aa, "__check_object_size" },
	{ 0x9d4cdefd, "virtqueue_enable_cb" },
	{ 0x740648c4, "ida_destroy" },
	{ 0x092a35a2, "_copy_from_user" },
	{ 0xd710adbf, "__kmalloc_noprof" },
	{ 0x49733ad6, "queue_work_on" },
	{ 0xa1dacb42, "class_destroy" },
	{ 0x0c812d3b, "sysfs_remove_groups" },
	{ 0xb0d7d397, "sysfs_create_groups" },
	{ 0xa53f4e29, "memcpy" },
	{ 0xcb8b6ec6, "kfree" },
	{ 0x66526f72, "sg_init_one" },
	{ 0xde338d9a, "_raw_spin_lock" },
	{ 0xd272d446, "__fentry__" },
	{ 0xdd6830c7, "sysfs_emit" },
	{ 0x5a844b26, "__x86_indirect_thunk_rax" },
	{ 0xe8213e80, "_printk" },
	{ 0xbd03ed67, "__ref_stack_chk_guard" },
	{ 0xd272d446, "__stack_chk_fail" },
	{ 0xde338d9a, "_raw_spin_unlock_bh" },
	{ 0x1313ad86, "unregister_virtio_driver" },
	{ 0x9b1de7cb, "_dev_info" },
	{ 0x8ea73856, "cdev_add" },
	{ 0x19028494, "__xa_alloc" },
	{ 0xe486c4b7, "device_create" },
	{ 0x23ef80fb, "noop_llseek" },
	{ 0x653aa194, "class_create" },
	{ 0xbd03ed67, "random_kmalloc_seed" },
	{ 0xd754aaaf, "virtqueue_disable_cb" },
	{ 0x4c3d335e, "ida_free" },
	{ 0x0718a00a, "virtqueue_add_sgs" },
	{ 0x9b1de7cb, "_dev_warn" },
	{ 0xd272d446, "__x86_return_thunk" },
	{ 0x6fde727c, "io_uring_cmd_done" },
	{ 0x108c60d3, "__register_virtio_driver" },
	{ 0x4d8cc270, "virtqueue_get_buf" },
	{ 0x97c20d46, "xa_erase" },
	{ 0x0bc5fb0d, "unregister_chrdev_region" },
	{ 0x34cb32a4, "virtqueue_kick" },
	{ 0x3017bf34, "xa_destroy" },
	{ 0x1595e410, "device_destroy" },
	{ 0xc064623f, "__kmalloc_cache_noprof" },
	{ 0x2d88a3ab, "cancel_work_sync" },
	{ 0x546c19d9, "validate_usercopy_range" },
	{ 0xde338d9a, "_raw_spin_lock_bh" },
	{ 0xde338d9a, "_raw_spin_unlock" },
	{ 0xd5f66efd, "cdev_init" },
	{ 0x7851be11, "__SCT__might_resched" },
	{ 0xfaabfe5e, "kmalloc_caches" },
	{ 0x4e54d6ac, "cdev_del" },
	{ 0xaef1f20d, "system_wq" },
	{ 0xbebe66ff, "module_layout" },
};

static const u32 ____version_ext_crcs[]
__used __section("__version_ext_crcs") = {
	0xd98156e2,
	0x9f222e1e,
	0xa61fd7aa,
	0x9d4cdefd,
	0x740648c4,
	0x092a35a2,
	0xd710adbf,
	0x49733ad6,
	0xa1dacb42,
	0x0c812d3b,
	0xb0d7d397,
	0xa53f4e29,
	0xcb8b6ec6,
	0x66526f72,
	0xde338d9a,
	0xd272d446,
	0xdd6830c7,
	0x5a844b26,
	0xe8213e80,
	0xbd03ed67,
	0xd272d446,
	0xde338d9a,
	0x1313ad86,
	0x9b1de7cb,
	0x8ea73856,
	0x19028494,
	0xe486c4b7,
	0x23ef80fb,
	0x653aa194,
	0xbd03ed67,
	0xd754aaaf,
	0x4c3d335e,
	0x0718a00a,
	0x9b1de7cb,
	0xd272d446,
	0x6fde727c,
	0x108c60d3,
	0x4d8cc270,
	0x97c20d46,
	0x0bc5fb0d,
	0x34cb32a4,
	0x3017bf34,
	0x1595e410,
	0xc064623f,
	0x2d88a3ab,
	0x546c19d9,
	0xde338d9a,
	0xde338d9a,
	0xd5f66efd,
	0x7851be11,
	0xfaabfe5e,
	0x4e54d6ac,
	0xaef1f20d,
	0xbebe66ff,
};
static const char ____version_ext_names[]
__used __section("__version_ext_names") =
	"ida_alloc_range\0"
	"alloc_chrdev_region\0"
	"__check_object_size\0"
	"virtqueue_enable_cb\0"
	"ida_destroy\0"
	"_copy_from_user\0"
	"__kmalloc_noprof\0"
	"queue_work_on\0"
	"class_destroy\0"
	"sysfs_remove_groups\0"
	"sysfs_create_groups\0"
	"memcpy\0"
	"kfree\0"
	"sg_init_one\0"
	"_raw_spin_lock\0"
	"__fentry__\0"
	"sysfs_emit\0"
	"__x86_indirect_thunk_rax\0"
	"_printk\0"
	"__ref_stack_chk_guard\0"
	"__stack_chk_fail\0"
	"_raw_spin_unlock_bh\0"
	"unregister_virtio_driver\0"
	"_dev_info\0"
	"cdev_add\0"
	"__xa_alloc\0"
	"device_create\0"
	"noop_llseek\0"
	"class_create\0"
	"random_kmalloc_seed\0"
	"virtqueue_disable_cb\0"
	"ida_free\0"
	"virtqueue_add_sgs\0"
	"_dev_warn\0"
	"__x86_return_thunk\0"
	"io_uring_cmd_done\0"
	"__register_virtio_driver\0"
	"virtqueue_get_buf\0"
	"xa_erase\0"
	"unregister_chrdev_region\0"
	"virtqueue_kick\0"
	"xa_destroy\0"
	"device_destroy\0"
	"__kmalloc_cache_noprof\0"
	"cancel_work_sync\0"
	"validate_usercopy_range\0"
	"_raw_spin_lock_bh\0"
	"_raw_spin_unlock\0"
	"cdev_init\0"
	"__SCT__might_resched\0"
	"kmalloc_caches\0"
	"cdev_del\0"
	"system_wq\0"
	"module_layout\0"
;

MODULE_INFO(depends, "");

MODULE_ALIAS("virtio:d0000105Av*");

MODULE_INFO(srcversion, "41A6B92A2646EDD4AFC9604");
