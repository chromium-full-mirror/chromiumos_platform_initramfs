# Copyright (c) 2011 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This consists of functions sourced by the /init script and used
# exclusivly for recovery images.  Note that this code uses the
# busybox shell (not bash, not dash).

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

make_user_wait() {
  local delay_in_sec="${1-300}"
  while [ $delay_in_sec -gt 0 ]; do
    logf " ."
    sleep 1
    delay_in_sec=$((delay_in_sec - 1))
  done
  log ""
}

clear_console() {
  clear >"$TTY_PATH"1
}

message_on_error() {
  log
  log "An unrecoverable error occurred during recovery!"
  log
  log "Please try again or try a newer recovery image."
  log
}

logging_notice() {
  log ""
  log "Log viewing options:"
  log "  Ctrl + Alt + F1 (VT1):  This screen."
  log "  Ctrl + Alt + F2 (VT2):  Text log"
  log "  Ctrl + Alt + F3 (VT3):  Debug log"
}

cancel_notice() {
  clear_console
  # N.B. is_nonchrome implies is_developer_mode, so we must test
  # is_nonchrome first.
  if is_nonchrome; then
    log "! Your computer does not appear to a Chrome computer!"
    log "!"
    log "! This operation will delete any other operating system you may"
    log "! have installed; dual-boot is not an option.  Please be sure"
    log "! you know what you're doing."
  elif is_developer_mode; then
    log "! Your computer's developer mode switch is in the ENABLED position."
    log "!"
    log "! If this is unintentional, you should power off and toggle it back"
    log "! after recovery is completed."
  fi

  log ""
  log "Please make sure your computer is plugged in to a power source."
  log ""
  log "If you want to cancel recovery, press and hold the power button"
  log "until the computer turns off.  It is safe to do this at any time"
  log "up until recovery begins."

  logging_notice

  log ""
}

message_startup() {
  cancel_notice

  log "Scanning your system for a valid recovery image."
}

message_developer_image() {
  cancel_notice

  log "The image on your recovery device is an unverified developer image."
  log "Recovery will continue, because your computer's developer mode switch"
  log "is in the ENABLED position."
}

message_validating() {
  cancel_notice

  log "Checking recovery device integrity."
}

message_key_change() {
  log ""
  log "A developer key change is required to proceed; the process requires"
  log "5 minutes."
  log ""
  logf "Please wait . ."
  make_user_wait 300
}

message_recovery_countdown() {
  cancel_notice
  log ""
  logf "System recovery will begin in 10 seconds."
  make_user_wait 10
  clear_console
  log "System recovery has begun."
  log "Please do not disconnect from a power source or power down."

  logging_notice
}

message_complete() {
  log ""
  log "System recovery is complete!"
  log ""
  log "It is now safe to remove the recovery device and restart your computer"
  logf "The system will automatically restart in 10 seconds"
  make_user_wait 10
}

message_invalid_install_kernel() {
  log ""
  log "The recovery device you inserted is corrupted or out-of-date."
  log "A new recovery device can be created by following instructions at:"
  log ""
  log "          http://google.com/chromeos/recovery"
  log ""
  log "Please try recovery again with a newly created recovery device."
  log ""
}

message_warn_invalid_install_kernel() {
  log ""
  log "WARNING: You are using an out-of-date or corrupted official Chrome OS"
  log "         recovery image."
  log ""
  log "The system will not boot in verified mode."
  log ""
  make_user_wait 5
}

message() {
  message_$1
}

on_error() {
  # Exit, thus causing a kernel panic. We don't want to do anything else (like
  # start a shell) because it would be trivially easy to get here (just unplug
  # the USB drive after the kernel starts but before the USB drives are probed
  # by the kernel) and starting a shell here would be a BIG security hole.
  message on_error
  save_log_file
  sleep 1d
  exit 1
}
