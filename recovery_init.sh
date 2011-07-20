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
    ) 2>&1 | progress_bar
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
get_dst() {
  local arch="$(crossystem arch)"

  # We can't trust the source (USB) media to find destination because ARM
  # supports booting from both USB(sd*) and SD Card Reader (mmcblk*).
  # The current solution is to hard-code destination by architecture -- which is
  # also how factory test program works.

  case "$arch" in
    x86 )
      DST="/dev/sda"
      DST_DEV_BASE="$DST"
      ;;
    arm )
      DST="/dev/mmcblk0"
      DST_DEV_BASE="$DST"p
      ;;
    * )
      dlog "Unknown platform ($arch), cannot identify destination."
      return 1
      ;;
  esac

  local src_dev_base="${REAL_USB_DEV%[0-9]*}"
  if [ "${src_dev_base}" = "$DST_DEV_BASE" ]; then
    dlog "Cannot find SSD for installation."
    return 1
  fi
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

get_kern_b_device() {
  # TODO(wad) By changing boot priority, could we end up
  # checking the recovery image or the recovery image could not
  # be in slot A. In that case, it should fail in normal mode.
  KERN_B_DEV=${REAL_USB_DEV%[0-9]*}4
  if [ ! -b "${KERN_B_DEV}" ]; then
    return 1
  fi
  return 0
}

get_real_kern_b_hash() {
  REAL_KERN_B_HASH=$(dd if="${KERN_B_DEV}" | sha1sum | cut -f1 -d' ')
  [ -n "$REAL_KERN_B_HASH" ]
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
  get_kern_b_device || return 1
  get_real_kern_b_hash || return 1

  # TODO(wad) check signatures from stateful on kern b using the
  #           root of trust instead of using a baked in cmdline.
  if [ "$REAL_KERN_B_HASH" != "$KERN_ARG_KERN_B_HASH" ]; then
    if ! is_developer_mode; then
      dlog "The recovery kernel cannot be verified."
      return 1
    fi

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

touch_developer_mode_file() {
  is_developer_mode || return 1
  mount -n -o rw -t ext3 "$DST_DEV_BASE"1 "$STATEFUL_MNT" || return 1
  touch "$STATEFUL_MNT/.developer_mode" || return 1
  umount "$STATEFUL_MNT" || return 1
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
  dlog "Installing software; this will take some time."
  dlog "See the debug log on VT3 for the full output."

  # Until images are built with the installer keyblock in KERN-B by
  # default, we keep copying over the installer vblock from the
  # stateful partition.
  # TODO(wad) http://crosbug/8378
  setup_install_mounts || return 1
  export IS_RECOVERY_INSTALL=1
  chroot "$USB_MNT" \
    /usr/sbin/chromeos-install --run_as_root --yes \
                               --payload_image="$1" \
                               --use_payload_kern_b
  local install_status=$?
  if [  $install_status -ne 0 ]; then
    dlog "Installation of software failed."
  fi

  # No error check here:  Clean up doesn't need to be successful.
  cleanup_install_mounts

  # If we're in developer mode, touch the .developer_mode file on stateful
  # to avoid a bonus wait period on reboot.
  # Failure here is non-terminal and it may not succeed just because the
  # partition table of the destination has not been synchronized.
  if [  $install_status -eq 0 ]; then
    dlog "Prepping destination stateful to avoid a secondary delay."
    touch_developer_mode_file && dlog "Prepped image for developer use."
  fi

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

recovery_install() {
  NEWROOT_MNT="$USB_MNT"

  # Always lock the TPM.  If a NVRAM reset is ever needed, we can change it.
  lock_tpm || on_error

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
  save_log_file "$DST_DEV_BASE"1
  save_log_file

  unmount_usb

  message recovery_complete
  local usb_base=$(basename "${REAL_USB_DEV%[0-9]*}")
  while [ -d "/sys/block/$usb_base" ]; do
    sleep 1
  done

  reboot -f
  exit 0
}
