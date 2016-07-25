# Copyright (c) 2011 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This consists of functions sourced by the /init script and used
# exclusively for recovery images.  Note that this code uses the
# busybox shell (not bash, not dash).

SCREENS=/etc/screens
LANGDIR=

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
# The boxes are assigned locations on the screen, top to bottom in
# the order cited above.  The locations are selected so that the
# box ensemble is centered horizontally and vertically.

. $SCREENS/constants.sh
INSTRUCTION_BOX_TOP=-$MESSAGE_BOX_HEIGHT
PROGRESS_BOX_TOP=0
DEVMODE_BOX_TOP=$MESSAGE_BOX_HEIGHT

# User visible message logged w/ 'echo'
log() {
  echo "$@" | tee -a "${TTY_CONSOLE}" "${TTY_LOG}"
}

# User visible message logged w/ 'printf'
logf() {
  printf "$@" | tee -a "${TTY_CONSOLE}" "${TTY_LOG}"
}

# Debug console message logged w/ 'echo'
dlog() {
  echo "$@" | tee -a "${TTY_LOG}" "${TTY_DEBUG}"
}

# Debug console message logged w/ 'printf'
dlogf() {
  printf "$@" | tee -a "${TTY_LOG}" "${TTY_DEBUG}"
}

clear_console() {
  clear >"${TTY_CONSOLE}"
}

read_vpd_locale() {
  local region="$(vpd -g region)"
  local locale=""
  if [ -n "${region}" ]; then
    # Lookup correct value from locale list.
    sed -nre "s/^${region}\t(.*)$/\1/p" /etc/locales.txt
  else
    # Legacy devices that do not have 'region' and may have multiple locales.
    vpd -g initial_locale | sed 's/,.*//'
  fi
}

select_locale() {
  # The region (fetched via VPD) is only available on Chrome systems.
  is_nonchrome || LANGDIR="$(read_vpd_locale)"
  if [ -z "$LANGDIR" -o ! -d "$SCREENS/$LANGDIR" ]; then
    dlog "initial locale '$LANGDIR' not found"
    LANGDIR=en-US
  fi
  dlog "selected locale $LANGDIR"
}

# Encapsulate displaying of images into single function.
# This makes it easier to maintain and also lets us easily
# switch between using ply-image/frecon depending on if
# frecon is available.
#
# Arg 1:  the path to the image file
# Arg 2:  a pair of numbers X,Y representing offset from center
showimage() {
  local image=$1
  local offset=$2
  shift
  shift

  if [ "${USE_FRECON}" -eq 1 ]; then
    echo -ne \
         "\033]image:file=${image};offset=${offset}\033\\" \
         > /dev/pts/0
  else
    ply-image --offset "${offset}" "${image}" "$@"
  fi
}

# Present a message screen horizontally centered at a specified
# Y-coordinate.
#
# Arg 1:  the Y-coordinate.
# Arg 2:  a token identifying the message, which is used to form the
#   file name based on the current locale.  In case the localized version
#   of the message is unavailable, the en-US version is shown instead.
showbox() {
  local offset=0,$1
  shift
  local message_token=$1
  shift

  # Determine the filename of the message resource. Fall back to en-US if
  # the localized version of the message is not available.
  local message_file=$SCREENS/$LANGDIR/$message_token.png
  if [ ! -f $message_file ]; then
    message_file=$SCREENS/en-US/$message_token.png
  fi

  showimage "${message_file}" "${offset}"
}

# Display an icon next to text in the message box with the given
# Y-coordinate.  The settings of ICON_INSET_LEFT and ICON_INSET_TOP
# are used to determine placement of the icon within the box.
#
# Arg 1:  the Y-coordinate of the text box.
# Arg 2:  the path to image file
showicon() {
  local icon_left=$(( ICON_INSET_LEFT ))
  local icon_top=$(( $1 + ICON_INSET_TOP ))
  shift

  showimage "$1" "${icon_left},${icon_top}"
}

# During installation, we show a spinner animation beside the text
# in the "instruction" message box.  The animation moves at a
# constant speed that's currently not tied to any measure of
# progress; it's meant merely for keeping up appearances...
show_install_spinner() {
  # The termination logic here is a nuisance.  We'd like to stop the
  # animation as soon as we get SIGTERM, but we have to make sure
  # the final animation has stopped.  To keep things simple, we run
  # everything in the foreground and simply check for termination at
  # fixed intervals.
  TERMINATED=0
  trap 'TERMINATED=1' TERM

  while [ $TERMINATED -eq 0 ] ; do
    # just drawing 1 spinner image for each loop.
    for counter in 00 01 02 03 04 05 06 07 08 09 10 11; do
      showicon "${INSTRUCTION_BOX_TOP}" "${SCREENS}/spinner_"*"${counter}.png"
      sleep 0.115
    done
  done
}

# Display a message in the "instructions" box.
#
# Arg 1:  a token identifying the message, which is used to form the
#   file name based on the current locale.
instructions() {
  showbox $INSTRUCTION_BOX_TOP $1
}

# Display a message in the "progress" box.
#
# Arg 1:  a token identifying the message, which is used to form the
#   file name based on the current locale.
progress() {
  showbox $PROGRESS_BOX_TOP $1
}

# Display a message in the "devmode" box.
#
# Arg 1:  a token identifying the message, which is used to form the
#   file name based on the current locale.
dev_notice() {
  showbox $DEVMODE_BOX_TOP $1
}

# Handle display of a simple progress bar in the 'progress' box.
# stdin is a sequence of numbers indicating percent of progress.
# As each value is read, the progress bar is updated to reflect
# the percentage.
progress_bar() {
  local image_left=$(( PROGRESS_BAR_LEFT ))
  local image_top=$(( PROGRESS_BOX_TOP + PROGRESS_BAR_TOP ))

  showimage "${SCREENS}/progress_box.png" "${image_left},${image_top}"

  local incr_left=$(( PROGRESS_INCREMENT_LEFT ))
  local incr_top=$(( PROGRESS_BOX_TOP + PROGRESS_INCREMENT_TOP ))
  local leftmost=$incr_left
  local percent=""
  while read percent; do
    local rightmost=$(( incr_left + PROGRESS_INCREMENT * percent ))
    while [ $leftmost -lt $rightmost ]; do
      showimage "${SCREENS}/progress_increment.png" "${leftmost},${incr_top}"
      leftmost=$(( leftmost + PROGRESS_INCREMENT ))
    done
  done
}

# Enforce a delay on the user for security's sake.  A progress bar
# shows the time so that the impatient will not also be in the dark.
#
# Arg 1:  the wait time in seconds.
make_user_wait() {
  local seconds=$1

  # 100 updates because progress_bar wants percentages.
  local num_updates=100
  local ms_per_update=$(( (2 * 1000 * seconds / num_updates + 1) / 2 ))
  local delay_sec=$(( ms_per_update / 1000 ))
  local delay_ms=$(( ms_per_update % 1000 ))
  local delay=$(printf "%d.%03d" $delay_sec $delay_ms)

  for i in $(seq 1 $num_updates); do
    sleep $delay
    echo $i
  done | progress_bar "$2"
}

# Generic message to report an error.
message_on_error() {
  instructions error
  showicon $INSTRUCTION_BOX_TOP $SCREENS/icon_warning.png
  progress empty
  dev_notice empty
}

# First message we display at start up.
#
# This message also appears when booting factory images.
message_startup() {
  # This printf disables screen blanking and powerdown.  Images
  # displayed by frecon/ply-image would otherwise be erased if the
  # system were left unattended for long enough.  These escape
  # sequences are documented in the console_codes(4) man page.
  printf "\033[9;0]\033[14;0]" >"${TTY_CONSOLE}"

  # This 'echo' prevents the text cursor image from showing up after
  # frecon/ply-image have pushed the screen image.
  echo 0 > /sys/devices/virtual/graphics/fbcon/cursor_blink

  if [ "${USE_FRECON}" -eq 1 ]; then
    frecon-lite --enable-vt1 --daemon --no-login --enable-gfx \
                --enable-vts --clear "0x${BACKGROUND}" \
                "${SCREENS}/boot_message.png"
  else
    ply-image --clear "0x${BACKGROUND}"
    ply-image "${SCREENS}/boot_message.png"
  fi

  select_locale

  instructions cancel
  progress validating

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

# Tell the user that he must endure the 5 minute wait for a
# developer key change.
message_key_change() {
  progress wait
  dev_notice key_change
  make_user_wait 300
}

# Announce that recovery is about to start.  This happens after the
# progress bar is full, and is the user's last chance to cancel.
# The power button has to be held a full 8 seconds to power off, so
# we allow a short grace period in case the user started pressing the
# power button late in the cycle.
#
# When the grace period is up, start the moving box animation that
# will persist until recovery is complete.
message_recovery_start() {
  # The user gets a two seconds grace period to cancel
  sleep 2
  instructions recovering
  progress empty
  show_install_spinner >$LOG_DIR/spinner.log 2>&1 &
  SPINNER_PID=$!
}

# Kill the spinner animation and announce that recovery is
# complete.  Note that waiting for termination of the animation
# is necessary to guarantee that subsequent messages don't get
# overwritten.
message_recovery_complete() {
  kill $SPINNER_PID
  wait $SPINNER_PID
  instructions complete
  showicon $INSTRUCTION_BOX_TOP $SCREENS/icon_check.png
  progress empty
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
  showicon $INSTRUCTION_BOX_TOP $SCREENS/icon_warning.png
  save_log_files
  sleep 1d
  exit 1
}

# Tell the user that installation can't continue because the device
# owner has engaged developer mode blocking, and the image to be
# installed is not an official image.
#
# This is an error condition equivalent to on_error, below.
message_block_developer_mode() {
  instructions block_dev_mode
  showicon $INSTRUCTION_BOX_TOP $SCREENS/icon_warning.png
  progress empty
  dev_notice empty
  save_log_files
  sleep 1d
  exit 1
}

# Terminate with an error message.  We don't want to do anything
# else (like start a shell) because it would be trivially easy to
# get here (just unplug the USB drive after the kernel starts but
# before the USB drives are probed by the kernel) and starting a
# shell here would be a BIG security hole.
on_error() {
  message on_error
  save_log_files
  sleep 1d
  exit 1
}
