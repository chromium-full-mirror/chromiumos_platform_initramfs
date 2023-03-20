# ChromiumOS initramfs

Build logic for creating standalone initramfs environments.

See the README files in the respective subdirs for more details.

[TOC]

## Using

Normally you wouldn't build in this directory directly.  Instead, you would
build the chromeos-initramfs package with the right USE flags.  e.g.:

`$ USE=recovery_ramfs emerge-$BOARD chromeos-initramfs`

That will install the cpio initramfs files into the sysroot for you to build
into a kernel directly.  The various build scripts would then be used to make
the right kernel/image using those (e.g. mod_image_for_recovery.sh).

## Building

You could build these by hand for quick testing.  Inside the chroot:

`$ make SYSROOT=/build/$BOARD BOARD=$BOARD <target>`

That will create the cpio archives for you.

## Debugging

It is possible to debug few of the initramfs targets in QEMU. Read
[test/README.md](test/README.md) for more information.

Also, here is a shortcut for developing/debugging graphical bits in initramfs,
without having to create a full image for every iteration.

After `emerge-$BOARD`, find your initramfs package from chroot
`/build/$BOARD/var/lib/initramfs` and copy to a running DUT, for example
`/tmp/recovery_ramfs.cpio`, then do followings on DUT over SSH:

1. `mkdir /usr/local/test/; cd /usr/local/test`
2. `xzcat /tmp/XXXXXX_ramfs.cpio | toybox cpio -iv`
(Here we assume that the kernel is configured to use xz compression for its initramfs.)
3. `stop ui; kill $(pidof frecon)`
4. bind mount /dev, /proc, /sys and /tmp in /usr/local/test:
```
for d in dev proc sys tmp; do
   mount --bind /${d} /usr/local/test/${d}
done
```
5. `chroot /usr/local/test /init`
6. Iterate.
