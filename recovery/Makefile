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

# Extra dependency, should be set by builder configuration.
EXTRA_BIN_DEPS?=

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
	log \
	newroot \
	stateful \
	usb

INTERACTIVE_COMPLETE	?= true

# Any files here will be overlayed to the initramfs folder.
OVERLAY_FOLDER		?= $(SYSROOT)/var/lib/initramfs/recovery

# LOCALE_LIST can be overridden on the command line.  This feature
# is used in the ebuild to allow board-specific locale lists.
LOCALE_LIST		=

# The region database installed by virtual/chromeos-regions, and will be used to
# generate the locales table.
CROS_REGIONS_DATABASE	?= $(SYSROOT)/usr/share/misc/cros-regions.json
LOCALES_TABLE		?= $(STAGE)/etc/locales.txt

include ../common/initramfs.mk

$(RAMFS_BIN): stage_init
	cp "$(SYSROOT)/usr/share/chromeos-assets/images/boot_message.png" \
		assets/*.png $(STAGE)/etc/screens
	./make_images localized_text "$(STAGE)/etc/screens" $(LOCALE_LIST)
	./make_locales "$(CROS_REGIONS_DATABASE)" >"$(LOCALES_TABLE)"
	ln -s busybox $(STAGE)/bin/sh
	ln -s futility "$(STAGE)/bin/dump_kernel_config"
	ln -s futility "$(STAGE)/bin/vbutil_kernel"
	lddtree --verbose --copy-non-elfs --root=$(SYSROOT) \
		--copy-to-tree=$(STAGE) \
		$(DATA_DEPS)
	cp *.sh $(STAGE)/lib
	echo "INTERACTIVE_COMPLETE=$(INTERACTIVE_COMPLETE)" \
		>$(STAGE)/lib/completion_settings.sh
	[ ! -d "$(OVERLAY_FOLDER)" ] || rsync -av $(OVERLAY_FOLDER)/* "$(STAGE)"
	(BOARD=$(BOARD) BUILD_LIBRARY_DIR=$(BUILD_LIBRARY_DIR) bash -c \
	 ". $(BUILD_LIBRARY_DIR)/disk_layout_util.sh; \
	 write_partition_script usb $(STAGE)/bin/write_gpt.sh")
	$(call generate_ramfs)
