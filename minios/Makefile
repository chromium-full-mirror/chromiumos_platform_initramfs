# Copyright 2020 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

export MINIOS = 1

# Override so initramfs.mk doesn't use recovery directory.
export SRCDIR = $(CURDIR)

# Override so recovery/Makefile uses files with relative path to miniOS.
export RECOVERY_DIR = ../recovery

# Override so recovery/Makefile uses miniOS initramfs folder.
export OVERLAY_FOLDER = $(SYSROOT)/var/lib/initramfs/minios

# Override so recovery/Makefile creates extra directories.
export MINIOS_RAMFS_LAYOUT_DIRS = \
	run/dbus

# Extra dependencies miniOS requires.
export MINIOS_BIN_DEPS = \
	/sbin/chromeos_startup \
	/sbin/dhclient \
	/sbin/dhclient-script \
	/sbin/dhcpcd \
	/sbin/init \
	/sbin/initctl \
	/sbin/minijail0 \
	/sbin/start \
	/sbin/status \
	/sbin/stop \
	/usr/bin/curl \
	/usr/bin/dbus-daemon \
	/usr/bin/dbus-monitor \
	/usr/bin/dbus-send \
	/usr/bin/logger \
	/usr/bin/minios \
	/usr/bin/minios_init \
	/usr/bin/shill \
	/usr/bin/strace \
	/usr/bin/update_engine_client \
	/usr/bin/wpa_cli \
	/usr/bin/wpa_debug \
	/usr/bin/wpa_passphrase \
	/usr/sbin/bootstat \
	/usr/sbin/update_engine \
	/usr/sbin/wpa_supplicant

.PHONY: all
all:
	$(MAKE) -C $(RECOVERY_DIR) $(MAKECMDGOALS)
