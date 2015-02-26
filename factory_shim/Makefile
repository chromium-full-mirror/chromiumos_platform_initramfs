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

# Staging and build toolchain.
OUTPUT_DIR		?= .
STAGE			?= $(OUTPUT_DIR)/stage_shim
SYSROOT			?= /

# Output image file names.
RAMFS_BIN=$(OUTPUT_DIR)/factory_shim_ramfs.cpio.xz

.PHONY: clean all

all:	$(RAMFS_BIN)

clean:
	rm -rf $(RAMFS_BIN) $(STAGE)

$(RAMFS_BIN):
	rm -rf "$(STAGE)"; mkdir -p "$(STAGE)"
	(cd $(STAGE); mkdir -p $(RAMFS_LAYOUT_DIRS))
	# Use "ln -s" because "mount --bind" may not work in initramfs.
	ln -s lib $(STAGE)/lib64
	ln -s bin $(STAGE)/sbin
	ln -s ../bin $(STAGE)/usr/bin
	ln -s ../bin $(STAGE)/usr/sbin
	lddtree --verbose --copy-non-elfs --root=$(SYSROOT) \
		--copy-to-tree=$(STAGE) --libdir=/lib --bindir=/bin \
		$(BIN_DEPS) $(EXTRA_BIN_DEPS)
	cp init $(STAGE)/
	cp bootstrap.sh $(STAGE)/bin
	(cd $(STAGE); find . | cpio -o -H newc | xz -9 --check=crc32) >$@
