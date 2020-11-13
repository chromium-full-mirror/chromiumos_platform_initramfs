# Copyright 2020 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

export MINIOS = 1

# Override so initramfs.mk doesn't use recovery directory.
export SRCDIR = $(CURDIR)

# Override so recovery/Makefile uses files with relative path to miniOS.
export RECOVERY_DIR = ../recovery

# Override so recovery/Makefile used miniOS initramfs folder.
export OVERLAY_FOLDER = $(SYSROOT)/var/lib/initramfs/minios

# Extra dependencies miniOS requires.
export MINIOS_BIN_DEPS = \
	/usr/bin/strace \
	/usr/bin/curl \
	/sbin/dhclient \
	/sbin/dhclient-script \
	/sbin/dhcpcd \
	/sbin/minijail0 \
	/usr/sbin/wpa_supplicant \
	/usr/bin/wpa_passphrase \
	/usr/bin/wpa_cli \
	/usr/bin/wpa_debug

.PHONY: all
all:
	$(MAKE) -C $(RECOVERY_DIR) $(MAKECMDGOALS)
