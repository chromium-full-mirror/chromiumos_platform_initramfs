# Copyright 2019 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Dependency list of binary programs.
BIN_DEPS= \
	/bin/busybox \
	/build/initramfs/trichechus \
	/build/initramfs/manatee_memory_service \
	/build/manatee/bin/crosvm-direct \
	/usr/bin/cbmem

ifeq ($(MANATEE_PERFORMANCE_TOOLS),1)
BIN_DEPS+= \
	/usr/bin/htop \
	/usr/bin/perf \
	/usr/bin/perfetto \
	/usr/bin/strace \
	/usr/bin/trace-cmd \
	/usr/bin/turbostat \
	/usr/bin/vmstat \

endif

# Additional data files to copy from the sysroot.
DATA_DEPS= \
	/boot/vmlinuz \
	/lib64/libminijailpreload.so

include ../common/initramfs.mk

CONFIG_DEPS=$(wildcard $(SYSROOT)/usr/share/manatee/templates/*.json)

$(RAMFS_BIN): stage_init ${CONFIG_DEPS}
	ln -s busybox $(STAGE)/bin/sh
	lddtree --verbose --copy-non-elfs --root=$(SYSROOT) \
		--copy-to-tree=$(STAGE) \
		$(DATA_DEPS)
	cp "$(SRCDIR)/boards/$(BOARD)/manatee.conf" "$(STAGE)/etc/manatee.conf"
	cp "$(SRCDIR)/crosvm-direct.sh" "$(STAGE)/bin/crosvm-direct.sh"

	mkdir -p "$(STAGE)/usr/share/manatee"
	tee_app_info_lint -R "$(SYSROOT)" \
		-o "$(STAGE)/usr/share/manatee/manatee.flex.bin" \
		${CONFIG_DEPS}
	echo "MANATEE_VERSION=\"$(shell date)\"" \
		>> "$(STAGE)/etc/lsb-release"

	$(call generate_ramfs)

check:
	$(SYSROOT)/bin/busybox sh "$(SRCDIR)/crosvm-direct-test.sh"
