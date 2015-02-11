# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

SUBDIRS = recovery factory_netboot factory_shim

.PHONY: subdirs clean $(SUBDIRS)

subdirs: $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $@

clean:
	@$(foreach dir,$(SUBDIRS),$(MAKE) -C $(dir) clean;)
