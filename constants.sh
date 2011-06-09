# Copyright (c) 2011 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This file consists of definitions of message image parameters
# shared between make_images and messages.sh.  Because this file is
# shared, the code here must work the same with both bash
# (make_images) and busybox (messages.sh).  Stick to simple constant
# assignments, and you won't go wrong.

MESSAGE_BOX_WIDTH=800
MESSAGE_BOX_HEIGHT=200
TIME_BAR_HEIGHT=150
TIME_BAR_WIDTH=20
