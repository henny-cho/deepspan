# SPDX-License-Identifier: GPL-2.0

obj-$(CONFIG_DEEPSPAN) := deepspan.o

deepspan-objs := \
	deepspan_main.o     \
	deepspan_virtio.o   \
	deepspan_iouring.o  \
	deepspan_vqueue.o   \
	deepspan_sysfs.o

deepspan-$(CONFIG_DEEPSPAN_TRANSPORT_SIM) += deepspan_transport_sim.o
deepspan-$(CONFIG_DEEPSPAN_TRANSPORT_HW)  += deepspan_transport_hw.o

# CRC32 Linux Crypto API shash bridge (optional, enabled by CONFIG_DEEPSPAN_CRC32_SHASH)
obj-$(CONFIG_DEEPSPAN_CRC32_SHASH) += deepspan_crc32_shash.o

obj-$(CONFIG_DEEPSPAN_KUNIT_TEST) += tests/deepspan_test.o

KVERSION ?= $(shell uname -r)
KDIR    ?= /lib/modules/$(KVERSION)/build

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

install:
	$(MAKE) -C $(KDIR) M=$(PWD) modules_install
	depmod -A

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

arm64:
	$(MAKE) -C $(KDIR) M=$(PWD) modules \
		ARCH=arm64 \
		CROSS_COMPILE=aarch64-linux-gnu-
