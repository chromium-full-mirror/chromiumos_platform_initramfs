# Copyright (c) 2012 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This consists of functions sourced by the /init script and used
# exclusively for factory install shim images.  Note that this code
# uses the busybox shell (not bash, not dash).

# Size of the root ramdisk.
TMPFS_SIZE=400M

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
  exec switch_root -c /dev/tty2 "$NEWROOT_MNT" /sbin/init

  # This should not really happen.
  log "Failed to switch root."
  save_log_files
  return 1
}

netboot_ramfs_install() {
  mkdir -p /var/log
  touch /var/log/softwareupdate.log
  (tail -f /var/log/softwareupdate.log >/dev/tty1) &

  # For network boot, we are not able to retrieve install log if anything
  # goes wrong. When installation fails, a shell on TTY4 would be handy.
  # For security reason, this is disabled by default. Uncomment this line
  # and do a local build by make_netboot.sh to build a netboot image with
  # shell.
  # (sh </dev/tty4 >/dev/tty4 2>/dev/tty4) &

  # In case an error is not handled by factory installer itself, stop here
  # so that an operator can see installation stop.
  factory_install.sh >/dev/tty1 || sleep 1d
}

factory_install() {
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
