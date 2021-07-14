# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Dependency list of binary programs.
BIN_DEPS = \
	/bin/busybox \
	/sbin/dmsetup \
	/sbin/frecon-lite \
	/usr/bin/eject \
	/usr/bin/pv \
	/usr/bin/futility \
	/usr/bin/crossystem \
	/usr/bin/tpmc \
	/usr/bin/cgpt \
	/usr/bin/cros_oobe_crypto \
	/usr/sbin/evwaitkey \
	/usr/sbin/flashrom \
	/usr/sbin/mosys \
	/usr/sbin/vpd

ifdef MINIOS_BIN_DEPS
BIN_DEPS += $(MINIOS_BIN_DEPS)
endif

# Override this value when including this Makefile.
RECOVERY_DIR ?= $(CURDIR)

# Extra dependency, should be set by builder configuration.
EXTRA_BIN_DEPS ?=

DATA_DEPS = \
	/usr/share/misc/chromeos-common.sh

LOCAL_BIN_DEPS = \
	$(AOA_SWITCH)

# Layout of directories to be created in initramfs.
RAMFS_LAYOUT_DIRS = \
	etc/screens \
	usr/share/misc \
	newroot \
	stateful \
	usb

ifdef MINIOS_RAMFS_LAYOUT_DIRS
RAMFS_LAYOUT_DIRS += $(MINIOS_RAMFS_LAYOUT_DIRS)
endif

INTERACTIVE_COMPLETE ?= true

# Any files here will be overlayed to the initramfs folder.
OVERLAY_FOLDER ?= $(SYSROOT)/var/lib/initramfs/recovery

# LOCALE_LIST can be overridden on the command line.  This feature
# is used in the ebuild to allow board-specific locale lists.
LOCALE_LIST =

# The region database installed by virtual/chromeos-regions, and will be used to
# generate the locales table.
CROS_REGIONS_DATABASE ?= $(SYSROOT)/usr/share/misc/cros-regions.json
LOCALES_TABLE ?= $(STAGE)/etc/locales.txt
CONFIG_FOLDER ?= $(STAGE)/etc/cros-initramfs

ifeq ($(LEGACY_UI),1)
UI = legacy_ui
ifeq ($(MINIOS),1)
$(error "Cannot build miniOS on legacy_ui")
endif
else
UI = menu_ui
ifeq ($(MINIOS),1)
UI = minios_ui
endif
endif

include ../common/initramfs.mk

$(RAMFS_BIN): $(UI) stage_init
	$(RECOVERY_DIR)/make_locales "$(CROS_REGIONS_DATABASE)" >"$(LOCALES_TABLE)"
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
	[ "$(OOBE_CONFIG)" -eq 0 ] || touch "$(CONFIG_FOLDER)/use_oobe_config"
	(BOARD=$(BOARD) BUILD_LIBRARY_DIR=$(BUILD_LIBRARY_DIR) bash -c \
	 ". $(BUILD_LIBRARY_DIR)/disk_layout_util.sh; \
	 write_partition_script usb $(STAGE)/bin/write_gpt.sh")
	$(call generate_ramfs)

.PHONY: legacy_ui
legacy_ui: stage_init
	cp "$(SYSROOT)/usr/share/chromeos-assets/images/boot_message_light.png" \
		legacy_ui/assets/*.png "$(STAGE)/etc/screens"
	legacy_ui/make_images localized_text "$(STAGE)/etc/screens" \
		$(LOCALE_LIST)
	cp *.sh legacy_ui/*.sh "$(STAGE)/lib"

.PHONY: menu_ui
menu_ui: stage_init
	$(RECOVERY_DIR)/menu_ui/make_images $(UI) \
		$(RECOVERY_DIR)/localized_text \
		"$(STAGE)/etc/screens" $(LOCALE_LIST)
	cp $(RECOVERY_DIR)/*.sh $(RECOVERY_DIR)/menu_ui/*.sh "$(STAGE)/lib"

.PHONY: minios_ui
minios_ui: menu_ui minios stage_init

.PHONY: minios
minios: stage_init
	# FIRMWARE
	mkdir -p "$(STAGE)/lib/firmware"
	cp -av "$(SYSROOT)/lib/firmware/rt"* \
		"$(SYSROOT)/lib/firmware/iwl"* \
		"$(STAGE)/lib/firmware"
	# KERNEL MODULES
	mkdir -p "$(STAGE)/lib/modules"
	cp -av "$(SYSROOT)/lib/modules/"* "$(STAGE)/lib/modules"
	(cd "$(STAGE)/lib/modules/"*"/kernel" && \
		find -maxdepth 1 \
		! -name drivers \
		! -name net \
		! -name crypto \
		! -name . -exec rm -rf {} +)
	(cd "$(STAGE)/lib/modules/"*"/kernel/drivers" && \
		find -maxdepth 1 \
		! -name net \
		! -name . -exec rm -rf {} +)
	# MISC.
	cp "$(SYSROOT)/etc/passwd" \
		"$(SYSROOT)/etc/group" \
		"$(SYSROOT)/etc/nsswitch.conf" "$(STAGE)/etc"
	mkdir -p "$(STAGE)/usr/share/X11/xkb"
	cp -r "$(SYSROOT)/usr/share/X11/xkb"* "$(STAGE)/usr/share/X11"
	# MISSING SHARED LIBS
	mkdir -p "$(STAGE)/lib64"
	cp -av "$(SYSROOT)/lib64/libnss"* "$(STAGE)/lib64/"
	cp -av "$(SYSROOT)/lib64/libminijail"* "$(STAGE)/lib64/"
	# DBUS
	mkdir -p "$(STAGE)/etc/dbus-1"
	cp -av "$(SYSROOT)/etc/dbus-1/"* \
		"$(STAGE)/etc/dbus-1/"
	mkdir -p "$(STAGE)/usr/share/dbus-1"
	cp -av "$(SYSROOT)/usr/share/dbus-1/"* \
		"$(STAGE)/usr/share/dbus-1/"
	# SHILL
	mkdir -p "$(STAGE)/usr/share/cros/init"
	cp -av "$(SYSROOT)/usr/share/cros/init/shill-pre-start.sh" \
		"$(SYSROOT)/usr/share/cros/init/shill.sh" \
		"$(SYSROOT)/usr/share/cros/init/shill-event.sh" \
		"$(STAGE)/usr/share/cros/init/"
	mkdir -p "$(STAGE)/usr/include/chromeos/dbus"
	cp -ab "$(SYSROOT)/usr/include/chromeos/dbus/shill" \
		"$(STAGE)/usr/include/chromeos/dbus/"
	mkdir -p "$(STAGE)/usr/share/shill"
	cp -av "$(SYSROOT)/usr/share/shill/"* \
		"$(STAGE)/usr/share/shill/"
	mkdir -p "$(STAGE)/usr/lib64/shill"
	cp -av "$(SYSROOT)/usr/lib64/shill/"* \
		"$(STAGE)/usr/lib64/shill/"
	# Add json mapping from region to xkb layout.
	cp -av "$(CROS_REGIONS_DATABASE)" "$(STAGE)/usr/share/misc/cros-regions.json"
	# Add conf files for upstart to pickup.
	mkdir -p "$(STAGE)/etc/init"
	cp -av "$(SYSROOT)/build/initramfs/"* "$(STAGE)/etc/init/"
	cp -av "$(SYSROOT)/etc/init/dbus.conf" "$(STAGE)/etc/init/"
	cp -av "$(SYSROOT)/etc/init/network-services.conf" "$(STAGE)/etc/init/"
	cp -av "$(SYSROOT)/etc/init/pre-shutdown.conf" "$(STAGE)/etc/init/"
	cp -av "$(SYSROOT)/etc/init/reboot.conf" "$(STAGE)/etc/init/"
	cp -av "$(SYSROOT)/etc/init/shill.conf" "$(STAGE)/etc/init/"
	cp -av "$(SYSROOT)/etc/init/wpasupplicant.conf" "$(STAGE)/etc/init/"
	mkdir -p "$(STAGE)/usr/lib/tmpfiles.d"
	cp -av "$(SYSROOT)/usr/lib/tmpfiles.d/dbus.conf" "$(STAGE)/usr/lib/tmpfiles.d/"
	cp -av "$(SYSROOT)/usr/lib/tmpfiles.d/syslog.conf" \
		"$(STAGE)/usr/lib/tmpfiles.d/"
	# D-Bus and logging dependencies for upstart.
	mkdir -p "$(STAGE)/var/lib/metrics"
	mkdir -p "$(STAGE)/usr/lib64/rsyslog"
	cp -av "$(SYSROOT)/usr/lib64/rsyslog/"* "$(STAGE)/usr/lib64/rsyslog"
	cp -av "$(SYSROOT)/etc/rsyslog.chromeos" "$(STAGE)/etc"
	mkdir -p "$(STAGE)/usr/lib/systemd"
	cp -av "$(SYSROOT)/usr/lib/systemd/"* "$(STAGE)/usr/lib/systemd"
	# Add policy files for init.
	cp -av "$(SYSROOT)/lib64/libselinux"* "$(STAGE)/lib64/"
	cp -av "$(SYSROOT)/usr/lib64/libselinux"* "$(STAGE)/usr/lib64/"
	mkdir -p "$(STAGE)/etc/selinux"
	rsync -av "$(SYSROOT)/etc/selinux/"* "$(STAGE)/etc/selinux/"
	# Add marker file to indicate we are running from MiniOs.
	touch "$(STAGE)/etc/minios"
	# CrOS-install dependencies.
	cp -av "$(SYSROOT)/usr/share/misc/shflags" "$(STAGE)/usr/share/misc"
	cp -av "$(SYSROOT)/usr/share/misc/lvm-utils.sh" "$(STAGE)/usr/share/misc"
	cp -av "$(SYSROOT)/usr/share/misc/chromeos-common.sh" \
		"$(STAGE)/usr/share/misc"
	mkdir -p "$(STAGE)/usr/share/syslinux"
	cp -av "$(SYSROOT)/usr/share/syslinux/gptmbr.bin" \
		"$(STAGE)/usr/share/syslinux/"
	# Update engine dependencies.
	mkdir -p "$(STAGE)/usr/share/update_engine"
	cp -av "$(SYSROOT)/build/initramfs/update-payload-key.pub.pem" \
		"$(STAGE)/usr/share/update_engine"
	cp -av "$(SYSROOT)/usr/share/chromeos-ca-certificates" "$(STAGE)/usr/share"

	# Udev trigger loading modules + saving networking modules for preloading.
	cp -av "$(SYSROOT)/lib/udev" "$(STAGE)/lib/"
	cp -av "$(SYSROOT)/etc/init/failsafe.conf" \
		"$(SYSROOT)/etc/init/failsafe-delay.conf" \
		"$(SYSROOT)/etc/init/preload-network.conf" \
		"$(SYSROOT)/etc/init/udev.conf" \
		"$(SYSROOT)/etc/init/udev-boot.conf" \
		"$(SYSROOT)/etc/init/udev-trigger.conf" \
		"$(SYSROOT)/etc/init/udev-trigger-early.conf" \
		"$(STAGE)/etc/init/"
	# Connecting to wifi.
	# TODO(b/169261043): Cleanup and organize these dependencies.
	#   Look into target-initramfs as the final solution.
	sudo cp -av "$(SYSROOT)/usr/lib64/libdbus-glib"* \
		"$(SYSROOT)/usr/lib64/libgio"* \
		"$(SYSROOT)/usr/lib64/libgobject"* \
		"$(SYSROOT)/usr/lib64/libgmodule"* \
		"$(SYSROOT)/usr/lib64/libffi"* \
		"$(SYSROOT)/usr/lib64/libgthread"* \
		"$(SYSROOT)/usr/lib64/libz"* \
		"$(SYSROOT)/usr/lib64/libssl"* \
		"$(SYSROOT)/usr/lib64/engine"* \
		"$(SYSROOT)/usr/lib64/libchaps"* \
		"$(SYSROOT)/usr/lib64/libp11"* \
		"$(STAGE)/usr/lib64/"
	mkdir -p "$(STAGE)/etc/ssl"
	sudo cp -av "$(SYSROOT)/etc/ssl/openssl"* \
		"$(STAGE)/etc/ssl/"
	mkdir -p "$(STAGE)/usr/share/policy"
	sudo cp -av "$(SYSROOT)/usr/share/policy/wpa_supplicant.bpf" \
		"$(STAGE)/usr/share/policy/"
	# DHCPCD related files.
	cp -av "$(SYSROOT)/lib64/dhcpcd"* "$(STAGE)/lib64/"
	cp -av "$(SYSROOT)/etc/resolv.conf" "$(STAGE)/etc/"
