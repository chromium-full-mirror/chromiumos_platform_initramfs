# Chromium OS initramfs

Build logic for creating standalone initramfs environments.

See the README files in the respective subdirs for more details.


To Use
======

Normally you wouldn't build in this directory directly.  Instead, you would
build the chromeos-initramfs package with the right USE flags.  e.g.:

`$ USE=recovery_ramfs emerge-$BOARD chromeos-initramfs`

That will install the cpio initramfs files into the sysroot for you to build
into a kernel directly.  The various build scripts would then be used to make
the right kernel/image using those (e.g. mod_image_for_recovery.sh).


To Make
=======

You could build these by hand for quick testing.  Inside the chroot:

`$ make SYSROOT=/build/$BOARD BOARD=$BOARD <target>`

That will create the cpio archives for you.

To Debug
========
It is possible to debug few of the initramfs targets in QEMU. Read
[test/README.md](test/README.md) for more information.

Also, here is a shortcut for developing/debugging graphical bits in initramfs,
without having to create a full image for every iteration.

After `emerge-$BOARD`, find your initramfs package from chroot
`/build/$BOARD/var/lib/initramfs` and copy to a running DUT, for example
`/tmp/recovery_ramfs.cpio.xz`, then do followings on DUT:

1. `mount -o remount,exec /mnt/stateful_partition`
2. `mkdir /mnt/stateful_partition/test; cd /mnt/stateful_partition/test`
3. `xzcat /tmp/XXXXXX_ramfs.cpio.xz | cpio -iv`
4. `stop ui; kill $(pidof frecon)`
5. `bind mount /dev, /proc, /sys and /tmp in /mnt/stateful_partition/test`
6. `chroot /mnt/stateful_partition/test/init`
7. Iterate.
