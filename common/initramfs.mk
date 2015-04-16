# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Disable implicit rules.
.SUFFIXES:

.PHONY: all
all:	$(RAMFS_BIN)

.PHONY: clean
clean:
	rm -rf $(RAMFS_BIN) $(STAGE)

.PHONY: stage_init
stage_init:
	rm -rf "$(STAGE)"
	mkdir -p "$(STAGE)"
	(cd $(STAGE); mkdir -p $(RAMFS_LAYOUT_DIRS))
