# Copyright 2021 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

export MINIOS_TEST = 1

# Override so initramfs.mk doesn't use minios directory.
export SRCDIR ?= $(CURDIR)

# Override so minios/Makefile uses files with relative path to minios_test.
export MINIOS_DIR = ../minios

# Override so minios/Makefile creates extra directories.
export MINIOS_RAMFS_LAYOUT_DIRS = \
	var/tmp

# Dependencies only needed in the test image
export MINIOS_BIN_DEPS = \
	/bin/bash \
	/bin/bzip2 \
	/bin/cat \
	/bin/env \
	/bin/mkdir \
	/bin/rm \
	/bin/tail \
	/bin/tar \
	/bin/touch \
	/usr/bin/coreutils \
	/usr/bin/md5sum \
	/usr/bin/rsync \
	/usr/bin/scp \
	/usr/bin/python3 \
	/usr/local/bin/nebraska.py \
	/usr/sbin/nvme

.PHONY: all
all:
	$(MAKE) -C $(MINIOS_DIR) $(MAKECMDGOALS)
