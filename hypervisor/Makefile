# Copyright 2019 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Dependency list of binary programs.
BIN_DEPS= \
	/bin/busybox \
	/usr/bin/qemu-system-x86_64

# Additional data files to copy from the sysroot.
DATA_DEPS= \
	/boot/vmlinuz \
	/usr/share/qemu/bios-256k.bin \
	/usr/share/qemu/keymaps/en-us \
	/usr/share/qemu/linuxboot_dma.bin \
	/usr/share/qemu/kvmvapic.bin

include ../common/initramfs.mk

$(RAMFS_BIN): stage_init
	ln -s busybox $(STAGE)/bin/sh
	lddtree --verbose --copy-non-elfs --root=$(SYSROOT) \
		--copy-to-tree=$(STAGE) \
		$(DATA_DEPS)
	$(call generate_ramfs)
