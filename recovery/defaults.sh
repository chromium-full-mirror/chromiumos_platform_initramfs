#!/bin/sh
#
# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# Default settings and implementations. Variables and settings defined in this
# file can be overridden by board_recovery.sh.

# Console and log output.
TTY_CONSOLE=/dev/tty1
TTY_LOG=/dev/tty2
TTY_DEBUG=/dev/tty3

# Wrapper to provide a hook for every message we print.
message() {
  # Currently defined messages (see message.sh for details):
  #  - startup
  #  - on_error
  #  - key_change
  #  - developer_image
  #  - key_change
  #  - recovery_start
  #  - recovery_complete
  #  - recovery_complete_noninteractive
  #  - warn_invalid_install_kernel
  #  - invalid_install_kernel
  #  - block_developer_mode
  #
  # By default, calls to the functions defined in message.sh.
  message_$1
}
