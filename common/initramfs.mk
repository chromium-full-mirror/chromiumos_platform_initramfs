# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Disable implicit rules.
.SUFFIXES:

# How to compress the cpio archive.
COMPRESS = xz -9 --check=crc32

# Staging and build toolchain.
NAME			?= $(notdir $(CURDIR))
OUTPUT_DIR		?= $(CURDIR)
RAMFS_BIN		?= $(OUTPUT_DIR)/$(NAME)_ramfs.cpio.xz
STAGE			?= $(OUTPUT_DIR)/stage_$(NAME)
SYSROOT			?= /
BOARD			?= unknown
BUILD_LIBRARY_DIR	?= $(HOME)/trunk/src/scripts/build_library

RAMFS_BIN_DEPS		?= $(BIN_DEPS) $(EXTRA_BIN_DEPS)
GEN_INIT_CPIO		= $(OUTPUT_DIR)/gen_init_cpio

# Settings for the build system.
BUILD_CC		?= gcc
BUILD_CFLAGS		?= -O1 -pipe
BUILD_CPPFLAGS		?=
BUILD_LDFLAGS		?=

.PHONY: all
all:	$(RAMFS_BIN)

.PHONY: clean
clean:
	rm -rf $(RAMFS_BIN) $(RAMFS_BIN).contents $(STAGE) $(GEN_INIT_CPIO)

$(RAMFS_BIN): $(GEN_INIT_CPIO)

$(GEN_INIT_CPIO): ../common/gen_init_cpio.c
	$(BUILD_CC) $(BUILD_CFLAGS) $(BUILD_CPPFLAGS) $(BUILD_LDFLAGS) $< -o $@

.PHONY: stage_init
stage_init:
	rm -rf "$(STAGE)"
	mkdir -p "$(STAGE)"
	ln -s . "$(STAGE)/usr"
	(cd $(STAGE); mkdir -p $(RAMFS_LAYOUT_DIRS))

	# Use "ln -s" because "mount --bind" may not work in initramfs.
	ln -s bin $(STAGE)/sbin

	lddtree --verbose --copy-non-elfs --root="$(SYSROOT)" \
		--copy-to-tree="$(STAGE)" --bindir=/bin \
		$(RAMFS_BIN_DEPS)
	cp init "$(STAGE)/init"

define generate_initramfs
	../common/gen_initramfs_list.sh -u squash -g squash $(1) >> $(2).contents
	$(GEN_INIT_CPIO) $(2).contents $(if $(COMPRESS),| $(COMPRESS)) > $(2)
endef
define generate_ramfs
	$(call generate_initramfs,$(STAGE),$(RAMFS_BIN))
endef
