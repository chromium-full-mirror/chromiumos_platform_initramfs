#!/bin/busybox sh
# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# To bootstrap the factory installer on rootfs. This file must be executed as
# PID=1 (exec).
# Note that this script uses the busybox shell (not bash, not dash).
set -x

# USB card partition and mount point.
USB_DEVS="sdb3 sdc3 mmcblk1p3"
USB_MNT=/usb
REAL_USB_DEV=

STATEFUL_MNT=/stateful
STATE_DEV=

LOG_DEV=
LOG_DIR=/log
LOG_FILE=$LOG_DIR/recovery.log

# Size of the root ramdisk.
TMPFS_SIZE=400M

# Special file systems required in addition to the root file system.
BASE_MOUNTS="/sys /proc /dev"

# To be updated to keep logging after move_mounts.
TTY_PATH="/dev/tty"
TAIL_PID=

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

on_error() {
  log "ERROR: Factory installation aborted."
  save_log_files
  sleep 1d
  exit 1
}

# Look for a device with our GPT ID.
wait_for_gpt_root() {
  [ -z "$KERN_ARG_KERN_GUID" ] && return 1
  dlog -n "Looking for rootfs using kern_guid..."
  for try in $(seq 20); do
    dlogf " ."
    kern=$(cgpt find -1 -u $KERN_ARG_KERN_GUID)
    # We always try ROOT-A in recovery.
    newroot="${kern%[0-9]*}3"
    if [ -b "$newroot" ]; then
      USB_DEV="$newroot"
      dlog "Found $USB_DEV"
      return 0
    fi
    sleep 1
  done
  dlog "Failed waiting for kern_guid"
  return 1
}

# Look for any USB device.
wait_for_root() {
  dlog -n "Waiting for $USB_DEVS to appear"
  for try in $(seq 20); do
    dlogf " ."
    for dev in $USB_DEVS; do
      if [ -b "/dev/$dev" ]; then
        USB_DEV="/dev/$dev"
        dlog "Found $USB_DEV"
        return 0
      fi
    done
    sleep 1
  done
  dlog "Failed waiting for root!"
  return 1
}

# Attempt to find the root defined in the signed recovery
# kernel we're booted into to. Exports REAL_USB_DEV if there
# is a root partition that may be used - on succes or failure.
find_official_root() {
  dlogf "Checking for an official root . . ."

  # Check for a kernel selected root device or one in a well known location.
  wait_for_gpt_root || wait_for_root || return 1

  # Now see if it has a Chrome OS rootfs partition.
  cgpt find -t rootfs "$(strip_partition "$USB_DEV")" || return 1
  REAL_USB_DEV="$USB_DEV"

  # USB_DEV points to the rootfs partition of removable media. And its value
  # can be one of /dev/sda3 (arm), /dev/sdb3 (x86, arm) and /dev/mmcblk1p3
  # (arm). Get stateful partition by replacing partition number with "1".
  LOG_DEV="${USB_DEV%[0-9]*}"1  # Default to stateful.

  mount_usb || return 1
  return 0
}

mount_usb() {
  dlog -n "Mounting usb"
  for try in $(seq 20); do
    dlogf " ."
    if mount -n -o ro "$USB_DEV" "$USB_MNT"; then
      dlog "ok"
      return 0
    fi
    sleep 1
  done
  dlog "Failed to mount usb!"
  return 1
}

get_stateful_dev() {
  STATE_DEV=${REAL_USB_DEV%[0-9]*}1
  if [ ! -b "$STATE_DEV" ]; then
    dlog "Failed to determine stateful device"
    return 1
  fi
  return 0
}

unmount_usb() {
  dlog "Unmounting $USB_MNT"
  umount "$USB_MNT"
  dlog
  dlog "$REAL_USB_DEV can now be safely removed"
  dlog
  return 0
}

strip_partition() {
  local dev="${1%[0-9]*}"
  # handle mmcblk0p case as well
  echo "${dev%p*}"
}

# Saves log files stored in LOG_DIR in addition to demsg to the device specified
# (/ of stateful mount if none specified).
save_log_files() {
  # The recovery stateful is usually too small for ext3.
  # TODO(wad) We could also just write the data raw if needed.
  #           Should this also try to save
  local log_dev="${1:-$LOG_DEV}"
  [ -z "$log_dev" ] && return 0

  local log_fs="${2:-ext4}"

  dlog "Dumping dmesg to $LOG_DIR"
  dmesg > "$LOG_DIR"/dmesg

  # TODO(sosa): Remove once caller scripts recover all of the log dir.
  cat "$LOG_DIR"/dmesg >> "$LOG_FILE"

  dlog "Saving log files from: $LOG_DIR -> $log_dev"
  err=0
  [ $err -ne 0 ] || mount -n -t "$log_fs" -o sync,rw "$log_dev" /tmp || err=1
  [ $err -ne 0 ] || rm -rf /tmp/recovery_logs || err=1
  [ $err -ne 0 ] || mkdir -p /tmp/recovery_logs || err=1
  [ $err -ne 0 ] || cp $LOG_DIR/* /tmp/recovery_logs || err=1
  # Attempt umount, even if there was an error to avoid leaking the mount.
  umount -n /tmp || err=1

  if [ $err -eq 0 ] ; then
    dlog "Successfully saved the log file"
  else
    dlog "Failures seen trying to save log file"
  fi
}

stop_log_file() {
  # Drop logging
  exec >"$TTY_PATH"3 2>&1
  [ -n "$TAIL_PID" ] && kill $TAIL_PID
}

# Extract and export kernel arguments
export_args() {
  # We trust our kernel command line explicitly.
  local arg=
  local key=
  local val=
  local acceptable_set='[A-Za-z0-9]_'
  for arg in "$@"; do
    key=$(echo "${arg%=*}" | tr 'a-z' 'A-Z' | \
                   tr -dc "$acceptable_set" '_')
    val="${arg#*=}"
    export "KERN_ARG_$key"="$val"
    dlog "Exporting kernel argument $key as KERN_ARG_$key"
  done
}

mount_tmpfs() {
  dlog "Mounting tmpfs..."
  mount -n -t tmpfs tmpfs "$NEWROOT_MNT" -o "size=$TMPFS_SIZE"
  return $?
}

copy_contents() {
  log "Copying contents of USB device to tmpfs..."
  (cd "${USB_MNT}" ; tar cf - . | (cd "${NEWROOT_MNT}" && tar xf  -))
  RES=$?
  if [ $RES -eq 0 ]; then
    log "Copy complete."
  else
    log "Copy failed with result $RES."
  fi
  return $RES
}

copy_lsb() {
  local lsb_file="dev_image/etc/lsb-factory"
  local dest_path="${NEWROOT_MNT}/mnt/stateful_partition/${lsb_file}"
  local src_path="${STATEFUL_MNT}/${lsb_file}"

  mkdir -p "$(dirname $dest_path)"
  # Mounting ext3 as ext2 since the journal is unneeded in ro.
  if ! mount -n "${STATE_DEV}" "${STATEFUL_MNT}"; then
    log "Failed to mount ${STATE_DEV}!! Failing."
    return 1
  fi
  if [ -f "${src_path}" ]; then
    log "Found ${src_path}"
    cp -a "${src_path}" "${dest_path}"
    echo "REAL_USB_DEV=$REAL_USB_DEV" >>"${dest_path}"
  else
    log "Failed to find ${src_path}!! Failing."
    umount "$STATEFUL_MNT"
    return 1
  fi
  umount "$STATEFUL_MNT"
  rmdir "$STATEFUL_MNT"
}

copy_bins() {
  # Copy essential binaries that are in the initramfs, but not in the root FS.
  log "Copying binaries to $NEWROOT_MNT"
  cp /bin/busybox $NEWROOT_MNT/bin

  # Modify some files that does not work (and not required) in tmpfs chroot.
  # This may be removed when we can build factory installer in "embedded" mode.
  local file="${NEWROOT_MNT}/usr/sbin/mount-encrypted"
  echo '#!/bin/sh' >"${file}"
  echo 'echo "Sorry, $0 is disabled on factory installer image."' >>"${file}"
}

move_mounts() {
  dlog "Moving $BASE_MOUNTS to $NEWROOT_MNT"
  for mnt in $BASE_MOUNTS; do
    # $mnt is a full path (leading '/'), so no '/' joiner
    mkdir -p "$NEWROOT_MNT$mnt"
    mount -n -o move "$mnt" "$NEWROOT_MNT$mnt"
  done
  TTY_PATH="$NEWROOT_MNT/dev/tty"
  dlog "Done."
  return 0
}

use_new_root() {
  move_mounts || on_error

  # Chroot into newroot, erase the contents of the old /, and exec real init.
  log "About to switch root"
  stop_log_file
  exec switch_root -c /dev/tty2 "$NEWROOT_MNT" /sbin/init

  # This should not really happen.
  log "Failed to switch root."
  save_log_files
  return 1
}

check_block_dev() {
  log "Checking block_devmode flags"
  if crossystem 'block_devmode?1' 'wpsw_boot?1' 2>/dev/null; then
    log "
    crossystem flag 'block_devmode' is set on a write protected device.

    You need to disable hardware write protection to bypass this check.
    "
    return 1
  fi
  return 0
}

main() {
  mkdir -p "$(dirname $LOG_FILE)"
  exec >"$LOG_FILE" 2>&1
  # Send all verbose output to tty3
  (tail -f "$LOG_FILE" > "$TTY_PATH"3) &
  TAIL_PID=$!

  # Export the kernel command line as a parsed blob prepending KERN_ARG_ to each
  # argument.
  export_args $(cat /proc/cmdline | sed -e 's/"[^"]*"/DROPPED/g')

  check_block_dev || on_error
  find_official_root || on_error
  get_stateful_dev || on_error


  log "Bootstrapping factory shim."
  # Copy rootfs contents to tmpfs, then unmount USB device.
  NEWROOT_MNT=/newroot
  mount_tmpfs || on_error
  copy_contents || on_error
  copy_lsb || on_error
  copy_bins || on_error
  # USB device is unmounted, we can remove it now.
  unmount_usb || on_error
  # Switch to the new root
  use_new_root || on_error
  on_error # !! Never reached. !!
}

main "$@"
