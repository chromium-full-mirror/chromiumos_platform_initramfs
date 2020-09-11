# Copyright 2019 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Dependency list of binary programs.
BIN_DEPS= \
	/bin/busybox \
	/build/initramfs/trichechus \
	/usr/bin/crosvm

# Additional data files to copy from the sysroot.
DATA_DEPS= \
	/boot/vmlinuz

include ../common/initramfs.mk

$(RAMFS_BIN): stage_init
	ln -s busybox $(STAGE)/bin/sh
	lddtree --verbose --copy-non-elfs --root=$(SYSROOT) \
		--copy-to-tree=$(STAGE) \
		$(DATA_DEPS)
	$(call generate_ramfs)
