savedcmd_deepspan.mod := printf '%s\n'   deepspan_main.o deepspan_virtio.o deepspan_iouring.o deepspan_vqueue.o deepspan_sysfs.o | awk '!x[$$0]++ { print("./"$$0) }' > deepspan.mod
