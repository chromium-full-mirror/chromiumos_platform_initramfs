# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

export FLEXOR = 1

# Override so initramfs.mk doesn't use recovery directory.
export SRCDIR = $(CURDIR)

# Override so recovery/Makefile uses files with relative path to Flexor.
export RECOVERY_DIR = ../recovery

export FLEXOR_BIN_DEPS = \
	/bin/mount \
	/bin/tail \
	/bin/tar \
	/bin/dd \
	/bin/udevadm \
	/usr/sbin/chromeos-install \
	/sbin/blockdev \
	/sbin/init \
	/sbin/poweroff \
	/sbin/losetup \
	/sbin/mkfs.ext4 \
	/sbin/reboot \
	/sbin/sfdisk

.PHONY: all
all:
	$(MAKE) -C $(RECOVERY_DIR) $(MAKECMDGOALS)

.PHONY: check
check:
