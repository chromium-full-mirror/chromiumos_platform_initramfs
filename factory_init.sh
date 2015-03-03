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
    # Convert it to upper case and store it to lsb file.
    local kern_guid=$(echo "${KERN_ARG_KERN_GUID}" |
                        tr '[:lower:]' '[:upper:]')
    log "Found ${src_path}"
    cp -a "${src_path}" "${dest_path}"
    echo "REAL_USB_DEV=$REAL_USB_DEV" >>"${dest_path}"
    echo "KERN_ARG_KERN_GUID=${kern_guid}" >>"${dest_path}"
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

  # Install busybox bins for factory installer and add to path.
  mkdir /tmp/busybox-bins
  busybox --install /tmp/busybox-bins
  PATH="$PATH":/tmp/busybox-bins
  export PATH

  # For network boot, we are not able to retrieve install log if anything
  # goes wrong. When installation fails, a shell on TTY5 would be handy.
  # For security reason, this is disabled by default. Uncomment this line
  # and do a local build by make_netboot.sh to build a netboot image with
  # shell.
  # openvt -c 5 bash

  # In case an error is not handled by factory installer itself, stop here
  # so that an operator can see installation stop.
  openvt -c 1 factory_install.sh -w || sleep 1d
}

check_block_dev() {
  log "Checking block_devmode flags"
  if crossystem 'block_devmode?1' 'wpsw_boot?1' 2>/dev/null; then
    log "
    crossystem flag 'block_devmode' is set on a write protected device.

    You need to disable hardware write protection to bypass this check.
    "
    on_error
  fi
}

factory_install() {
  check_block_dev
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
