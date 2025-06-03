# Copyright 2025 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Override so initramfs.mk doesn't use recovery directory.
export SRCDIR = $(CURDIR)

# Override so recovery/Makefile uses files with relative path.
export RECOVERY_DIR = ../recovery

# Extra dependencies desktop recovery requires.
export DESKTOP_BIN_DEPS = \
	/sbin/poweroff \
	/sbin/reboot \
	/sbin/shutdown \
	/usr/bin/rootdev \
	/usr/sbin/bootstat

.PHONY: all
all:
	$(MAKE) -C $(RECOVERY_DIR) $(MAKECMDGOALS)

.PHONY: check
check:
