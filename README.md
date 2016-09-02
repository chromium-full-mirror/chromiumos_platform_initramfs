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
