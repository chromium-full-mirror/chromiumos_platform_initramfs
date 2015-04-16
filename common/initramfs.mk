# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Disable implicit rules.
.SUFFIXES:

# Staging and build toolchain.
NAME			?= $(notdir $(CURDIR))
OUTPUT_DIR		?= $(CURDIR)
RAMFS_BIN		?= $(OUTPUT_DIR)/$(NAME)_ramfs.cpio.xz
STAGE			?= $(OUTPUT_DIR)/stage_$(NAME)
SYSROOT			?= /
BOARD			?= unknown
BUILD_LIBRARY_DIR	?= $(HOME)/trunk/src/scripts/build_library

.PHONY: all
all:	$(RAMFS_BIN)

.PHONY: clean
clean:
	rm -rf $(RAMFS_BIN) $(STAGE)

.PHONY: stage_init
stage_init:
	rm -rf "$(STAGE)"
	mkdir -p "$(STAGE)"
	(cd $(STAGE); mkdir -p $(RAMFS_LAYOUT_DIRS))

	# Use "ln -s" because "mount --bind" may not work in initramfs.
	ln -s lib $(STAGE)/lib64
	ln -s bin $(STAGE)/sbin
	ln -s ../bin $(STAGE)/usr/bin
	ln -s ../bin $(STAGE)/usr/sbin

define generate_ramfs
	(cd $(STAGE); find . | cpio -o -H newc | xz -9 --check=crc32) >$(RAMFS_BIN)
endef
