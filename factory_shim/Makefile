# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Dependency list of binary programs.
BIN_DEPS= \
	/bin/busybox \
	/bin/sh \
	/usr/bin/cgpt \
	/usr/bin/crossystem

# Extra dependency, should be set by builder configuration.
EXTRA_BIN_DEPS?=

# Layout of directories to be created in initramfs.
RAMFS_LAYOUT_DIRS=\
	bin \
	dev \
	etc \
	lib \
	proc \
	root \
	sys \
	tmp \
	usr/share/misc \
	var/empty \
	var/log

include ../common/initramfs.mk

$(RAMFS_BIN): stage_init
	lddtree --verbose --copy-non-elfs --root=$(SYSROOT) \
		--copy-to-tree=$(STAGE) --libdir=/lib --bindir=/bin \
		$(BIN_DEPS) $(EXTRA_BIN_DEPS)
	cp init $(STAGE)/
	cp bootstrap.sh $(STAGE)/bin
	$(call generate_ramfs)
