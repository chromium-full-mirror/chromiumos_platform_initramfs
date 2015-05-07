# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

include ../common/initramfs.mk

# Dependency list of binary programs.
BIN_DEPS= \
	/bin/busybox \
	/usr/sbin/kexec \
	/usr/bin/futility \
	/usr/bin/cgpt
ifeq ($(INCLUDE_FIT_PICKER),1)
BIN_DEPS += /usr/bin/fitpicker
endif

$(RAMFS_BIN): stage_init
	ln -s busybox $(STAGE)/bin/sh
	cp "$(SYSROOT)/usr/share/vboot/devkeys/kernel_subkey.vbpubk" "$(STAGE)"
	cp "$(SYSROOT)/usr/share/vboot/devkeys/recovery_key.vbpubk" "$(STAGE)"
	$(call generate_ramfs)
