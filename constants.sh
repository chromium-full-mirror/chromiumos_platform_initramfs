# Copyright (c) 2011 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This file consists of definitions of message image parameters
# shared between make_images and messages.sh.  Because this file is
# shared, the code here must work the same with both bash
# (make_images) and busybox (messages.sh).  Stick to simple constants
# and expressions, and you won't go wrong.

# ALERT!
#
# The message box dimensions are duplicated in make_text_images.
# If you change them here, you must also change them there, and vice
# versa.

MESSAGE_BOX_WIDTH=800
MESSAGE_BOX_HEIGHT=200
# End Alert

PROGRESS_BAR_WIDTH=400
PROGRESS_BAR_HEIGHT=20
PROGRESS_BAR_PERCENT=$(( PROGRESS_BAR_WIDTH / 100 ))

PROGRESS_BAR_BORDER=5
PROGRESS_BAR_INSET=$(( 2 * PROGRESS_BAR_BORDER ))
