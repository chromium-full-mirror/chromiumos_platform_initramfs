# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Dependency list of binary programs.
BIN_DEPS= \
	/bin/busybox \
	/sbin/dmsetup \
	/usr/bin/ply-image \
	/usr/bin/pv \
	/usr/sbin/vpd \
	/usr/sbin/flashrom \
	/usr/bin/futility \
	/usr/bin/crossystem \
	/usr/bin/tpmc \
	/usr/bin/cgpt

DATA_DEPS= \
	/usr/share/misc/chromeos-common.sh

# Layout of directories to be created in initramfs.
RAMFS_LAYOUT_DIRS=\
	bin \
	dev \
	etc \
	etc/screens \
	lib \
	proc \
	root \
	sys \
	tmp \
	usr \
	usr/share/misc \
	newroot \
	stateful \
	usb

# Staging and build toolchain.
OUTPUT_DIR		?= .
STAGE			?= $(OUTPUT_DIR)/stage_recovery
SYSROOT			?= /
BOARD			?= unknown
BUILD_LIBRARY_DIR	?= $(HOME)/trunk/src/scripts/build_library
INTERACTIVE_COMPLETE	?= true

# Output image file names.
# TODO(hungte) Change this to recovery_ramfs.cpio.xz when the migration is over.
RAMFS_BIN=$(OUTPUT_DIR)/initramfs.cpio.xz

.PHONY: clean all

all:	$(RAMFS_BIN)

clean:
	rm -rf $(RAMFS_BIN) $(STAGE)

$(RAMFS_BIN):
	rm -rf "$(STAGE)"; mkdir -p "$(STAGE)"
	(cd $(STAGE); mkdir -p $(RAMFS_LAYOUT_DIRS))
	cp "$(SYSROOT)/usr/share/chromeos-assets/images/boot_message.png" \
		assets/*.png $(STAGE)/etc/screens
	./make_images localized_text "$(STAGE)/etc/screens"
	ln -s lib $(STAGE)/lib64
	ln -s busybox $(STAGE)/bin/sh
	ln -s bin $(STAGE)/sbin
	ln -s bin $(STAGE)/usr/bin
	ln -s bin $(STAGE)/usr/sbin
	ln -s futility "$(STAGE)/bin/dump_kernel_config"
	ln -s futility "$(STAGE)/bin/vbutil_kernel"
	lddtree --verbose --copy-non-elfs --root=$(SYSROOT) \
		--copy-to-tree=$(STAGE) --libdir=/lib --bindir=/bin \
		$(BIN_DEPS)
	lddtree --verbose --copy-non-elfs --root=$(SYSROOT) \
		--copy-to-tree=$(STAGE) --libdir=/lib \
		$(DATA_DEPS)
	cp init $(STAGE)/
	cp *.sh $(STAGE)/lib
	echo "$(INTERACTIVE_COMPLETE)" >$(STAGE)/lib/completion_settings.sh
	(BOARD=$(BOARD) BUILD_LIBRARY_DIR=$(BUILD_LIBRARY_DIR) bash -c \
	 ". $(BUILD_LIBRARY_DIR)/disk_layout_util.sh; \
	 write_partition_script usb $(STAGE)/bin/write_gpt.sh")
	(cd $(STAGE); find . | cpio -o -H newc | xz -9 --check=crc32) >$@
