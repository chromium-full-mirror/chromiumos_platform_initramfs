# Testing Chromium OS initramfs environments

The code in here will help you test out the various initramfs environments in
a QEMU VM.  This way you don't have to generate the image, write it to a USB
stick, and then boot it on a real device.

Caveat: This stuff might have rough edges.

## Setup

You must first run `./build_packages` for the board you want to test.
Most likely that means `amd64-generic`.

## Usage

You must run this inside the chroot.

Use the `test.sh` script in here to compile the initramfs rootfs, kernel, disk
image, and qemu wrapper script to test each environment out.

Artifacts will be placed in the typical `~/trunk/src/build/initramfs/` tree.
In there you'll find a directory for each target.  In there you'll find all
the relevant files and a helper `qemu` script.  Run that to boot the system.

Note that `recovery` images require a GUI.  The rest can be tested via the
command line (as the console will be via an emulated serial port).
