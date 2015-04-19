# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Dependency list of binary programs.
BIN_DEPS= \
	/bin/bash \
	/bin/busybox \
	/bin/sh

# Extra dependency, should be set by builder configuration.
EXTRA_BIN_DEPS?=

# Programs required by netboot intaller
NETBOOT_BIN_DEPS= \
	/bin/dd \
	/bin/ip \
	/bin/xxd \
	/sbin/blockdev \
	/sbin/resize2fs \
	/sbin/sfdisk \
	/usr/bin/coreutils \
	/usr/bin/getopt \
	/usr/bin/openssl \
	/usr/bin/setterm \
	/usr/bin/uudecode \
	/usr/bin/uuidgen \
	/usr/bin/wget \
	/usr/sbin/flashrom \
	/usr/sbin/fsck.vfat \
	/usr/sbin/htpdate \
	/usr/sbin/partprobe

# ChromeOS specific dependency.
CROS_DEPS=\
	/usr/bin/cgpt \
	/usr/bin/crossystem \
	/usr/bin/futility \
	/usr/sbin/chromeos-install \
	/usr/sbin/ectool \
	/usr/sbin/factory_install_service.sh \
	/usr/sbin/factory_install.sh \
	/usr/sbin/netboot_postinst.sh \
	/usr/sbin/ping_shopfloor.sh \
	/usr/sbin/secure_less.sh \
	/usr/sbin/vpd

# Non-executables.
DATA_DEPS=\
	/opt/google/memento_updater/* \
	/root/.pmbr_code \
	/usr/share/misc/chromeos-common.sh \
	/usr/share/misc/shflags

# Directories to be cloned into initramfs.
DATA_DIR_DEPS= \
	/etc/terminfo

# Layout of directories to be created in initramfs.
RAMFS_LAYOUT_DIRS=\
	bin \
	dev \
	etc \
	lib \
	proc \
	root \
	sys \
	tmp \
	usr/share/misc \
	var/empty \
	var/log \
	mnt/stateful_partition/dev_image/etc \
	newroot \
	stateful \
	usb

SERVER_ADDR		?= 10.0.0.1

NAME = netboot

include ../common/initramfs.mk

$(RAMFS_BIN): stage_init
	lddtree --verbose --copy-non-elfs --root=$(SYSROOT) \
		--copy-to-tree=$(STAGE) --bindir=/bin \
		$(BIN_DEPS) $(NETBOOT_BIN_DEPS) $(CROS_DEPS) $(EXTRA_BIN_DEPS)
	lddtree --verbose --copy-non-elfs --root=$(SYSROOT) \
		--copy-to-tree=$(STAGE) \
		$(DATA_DEPS)
	for data in $(DATA_DIR_DEPS); do \
		cp -r $(SYSROOT)/$${data} $(STAGE)/$${data}; \
	done
	(BOARD=$(BOARD) BUILD_LIBRARY_DIR=$(BUILD_LIBRARY_DIR) bash -c \
		". $(BUILD_LIBRARY_DIR)/disk_layout_util.sh; \
		write_partition_script usb $(STAGE)/bin/write_gpt.sh")
	cp etc/* $(STAGE)/etc/
	chmod 400 $(STAGE)/etc/passwd
	sed -i "s/%BOARD%/$(BOARD)/g;s/%SERVER_ADDR%/$(SERVER_ADDR)/g" \
		$(STAGE)/etc/lsb-factory
	mv $(STAGE)/etc/lsb-factory \
		$(STAGE)/mnt/stateful_partition/dev_image/etc/lsb-factory
	ln -s /mnt/stateful_partition/dev_image/etc/lsb-factory \
		$(STAGE)/etc/lsb-release
	cp init $(STAGE)/
	chmod a+x $(STAGE)/init $(STAGE)/etc/udhcpc.script
	./kotree.sh usbnet.ko $(SYSROOT) $(STAGE)
	$(call generate_ramfs)
