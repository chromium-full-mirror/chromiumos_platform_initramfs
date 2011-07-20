# Copyright (c) 2011 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This consists of functions sourced by the /init script and used
# exclusively for recovery images.  Note that this code uses the
# busybox shell (not bash, not dash).

. /lib/constants.sh

# Message screens are presented in one of three boxes:
# + The 'instructions' box is used for messages telling users
#   what they can or should do.  It's for messages like "here's how
#   to cancel", or "don't turn off your computer".
# + The 'progress' box is used for to inform users how things are
#   going.  It's for animations and messages that describe what
#   work is being done, or to show percentage completion of an
#   operation.
# + The 'devmode' box is for messages that should only occur in
#   developer mode, or on non-chrome hardware.
#
# The boxes are assigned fixed locations on the screen, top to
# bottom in the order cited above.  The parameters below assign the
# Y-coordinate of the top of each box
INSTRUCTION_BOX=$(( 0 * MESSAGE_BOX_HEIGHT ))
PROGRESS_BOX=$(( 1 * MESSAGE_BOX_HEIGHT ))
DEVMODE_BOX=$(( 2 * MESSAGE_BOX_HEIGHT ))

# TODO(jrbarnette):  Currently, we have no translated text, so we
# hard-code for US English.
SCREENS=/etc/screens
LANGDIR=en

# User visible message logged w/ 'echo'
log() {
  echo "$@" | tee -a "$TTY_PATH"1 "$TTY_PATH"2
}

# User visible message logged w/ 'printf'
logf() {
  printf "$@" | tee -a "$TTY_PATH"1 "$TTY_PATH"2
}

# Debug console message logged w/ 'echo'
dlog() {
  echo "$@" | tee -a "$TTY_PATH"2 "$TTY_PATH"3
}

# Debug console message logged w/ 'printf'
dlogf() {
  printf "$@" | tee -a "$TTY_PATH"2 "$TTY_PATH"3
}

clear_console() {
  clear >"$TTY_PATH"1
}

# Present a message screen aligned to the left of the display at a
# specified Y-coordinate.
#
# Arg 1:  the Y-coordinate.
# Args 2..$#:  arguments for ply-image.
showbox() {
  local location=0,$1
  shift
  ply-image --location $location "$@"
}

# During installation, we show an animation of a moving box inside
# the "progress" message box.  The animation is currently not tied
# to any measure of progress; it's meant merely for keeping up
# appearances...
#
# The moving box animation is a set of frames numbered from 0..N.
# The sequence displays frames 0..N-1 (moving from left to right),
# followed by frames N..1 (moving from right to left).
show_moving_box() {
  # 'forward' is the list of frames, 0..N-1
  local forward="$(ls $SCREENS/moving_box_??.png | sed '$d')"
  # 'backward' is the list of frames, N..1
  local backward="$(ls -r $SCREENS/moving_box_??.png | sed '$d')"

  # The termination logic here is a nuisance.  We'd like to stop the
  # animation as soon as we get SIGTERM, but we have to make sure
  # the final animation has stopped.  Starting `showbox` in the
  # background would create a child (shell) and grandchild
  # (ply-image), so cleaning up is tricky.  Far easier (in this
  # case) to run everything in the foreground and simply check for
  # termination at fixed intervals.
  TERMINATED=0
  trap 'TERMINATED=1' TERM

  while [ $TERMINATED -eq 0 ] ; do
    showbox $PROGRESS_BOX $forward $backward
  done
}

# Display a message in the "instructions" box.
#
# Arg 1:  a token identifying the message, which is used to form the
#   file name based on the current locale.
instructions() {
  showbox $INSTRUCTION_BOX $SCREENS/$LANGDIR/$1.png
}

# Display a message in the "progress" box.
#
# Arg 1:  a token identifying the message, which is used to form the
#   file name based on the current locale.
progress() {
  showbox $PROGRESS_BOX $SCREENS/$LANGDIR/$1.png
}

# Display a message in the "devmode" box.
#
# Arg 1:  a token identifying the message, which is used to form the
#   file name based on the current locale.
dev_notice() {
  showbox $DEVMODE_BOX $SCREENS/$LANGDIR/$1.png
}

# Enforce a delay on the user, for his own good, or for security's
# sake.  A vertical bar on the right hand side of the "progress"
# box counts down the time to prevent the user from being both in
# the dark *and* impatient.
#
# Arg 1:  the wait time in seconds.
# Arg 2:  the name of a message to display in the "progress" box
#   that explains the timeout.
make_user_wait() {
  local seconds=${1:-300}
  local left_edge=$(( 7 * MESSAGE_BOX_WIDTH / 8 ))
  local top_line=$(( PROGRESS_BOX +
                     (MESSAGE_BOX_HEIGHT - TIME_BAR_HEIGHT) / 2 ))
  local last_line=$(( top_line + TIME_BAR_HEIGHT ))

  progress $2
  ply-image --location $left_edge,$top_line $SCREENS/time_bar.png

  local ms_per_line=$(( (2 * 1000 * seconds / TIME_BAR_HEIGHT + 1) / 2 ))
  local delay_sec=$(( ms_per_line / 1000 ))
  local delay_ms=$(( ms_per_line % 1000 ))
  local delay=$(printf "%d.%03d" $delay_sec $delay_ms)

  while [ $top_line -lt $last_line ] ; do
    sleep $delay
    ply-image --location $left_edge,$top_line $SCREENS/time_line.png
    top_line=$(( top_line + 1 ))
  done
}

# Generic message to report an error.
message_on_error() {
  instructions error
  progress empty
  dev_notice empty
}

# First message we display at start up.
#
# This message also appears when booting factory images.
message_startup() {
  # This 'echo' prevents the text cursor image from showing up after
  # ply-image has pushed the screen image.
  echo 0 > /sys/devices/virtual/graphics/fbcon/cursor_blink
  ply-image $SCREENS/background.png
  instructions cancel
  progress scanning

  # N.B. is_nonchrome implies is_developer_mode, so we must test
  # is_nonchrome first.
  if is_nonchrome; then
    dev_notice non_chrome
  elif is_developer_mode; then
    dev_notice dev_switch
  else
    dev_notice empty
  fi
}

# Tell the user the system developer mode switch is on.
message_developer_image() {
  dev_notice unverified
}

# Tell the user that we're validating the recovery media.
message_validating() {
  progress validating
}

# Tell the user that he must endure the 5 minute wait for a
# developer key change.
message_key_change() {
  dev_notice key_change
  make_user_wait 300 wait
}

# Announce that recovery is about to start.  This is the user's
# last chance to cancel, so allow a short grace period.  When
# the grace period is up, start the moving box animation that will
# persist until recovery is complete.
message_recovery_start() {
  sleep 1
  make_user_wait 10 countdown
  sleep 1
  instructions recovering
  show_moving_box >$LOG_DIR/moving.log 2>&1 &
  MOVING_BOX_PID=$!
}

# Kill the moving box animation and announce that recovery is
# complete.  Note that waiting for termination of the animation
# is necessary to guarantee that subsequent messages don't get
# overwritten.
message_recovery_complete() {
  kill $MOVING_BOX_PID
  wait $MOVING_BOX_PID
  instructions complete
}

# Warn the user that the current image, although valid for
# unverified boot, won't boot if verification is re-enabled.
message_warn_invalid_install_kernel() {
  dev_notice dev_invalid_kernel
}

# Tell the user that the image on the recovery media can't be
# installed, either because it failed verification, or because
# the version is out of date.
#
# This is an error condition equivalent to on_error, below.
message_invalid_install_kernel() {
  instructions invalid_kernel
  save_log_file
  sleep 1d
  exit 1
}

# Wrapper to provide a hook for every message we print.
message() {
  message_$1
}

# Terminate with an error message.  We don't want to do anything
# else (like start a shell) because it would be trivially easy to
# get here (just unplug the USB drive after the kernel starts but
# before the USB drives are probed by the kernel) and starting a
# shell here would be a BIG security hole.
on_error() {
  message on_error
  save_log_file
  sleep 1d
  exit 1
}
