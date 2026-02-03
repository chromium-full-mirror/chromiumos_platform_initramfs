#!/bin/sh -u
# Copyright 2025 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This consists of functions sourced by the /init script and used
# exclusively for recovery images.  Note that this code uses the
# busybox shell (not bash, not dash).

# Include disk information.
. /usr/sbin/write_gpt.sh
# Include firmware rollback check functions.
. /lib/fw_rollback_check.sh

# Installation Target.
#  DST_DEV_BASE: A device path for concatenate partition number.
#                Sample: /dev/mmcblk0p /dev/sda
#                Usage: "${DST_DEV_BASE}${PART_NUM}"
#  DST: A device path for the block device itself (similar to rootdev -d).
#                Sample: /dev/mmcblk0 /dev/sda
DST_DEV_BASE=
DST=


# Error codes used as return code by functions to indicate installation
# should be aborted for the corresponding reason.

# Indicates a failure validating the kernel.
ERR_INVALID_INSTALL_KERNEL=2

# The image failed validation on a device with block_devmode=1.
ERR_DEV_MODE_BLOCKED=3

get_dst() {
  load_base_vars
  DST="$(get_fixed_dst_drive)"
  if [ -z "${DST}" ]; then
    dlog "SSD for installation not specified"
    return 1
  fi
  if [ "${DST%[0-9]}" = "${DST}" ]; then
    # ex, sda => sda1, sdb1
    DST_DEV_BASE="${DST}"
  else
    # ex, mmcblk0 => mmcblk0p1
    DST_DEV_BASE="${DST}p"
  fi
  local src_dev_base="${REAL_USB_DEV%[0-9]*}"
  if [ "${src_dev_base}" = "${DST_DEV_BASE}" ]; then
    dlog "Cannot find SSD for installation."
    return 1
  fi
  SRC_DEV_BASE="${src_dev_base}"
}

recovery_install_internal() {
  local extra_flags=

  message recovery_in_progress

  echo y | chroot . /bin/sh -x /lib/desktop-recovery-install.sh "${REAL_USB_DEV}" "$(strip_partition ${DST_DEV_BASE}1)"
  return $?
}

# Return the path to the node under /sys/block associated with
# the USB stick.  The existence of that path is used to test whether
# the user has removed the stick and we can reboot.
#
# For certain non-interactive test cases, the stateful partition on
# the USB stick may be flagged to request that we bypass the
# interactive removal of the USB stick.  If we detect that
# condition, we signal it by returning an empty string instead
# of a path.
get_usb_node_dir() {
  local usb_node_dir=/sys/block/$(strip_partition "${REAL_USB_DEV##*/}")
  echo "$usb_node_dir"
}

# Shows the appropriate error screen for the specified error code and
# stops further action, i.e. doesn't return.
handle_error() {
  save_log_files

  case "$1" in
    $ERR_DEV_MODE_BLOCKED)
      message block_developer_mode
      ;;
    $ERR_INVALID_INSTALL_KERNEL)
      message invalid_install_kernel
      ;;
    *)
      # Show the generic error screen by default.
      on_error
      ;;
  esac
}

# Terminate with an error message.  We don't want to do anything
# else (like start a shell) because it would be trivially easy to
# get here (just unplug the USB drive after the kernel starts but
# before the USB drives are probed by the kernel) and starting a
# shell here would be a BIG security hole.
on_error() {
  message on_error
  signal_fatal_error
}

# Called after displaying some fatal error message.  This method will sync
# disks, and never return.
signal_fatal_error() {
  save_log_files
  sleep 1d
  exit 1
}

recovery_install() {
  get_dst || on_error

  # Update the FW
  echo "Mounting source device"
  mkdir -p /tmp/fw
  mount -oro "${SRC_DEV_BASE}5" /tmp/fw || on_error

  if ! futility update -a /tmp/fw/chromeos-firmwareupdate -m recovery --force; then
    rc=$?
    umount /tmp/fw
    handle_error "${rc}"
  fi
  umount /tmp/fw

  sleep 2

  if [ -n "${KERN_ARG_INSECURE_KEEP_ADB_GBB:-}" ]; then
    dlog 'Found insecure_keep_adb_gbb in kernel cmdline. Keeping GBB flag 0x80000000 intact.'
  else
    futility gbb --set --flash --flags -0x80000000
    sleep 2
  fi

  recovery_install_internal || handle_error $?

  # Enable dev_boot_usb by default
  # TODO(b/457449610): Remove this line once crossystem will be available
  # on user builds and enabling USB boot will be possible through UI.
  crossystem dev_boot_usb=1

  # Save the logs to the USB stick on success.
  save_log_files

  # This assignment depends on the stateful partition on the USB
  # stick, so we must do it before unmount_usb and the
  # "recovery_complete" message, because the user could remove the
  # USB stick from that moment forward.
  local usb_node_dir=$(get_usb_node_dir)

  #unmount_usb
  message recovery_complete
  # Wait until the user removes the USB stick.
  while [ -d "$usb_node_dir" ]; do
    sleep 1
  done

  reboot -f
  exit 0
}
