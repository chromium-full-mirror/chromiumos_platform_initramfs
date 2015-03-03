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
NEWROOT_MNT=/newroot

LOG_DEV=
LOG_DIR=/log
LOG_FILE=${LOG_DIR}/factory_shim.log

# Size of the root ramdisk.
TMPFS_SIZE=400M

# Special file systems required in addition to the root file system.
BASE_MOUNTS="/sys /proc /dev"

# To be updated to keep logging after move_mounts.
TTY=
LOG_TTY=/dev/null
TAIL_PID=

# Checks if given parameter is a valid TTY (or PTS) device file.
is_valid_tty() {
  [ -c "$1" ] && (echo "" >"$1") 2>/dev/null
}

# Determine the right console by following order:
#  - The last non-empty console= from cmdline.
#  - /dev/tty1 if available (for Non-Freon boards).
#  - /dev/null if nothing available.
find_best_tty() {
  local entry="$(cat /proc/cmdline)"
  local ttys=""
  local tty_name="" tty_path=""

  while echo "${entry}" | grep -q console= ; do
    entry="${entry#*console=}"
    ttys="${entry%%[ ,]*} ${ttys}"
    entry="${entry#* }"
  done

  for tty_name in ${ttys}; do
    tty_path="/dev/${tty_name}"
    if is_valid_tty "${tty_path}"; then
      TTY="${tty_path}"
      break
    fi
  done

  if [ -z "${TTY}" ]; then
    if is_valid_tty "/dev/tty1"; then
      TTY=/dev/tty1
    else
      TTY=/dev/null
    fi
  fi

  # Enable LOG_TTY if available (currently only works for VT).
  is_valid_tty "/dev/tty2" && LOG_TTY="/dev/tty2"
  return 0
}

# Print message on both main TTY and log file.
info() {
  echo "$@" | tee -a "${TTY}" "${LOG_FILE}"
}

is_cros_debug() {
  grep -qw cros_debug /proc/cmdline 2>/dev/null
}

enable_debug_console() {
  local tty="$1"
  if ! is_cros_debug; then
    info "To debug, add [cros_debug] to your kernel command line."
  elif [ "${tty}" = /dev/null ] || ! is_valid_tty "${tty}"; then
    # User probably can't see this, but we don't have better way.
    info "Please set a valid [console=XXX] in kernel command line."
  else
    info -e '\033[1;33m[cros_debug] enabled on '${tty}'.\033[m'
    (setsid sh -c sh <"${tty}" >>"${tty}" 2>&1 || true) &
  fi
}

on_error() {
  trap - EXIT
  info -e '\033[1;31m'
  info "ERROR: Factory installation aborted."
  save_log_files
  enable_debug_console "${TTY}"
  sleep 1d
  exit 1
}

# Look for a device with our GPT ID.
wait_for_gpt_root() {
  [ -z "$KERN_ARG_KERN_GUID" ] && return 1
  info -n "Looking for rootfs using kern_guid [${KERN_ARG_KERN_GUID}]... "
  local try kern newroot
  for try in $(seq 20); do
    info -n ". "
    # crbug.com/463414: when the cgpt supports MTD (cgpt.bin), redirecting its
    # output will get duplicated data.
    kern="$(cgpt find -1 -u $KERN_ARG_KERN_GUID 2>/dev/null | uniq)"
    # We always try ROOT-A in recovery.
    newroot="${kern%[0-9]*}3"
    if [ -b "$newroot" ]; then
      USB_DEV="$newroot"
      info "Found ${USB_DEV}"
      return 0
    fi
    sleep 1
  done
  info "Failed waiting for device with correct kern_guid."
  return 1
}

# Look for any USB device.
wait_for_root() {
  info -n "Waiting for $USB_DEVS to appear"
  for try in $(seq 20); do
    info -n " ."
    for dev in $USB_DEVS; do
      if [ -b "/dev/$dev" ]; then
        USB_DEV="/dev/$dev"
        info "Found $USB_DEV"
        return 0
      fi
    done
    sleep 1
  done
  info "Failed waiting for root!"
  return 1
}

# Attempt to find the root defined in the signed factory shim
# kernel we're booted into to. Exports REAL_USB_DEV if there
# is a root partition that may be used - on succes or failure.
find_official_root() {
  info -n "Checking for an official root... "

  # Check for a kernel selected root device or one in a well known location.
  wait_for_gpt_root || wait_for_root || return 1

  # Now see if it has a Chrome OS rootfs partition.
  cgpt find -t rootfs "$(strip_partition "$USB_DEV")" || return 1
  REAL_USB_DEV="$USB_DEV"

  # USB_DEV points to the rootfs partition of removable media. And its value
  # can be one of /dev/sda3 (arm), /dev/sdb3 (x86, arm) and /dev/mmcblk1p3
  # (arm). Get stateful partition by replacing partition number with "1".
  LOG_DEV="${USB_DEV%[0-9]*}"1  # Default to stateful.

  mount_usb
}

mount_usb() {
  info -n "Mounting usb... "
  for try in $(seq 20); do
    info -n ". "
    if mount -n -o ro "$USB_DEV" "$USB_MNT"; then
      info "OK."
      return 0
    fi
    sleep 1
  done
  info "Failed to mount usb!"
  return 1
}

get_stateful_dev() {
  STATE_DEV=${REAL_USB_DEV%[0-9]*}1
  if [ ! -b "$STATE_DEV" ]; then
    info "Failed to determine stateful device."
    return 1
  fi
  return 0
}

unmount_usb() {
  info "Unmounting ${USB_MNT}..."
  umount -n "${USB_MNT}"
  info ""
  info "$REAL_USB_DEV can now be safely removed."
  info ""
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

  info "Dumping dmesg to $LOG_DIR"
  dmesg >"$LOG_DIR"/dmesg

  local err=0
  local save_mnt=/save_mnt
  local save_dir_name="factory_shim_logs"
  local save_dir="${save_mnt}/${save_dir_name}"

  info "Saving log files from: $LOG_DIR -> $log_dev $(basename ${save_dir})"
  mkdir -p "${save_mnt}"
  mount -n -o sync,rw "${log_dev}" "${save_mnt}" || err=$?
  [ ${err} -ne 0 ] || rm -rf "${save_dir}" || err=$?
  [ ${err} -ne 0 ] || cp -r "${LOG_DIR}" "${save_dir}" || err=$?
  # Attempt umount, even if there was an error to avoid leaking the mount.
  umount -n "${save_mnt}" || err=1

  if [ ${err} -eq 0 ] ; then
    info "Successfully saved the log file."
    info ""
    info "Please remove the USB media, insert into a Linux machine,"
    info "mount the first partition, and find the logs in directory:"
    info "  ${save_dir_name}"
  else
    info "Failures seen trying to save log file."
  fi
}

stop_log_file() {
  # Drop logging
  exec >"${TTY}" 2>&1
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
    info "Exporting kernel argument $key as KERN_ARG_$key"
  done
}

mount_tmpfs() {
  info "Mounting tmpfs..."
  mount -n -t tmpfs tmpfs "$NEWROOT_MNT" -o "size=$TMPFS_SIZE"
}

copy_contents() {
  info "Copying contents of USB device to tmpfs..."
  local ret=0
  (cd "${USB_MNT}" ; tar cf - . | (cd "${NEWROOT_MNT}" && tar xf -)) || ret=$?
  if [ ${ret} -eq 0 ]; then
    info "Copy complete."
  else
    info "Copy failed with result ${ret}."
  fi
  return ${ret}
}

copy_lsb() {
  local lsb_file="dev_image/etc/lsb-factory"
  local dest_path="${NEWROOT_MNT}/mnt/stateful_partition/${lsb_file}"
  local src_path="${STATEFUL_MNT}/${lsb_file}"

  mkdir -p "$(dirname ${dest_path})"
  # Mounting ext3 as ext2 since the journal is unneeded in ro.
  if ! mount -n "${STATE_DEV}" "${STATEFUL_MNT}"; then
    info "Failed to mount ${STATE_DEV}!! Failing."
    return 1
  fi
  local ret=0
  if [ -f "${src_path}" ]; then
    info "Found ${src_path}"
    cp -a "${src_path}" "${dest_path}"
    echo "REAL_USB_DEV=${REAL_USB_DEV}" >>"${dest_path}"
  else
    info "Failed to find ${src_path}!! Failing."
    ret=1
  fi
  umount -n "${STATEFUL_MNT}" || true
  rmdir "${STATEFUL_MNT}" || true
  return "${ret}"
}

copy_bins() {
  # Copy essential binaries that are in the initramfs, but not in the root FS.
  info "Copying binaries to $NEWROOT_MNT"
  cp /bin/busybox $NEWROOT_MNT/bin

  # Modify some files that does not work (and not required) in tmpfs chroot.
  # This may be removed when we can build factory installer in "embedded" mode.
  local file="${NEWROOT_MNT}/usr/sbin/mount-encrypted"
  echo '#!/bin/sh' >"${file}"
  echo 'echo "Sorry, $0 is disabled on factory installer image."' >>"${file}"

  # We don't want any consoles to be executed.
  rm -f "${NEWROOT_MNT}"/etc/init/console-*.conf
}

move_mounts() {
  info "Moving $BASE_MOUNTS to $NEWROOT_MNT"
  for mnt in $BASE_MOUNTS; do
    # $mnt is a full path (leading '/'), so no '/' joiner
    mkdir -p "$NEWROOT_MNT$mnt"
    mount -n -o move "$mnt" "$NEWROOT_MNT$mnt"
  done
  # Adjust /dev files.
  TTY="${NEWROOT_MNT}${TTY}"
  LOG_TTY="${NEWROOT_MNT}${LOG_TTY}"
  [ -z "${LOG_DEV}" ] || LOG_DEV="${NEWROOT_MNT}${LOG_DEV}"
  # Make a copy of bootstrap log into new root.
  mkdir -p "${NEWROOT_MNT}${LOG_DIR}"
  cp -f "${LOG_FILE}" "${NEWROOT_MNT}${LOG_FILE}"
  info "Done."
}

use_new_root() {
  move_mounts

  # Chroot into newroot, erase the contents of the old /, and exec real init.
  info "About to switch root..."
  stop_log_file
  exec switch_root "${NEWROOT_MNT}" /sbin/init
}

check_block_dev() {
  info "Checking block_devmode flags"
  if crossystem 'block_devmode?1' 'wpsw_boot?1' 2>/dev/null; then
    info "
    crossystem flag 'block_devmode' is set on a write protected device.

    You need to disable hardware write protection to bypass this check.
    "
    return 1
  fi
  return 0
}

main() {
  # Setup environment.
  find_best_tty
  mkdir -p "${USB_MNT}" "${STATEFUL_MNT}" "${LOG_DIR}" "${NEWROOT_MNT}"

  exec >"${LOG_FILE}" 2>&1
  info "ChromeOS Factory Shim"
  info "----------------------------------------------------------------------"
  info "TTY: ${TTY}, LOG_TTY: ${LOG_TTY}"

  # Send all verbose output to debug TTY.
  (tail -f "${LOG_FILE}" >"${LOG_TTY}") &
  TAIL_PID="$!"

  # Export the kernel command line as a parsed blob prepending KERN_ARG_ to each
  # argument.
  export_args $(cat /proc/cmdline | sed -e 's/"[^"]*"/DROPPED/g')

  # TTY4 may be not available, but we don't have better choices on headless
  # devices.
  enable_debug_console "/dev/tty4"

  check_block_dev
  find_official_root
  get_stateful_dev

  info "Bootstrapping factory shim."
  # Copy rootfs contents to tmpfs, then unmount USB device.
  mount_tmpfs
  copy_contents
  copy_lsb
  copy_bins

  # USB device is unmounted, we can remove it now.
  unmount_usb

  # Switch to the new root
  use_new_root

  # Should never reach here.
  return 1
}

trap on_error EXIT
set -e
main "$@"
