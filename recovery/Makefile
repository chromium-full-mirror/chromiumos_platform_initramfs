# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Dependency list of binary programs.
BIN_DEPS= \
	/bin/busybox \
	/sbin/dmsetup \
	/sbin/frecon-lite \
	/usr/bin/eject \
	/usr/bin/pv \
	/usr/sbin/vpd \
	/usr/sbin/flashrom \
	/usr/bin/futility \
	/usr/bin/crossystem \
	/usr/sbin/mosys \
	/usr/bin/tpmc \
	/usr/bin/cgpt \
	/usr/sbin/evwaitkey \
	/usr/bin/cros_oobe_crypto

# Extra dependency, should be set by builder configuration.
EXTRA_BIN_DEPS?=

DATA_DEPS= \
	/usr/share/misc/chromeos-common.sh

LOCAL_BIN_DEPS= \
	$(AOA_SWITCH)

# Layout of directories to be created in initramfs.
RAMFS_LAYOUT_DIRS=\
	etc/screens \
	usr/share/misc \
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
CONFIG_FOLDER		?= $(STAGE)/etc/cros-initramfs

ifeq ($(MENU_UI),1)
UI=menu_ui
else
UI=legacy_ui
endif

include ../common/initramfs.mk

$(RAMFS_BIN): $(UI) stage_init
	./make_locales "$(CROS_REGIONS_DATABASE)" >"$(LOCALES_TABLE)"
	ln -s busybox $(STAGE)/bin/sh
	ln -s futility "$(STAGE)/bin/dump_kernel_config"
	ln -s futility "$(STAGE)/bin/vbutil_kernel"
	lddtree --verbose --copy-non-elfs --root=$(SYSROOT) \
		--copy-to-tree=$(STAGE) \
		$(DATA_DEPS)
	echo "INTERACTIVE_COMPLETE=$(INTERACTIVE_COMPLETE)" \
		>$(STAGE)/lib/completion_settings.sh
	[ ! -d "$(OVERLAY_FOLDER)" ] || rsync -av $(OVERLAY_FOLDER)/* "$(STAGE)"
	mkdir -p "$(CONFIG_FOLDER)"
	[ "$(DETACHABLE)" -eq 0 ] || touch "$(CONFIG_FOLDER)/is_detachable"
	[ "$(PHYSICAL_PRESENCE)" != "power" ] || \
		touch "$(CONFIG_FOLDER)/is_physical_presence_power"
	[ "$(PHYSICAL_PRESENCE)" != "recovery" ] || \
		touch "$(CONFIG_FOLDER)/is_physical_presence_recovery"
	(BOARD=$(BOARD) BUILD_LIBRARY_DIR=$(BUILD_LIBRARY_DIR) bash -c \
	 ". $(BUILD_LIBRARY_DIR)/disk_layout_util.sh; \
	 write_partition_script usb $(STAGE)/bin/write_gpt.sh")
	$(call generate_ramfs)

.PHONY: legacy_ui
legacy_ui: stage_init
	cp "$(SYSROOT)/usr/share/chromeos-assets/images/boot_message.png" \
		legacy_ui/assets/*.png "$(STAGE)/etc/screens"
	legacy_ui/make_images localized_text "$(STAGE)/etc/screens" \
		$(LOCALE_LIST)
	cp *.sh legacy_ui/*.sh "$(STAGE)/lib"

.PHONY: menu_ui
menu_ui: stage_init
	menu_ui/make_images localized_text "$(STAGE)/etc/screens" \
		$(LOCALE_LIST)
	cp *.sh menu_ui/*.sh "$(STAGE)/lib"
