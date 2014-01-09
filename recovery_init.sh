# Copyright (c) 2011 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This consists of functions sourced by the /init script and used
# exclusively for recovery images.  Note that this code uses the
# busybox shell (not bash, not dash).

# Starting kernel rollback version.
KERNEL_VER_MIN=0x10001
# TPM NVRAM index where the rollback kernel version is stored.
KERNEL_VER_TPM_NV_SPACE=0x1008
# TPM NVRAM index for the lockbox.
LOCKBOX_TPM_NV_SPACE=0x20000004
# Where chromeos-install will store any related hardware diagnostics data.
LOG_HARDWARE_DIAGNOSTICS=hardware_diagnostics.log


# Installation Target.
#  DST_DEV_BASE: A device path for concatenate partition number.
#                Sample: /dev/mmcblk0p /dev/sda
#                Usage: "${DST_DEV_BASE}${PART_NUM}"
#  DST: A device path for the block device itself (similar to rootdev -d).
#                Sample: /dev/mmcblk0 /dev/sda
DST_DEV_BASE=
DST=

# If we have a verified recovery root, ensure all blocks are valid before
# handing it off to the installer.
validate_recovery_root() {
  # Allow test recovery roots that are unverified.
  [ "$USB_DEV" = "/dev/dm-0" ] || return 0
  is_unofficial_root && return 0

  local usb_base=$(basename "$USB_DEV")
  local size=$(( 512 * $(cat /sys/block/$usb_base/size) ))

  # Ensure the verified rootfs is fully intact or fail with no USB_DEV.
  # REAL_USB_DEV is left intact.
  #
  # Correctness wins over speed for this.  Correctness also wins
  # over readability.  :-(
  #
  # High level summary:  The 'pv -n' command copies bytes from stdin
  # to stdout, and periodically prints *to stderr* the amount read
  # as a percentage of the size in the '-s' option.  The pipeline
  # redirects the stderr from 'pv' into stdin of 'progress_bar'.
  # This usage is covered in the pv(1) man page, which rightly warns
  # that "it may cause the programmer to overheat."
  (
    # The 'set -x' output goes to stderr, which would become input
    # to 'progress_bar', below.  Turn it off in a subshell so as not
    # to affect the main process.
    set +x
    (
      (
        # This 'dd' is the actual validation.  We must capture the
        # exit code in order to figure out whether it passed or not.
        dd if="$USB_DEV" bs=$((16 * 1024 * 1024)) 2>/dev/null
        echo $? >/tmp/verification_status
      ) | pv -n -s $size >/dev/null
    ) 2>&1 | ( set -x ; progress_bar ) >$LOG_DIR/progress.log 2>&1
  )
  if [ "$(cat /tmp/verification_status)" != "0" ]; then
    dlog "Included root filesystem could not be verified."
    umount "$USB_MNT"
    dmsetup remove "$DM_NAME"  # Free up the real root for use.
    USB_DEV=
    return 1
  fi
  return 0
}

# Accomodate sd* or mmcblk* devices
# TODO(shawnn): Sync the target device selection logic to chromeos-install.
# See http://crbug.com/336654.
get_dst() {
  # Find a non-removable /dev/sd* or /dev/mmcblk* device to install to.
  local num_dev=0
  local src_dev_base="${REAL_USB_DEV%[0-9]*}"
  local dev

  for dev in /sys/block/sd* /sys/block/mmcblk*; do
    if [ ! -d "${dev}" ]; then
      continue
    fi
    # Do not install to removable devices, or devices of size < 1 GiB
    # (2097152 blocks of size 512 bytes). Devices of such size are too small
    # for Chromium OS, and may in fact be special partitions of large drives.
    if [ "$(cat "${dev}/removable")" = 1 ]; then
      continue
    fi
    if [ "$(cat "${dev}/size")" -lt 2097152 ]; then
      continue
    fi

    DST="/dev/$(basename "${dev}")"
    : $(( num_dev += 1 ))

    if [ "${dev%[0-9]}" = "${dev}" ]; then
      # ex, sda => sda1, sdb1
      DST_DEV_BASE="/dev/$(basename "${dev}")"
    else
      # ex, mmcblk0 => mmcblk0p1
      DST_DEV_BASE="/dev/$(basename "${dev}")p"
    fi
  done

  # Check that there is only 1 internal device. This will fail on non-ChromeOS
  # devices with more than 1 internal drive, but the user is very unlikely
  # to want to take that approach since it is uncertain which drive this
  # will install to.
  if [ ${num_dev} -ne 1 ]; then
    return 1
  fi

  if [ "${src_dev_base}" = "${DST_DEV_BASE}" ]; then
    dlog "Cannot find SSD for installation."
    return 1
  fi
  SRC_DEV_BASE="${src_dev_base}"
}

dev_wait_or_error() {
  is_developer_mode || on_error  # terminal if we get here in regular mode.
  message key_change
}

check_key_or_wait() {
  dlogf "Searching the system disk for a matching kernel key . . ."
  if ! cgpt find -t kernel -M "$1" "$DST"; then
    dlog " failed."
    dev_wait_or_error
    return 0
  fi
  dlog " found."

  dlogf "Validating matching signature(s) . . ."
  # If we found a keyblock, at the right offset, make sure it actually signed
  # the subsequent payload.
  local kdev=
  for kdev in $(cgpt find -t kernel -M "$1" "$DST"); do
    dlogf " ."
    verify_kernel_signature "$kdev" "/tmp/kern.keyblock" || continue
    dlog " done."
    return 0
  done

  dlog " failed."
  dev_wait_or_error
  return 0
}

# Get the kernel version by directly reading the TPM NVRAM spaces.
# Needed when crossystem doesn't work (e.g. Mario systems).
get_kernelver_from_tpmc () {
  set -- $(tpmc read $KERNEL_VER_TPM_NV_SPACE 9)
  # Example output:
  #
  # 1 4c 57 52 47 1 0 1 0
  #
  # The first 5 bytes of the output are a canary value and can be
  # ignored. The full kernel version is stored as a 32-bit integer
  # in little endian format.
  echo "$(( $9 << 24 | $8 << 16 | $7 << 8 | $6 ))"
}

verify_kernel_signature() {
  local kern_dev="$1"
  local keyblock="$2"

  if ! dd if="$kern_dev" of="/tmp/kern.bin"; then
    return 1
  fi

  # Validates the signature and outputs a keyblock.
  if ! vbutil_kernel --verify "/tmp/kern.bin" \
                     --keyblock "$keyblock"; then
    return 1
  fi
  return 0
}

verify_kernel_version() {
  local kern_dev="$1"
  local minversion="$KERNEL_VER_MIN"

  if ! dd if="$kern_dev" of="/tmp/kern.bin"; then
    return 1
  fi

  # Get the currently set TPM NVRAM rollback versions.
  minversion=$(crossystem tpm_kernver || get_kernelver_from_tpmc)
  dlog "Rollback version stored in the TPM: $minversion"

  # Validate the signature and rollback versions.
  if ! vbutil_kernel --verify "/tmp/kern.bin" --minversion "$minversion"; then
    return 1
  fi
  return 0
}

verify_install_kernel() {
  # TODO(wad) check signatures from stateful on kern b using the
  #           root of trust instead of using a baked in cmdline.
  if [ "$REAL_KERN_B_HASH" != "$KERN_ARG_KERN_B_HASH" ]; then
    # Assertion: we have to be in developer mode; this was verified in the
    # course of the general init process.
    is_developer_mode || return 1

    message developer_image

    # Extract the kernel so that vbutil_kernel will happily consume it.
    dlog "Checking the install kernel for a valid developer signature . . ."
    verify_kernel_signature "$KERN_B_DEV" "/tmp/kern_b.keyblock" || return 1
    check_key_or_wait /tmp/kern_b.keyblock
    return 0
  fi

  # Looks like we have an official recovery image. Check for version rollback.
  dlog "Checking the install kernel for valid versions and signature . . ."
  if ! verify_kernel_version "$KERN_B_DEV"; then
    if ! is_developer_mode; then
      # Rollback version check failure is fatal if we are not in developer mode.
      message invalid_install_kernel
      return 1
    fi
    message warn_invalid_install_kernel
  fi

  return 0
}

setup_install_mounts() {
  mount -t tmpfs -o mode=1777 none "$USB_MNT/tmp" || return 1
  dlog "Re-binding $BASE_MOUNTS for $NEWROOT_MNT"
  for mnt in $BASE_MOUNTS; do
    # $mnt is a full path (leading '/'), so no '/' joiner
    mkdir -p "$NEWROOT_MNT$mnt"
    mount -n -o bind "$mnt" "$NEWROOT_MNT$mnt" || return 1
  done
  dlog "Done."
  return 0
}

cleanup_install_mounts() {
  dlog "Unmounting $BASE_MOUNTS in $NEWROOT_MNT"
  for mnt in $BASE_MOUNTS; do
    # $mnt is a full path (leading '/'), so no '/' joiner
    umount "$NEWROOT_MNT$mnt"
  done
  dlog "Done."
  umount "$USB_MNT/tmp"
  return 0
}

call_image_recovery_script() {
  # Until images are built with the installer keyblock in KERN-B by
  # default, we keep copying over the installer vblock from the
  # stateful partition.
  # TODO(wad) http://crosbug/8378
  setup_install_mounts || return 1

  dlog "Installing software; this will take some time."
  dlog "See the debug log on VT3 for the full output."

  # Prevent accidentally loading modules from the usb mount
  echo 1 >/proc/sys/kernel/modules_disabled

  local install_status
  if [ -x "$USB_MNT/usr/sbin/chromeos-recovery" ]; then
    chroot "$USB_MNT" /usr/sbin/chromeos-recovery "$1"
    install_status=$?
  else
    export IS_RECOVERY_INSTALL=1
    chroot "$USB_MNT" \
      /usr/sbin/chromeos-install --yes --run_as_root \
                                 --payload_image="$1" \
                                 --use_payload_kern_b
    install_status=$?
  fi
  if [  $install_status -ne 0 ]; then
    dlog "WARNING!!! Installation of software failed. Displaying hw diagnostics"
    local diagnostics_file="$USB_MNT/tmp/$LOG_HARDWARE_DIAGNOSTICS"
    if [ -f "$diagnostics_file" ]; then
      cp "$diagnostics_file" "$LOG_DIR"
      dlog \
"============================ HARDWARE DIAGNOSTICS =========================="
      dlog $(cat "$diagnostics_file")
      dlog "See recovery log for more information."
      dlog \
"============================================================================"
      dlog
    else
      dlog "Missing hardware diagnostics."
    fi
  fi

  # No error check here:  Clean up doesn't need to be successful.
  cleanup_install_mounts

  return $install_status
}

clobber_lockbox_space() {
  # Clobber the lockbox space, by defining a new space at the same index.
  # Protection flags and size of the new space don't matter, as it will get
  # recreated again by cryptohome.
  local ppwrite_permission=0x1
  local temporary_lockbox_size=1
  tpmc def $LOCKBOX_TPM_NV_SPACE $temporary_lockbox_size $ppwrite_permission
}

clear_tpm() {
  dlogf "Resetting security device . . ."
  # TODO(wad) should we fail on this?
  tpmc ppon || dlog "tpmc ppon error: $?"
  tpmc clear || dlog "tpmc clear error: $?"
  tpmc enable || dlog "tpmc enable error: $?"
  tpmc activate || dlog "tpmc activate error: $?"
  clobber_lockbox_space || dlog "error clobbering lockbox space: $?"
  tpmc pplock || dlog "tpmc pplock error: $?"
  dlog " done."
  return 0
}

recover_system() {
  local source=$(strip_partition "$REAL_USB_DEV")
  dlog "Beginning system recovery from $source"

  # If we're not running a developer script then we're either
  # installing a developer image or an official one. If we're
  # in normal recovery mode, then we require that the KERN-B
  # on the recovery image matches the hash on the command line.
  # In developer mode, we will just check the keys.
  verify_install_kernel || return 1

  # Only clear on full installs. Shim scripts can call tpmc if they
  # like.  Only bGlobalLock will be in place in advance.
  clear_tpm || return 1

  message recovery_start

  call_image_recovery_script "$source" || return 1

  return 0
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
  if mount -n -o sync,rw "${REAL_USB_DEV%[0-9]*}1" /tmp; then
    if [ -f /tmp/non_interactive ]; then
      usb_node_dir=""
    fi
    umount /tmp
  fi
  echo "$usb_node_dir"
}

get_usb_debugging_flag() {
  local decrypt=""
  if get_stateful_dev && mount -n -o sync,ro "${STATE_DEV}" /tmp; then
    if [ -f /tmp/decrypt_stateful ]; then
      decrypt=$(cat /tmp/decrypt_stateful)
    fi
    umount /tmp
  fi
  echo "$decrypt"
}

maybe_get_debugging_logs() {
  local state=$(get_usb_debugging_flag)
  if [ -z "$state" ]; then
    return 0
  fi
  log "Stateful recovery requested."

  dlog "Attempting to find the destination stateful . . ."
  get_dst || return 0

  log "Please wait (this may take up to 2 and a half minutes). . ."
  sleep 150  # Five minutes in half.
  if ! mount -n -o sync,rw "${DST_DEV_BASE}1" "${STATEFUL_MNT}"; then
    log "Unable to perform stateful recovery."
    dlog "mount failed for ${DST_DEV_BASE}1"
    sleep 1d
    reboot -f
  fi

  local flagfile="${STATEFUL_MNT}/decrypt_stateful"
  local decrypted_dir="${STATEFUL_MNT}/decrypted"
  local tarball_dir="/tmp/recovery"
  local tarball="${tarball_dir}/extracted.tgz"
  # Check if the files exist already or if recovery needs to be requested.
  if [ -f "$flagfile" ] && [ ! -d "$decrypted_dir" ]; then
    log "Prior recovery request incomplete. Starting over . . ."
  fi
  if [ -f "$flagfile" ] && [ -d "$decrypted_dir" ]; then
    log "Prior recovery request exists. Attempting to extract files."
    if ! mount -n -o sync,rw "${STATE_DEV}" /tmp 2>"$TTY_PATH"2; then
      log "Failed to mount recovery stateful partition."
      on_error
    fi
    mkdir -p "$tarball_dir" || on_error
    log "Copying files . . ."
    # Due to the tty redirection that this script runs under, without the
    # explicit stdin and stdout redirects, tar will fail with "Broken pipe".
    if ! tar -czf "${tarball}" -C "${STATEFUL_MNT}" \
         --exclude './decrypt_stateful' \
         --exclude './encrypted*' \
         --exclude './home/.shadow/*/*' \
         --exclude './dev_image' \
         . >"$TTY_PATH2"2 2>"$TTY_PATH"2 </dev/null ; then
      log "Extraction failed. See debug log for more details."
      crossystem recovery_request=1
      umount /tmp
      umount "${STATEFUL_MNT}"
      on_error
    fi
    log "Removing the request file and old data . . ."
    rm -f "${flagfile}"
    rm -rf "${decrypted_dir}"
    umount /tmp
    umount "${STATEFUL_MNT}"
    log "Operation complete, you can now remove your recovery media."
    log "The requested data can be found in the /recovery folder."
    sleep 1d
    reboot -f
  fi

  log "Stateful recovery requires authentication."
  log "Your username and salted password will be temporarily written to the"
  log "device for the duration of this recovery process. Once finished,"
  log "please be sure to change your password as a precautionary measure."

  local username
  read -p Username: username <"$TTY_PATH"1 2>"$TTY_PATH"1

  if [ -n "${username}" ]; then
    local password
    read -p Password: -s password <"$TTY_PATH"1 2>"$TTY_PATH"1
    # Force a newline for sane output after silent input.
    echo "" >"$TTY_PATH"1

    local saltfile="${STATEFUL_MNT}"/home/.shadow/salt
    if [ ! -f "${saltfile}" ]; then
      log "Target has no system salt file. Giving up."
      sleep 1d
      reboot -f
    fi

    local salt=$(hexdump -v -e '/1 "%02x"' <"$saltfile")
    local passkey=$(echo -n "${salt}${password}" | sha256sum | cut -c-32)

    log "Installing v2 request file . . ."
    cat > "${flagfile}" <<EOM
2
$username
$passkey
EOM
  else
    log "Installing v1 request file . . ."
    echo -n "1" > "${flagfile}"
  fi
  umount "${STATEFUL_MNT}"

  log "Stateful recovery initiation completed."
  log "In 60 seconds, the system will reboot to the local OS."
  log "Once the files are prepared, it will return back to recovery mode."
  log "Please use this same recovery media."
  sleep 60
  reboot -f  # Back to the system!
  return 1
}

recovery_install() {
  NEWROOT_MNT="$USB_MNT"

  # Always lock the TPM.  If a NVRAM reset is ever needed, we can change it.
  lock_tpm || on_error

  # Check if we're really doing debugging log extraction.
  maybe_get_debugging_logs || return 1

  # Perform a full device mapper root validation to avoid any unexpected
  # failures during postinst.  It also allows us to detect if the root is
  # intentionally mismatched - such as during Chromium OS recovery with a
  # Chrome OS recovery kernel.
  if ! validate_recovery_root; then
    # The root we just mounted looked like an official recovery
    # image, but it didn't pass validation.  Try to fall back to
    # installing a developer image.
    find_developer_root || on_error
    get_stateful_dev || on_error
    message developer_image
  fi

  get_dst || on_error

  recover_system || on_error

  stop_log_file
  # Save the recovery log to the target on success and the USB.
  save_log_files "$DST_DEV_BASE"1 ext4
  save_log_files "$SRC_DEV_BASE"12 vfat
  save_log_files "$SRC_DEV_BASE"1 ext4

  # This assignment depends on the stateful partition on the USB
  # stick, so we must do it before unmount_usb and the
  # "recovery_complete" message, because the user could remove the
  # USB stick from that moment forward.
  local usb_node_dir=$(get_usb_node_dir)

  unmount_usb
  message recovery_complete

  if [ -n "$usb_node_dir" ]; then
    # Default (interactive) case; wait till the user removes the USB
    # stick.
    while [ -d "$usb_node_dir" ]; do
      sleep 1
    done
  elif [ $(cat /sys/devices/virtual/tty/tty0/active) != tty1 ]; then
    # Special (non-interactive) test case, and the user is watching
    # VT2 or VT3.  Stay up a long time to allow for debugging.
    dlog "Recovery is complete!  The system will remain up to allow"
    dlog "you to examine VT screen contents.  You must manually"
    dlog "power off when you're done."
    sleep 1d
  else
    # Special (non-interactive) test case; reboot after a nominal
    # pause to allow a human to observe the screen.
    sleep 10
  fi

  reboot -f
  exit 0
}
