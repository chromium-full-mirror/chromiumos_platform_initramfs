# Copyright (c) 2011 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This consists of functions sourced by the /init script and used
# exclusively for factory install shim images.  Note that this code
# uses the busybox shell (not bash, not dash).

mount_tmpfs() {
  dlog "Mounting tmpfs..."
  mount -n -t tmpfs tmpfs "$NEWROOT_MNT" -o "size=$TMPFS_SIZE"
  return $?
}

copy_contents() {
  log "Copying usb->tmpfs..."
  (cd "${USB_MNT}" ; tar cf - . | (cd "${NEWROOT_MNT}" && tar xf  -))
  RES=$?
  log "Copy returned with result $RES"
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
  exec switch_root -c /dev/console "$NEWROOT_MNT" /sbin/init

  # This should not really happen.
  log "Failed to switch root."
  save_log_file
  return 1
}

factory_install() {
  # devsw_boot is 0 on dev + recovery boot on Parrot.
  # TODO(yongjaek) When the virtual switches are fixed in crossystem, it
  # should be reverted.
  if [ "$(crossystem devsw_boot)" = "0" \
       -a "$(crossystem recoverysw_boot)" = "0" ]; then
    on_error
  fi
  # Copy rootfs contents to tmpfs, then unmount USB device.
  NEWROOT_MNT=/newroot
  mount_tmpfs || on_error
  copy_contents || on_error
  copy_lsb || on_error
  # USB device is unmounted, we can remove it now.
  unmount_usb || on_error
  # Switch to the new root
  use_new_root || on_error
  on_error # !! Never reached. !!
}
