#!/bin/busybox sh
# Copyright 2021 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Bind PCI device to VFIO-PCI passthrough bus.
vfio_pci() {
  local sysfs=$1
  local bdf=$(basename "${sysfs}")
  local vendor_id=$(cat "${sysfs}/vendor")
  local device_id=$(cat "${sysfs}/device")
  local class=$(cat "${sysfs}/class")

  # Filter by CLASS
  case "${class}" in
  0x060000)
    return 1  # Ignore PCI Host Bridge.
    ;;
  0x060400)
    return 2  #link phyiscal pcie root port to virtual pcie root port
    ;;
  esac

  # Detach from current driver if any.
  local driver="${sysfs}/driver"
  if [[ -f "${driver}/unbind" ]]; then
    echo "${bdf}" > "${driver}/unbind"
  fi

  if [[ -f "/sys/bus/pci/drivers/vfio-pci-pm/new_id" ]]; then
    # Attach pci device to VFIO-PCI-PM bus driver (if exists).
    echo "${vendor_id} ${device_id}" > /sys/bus/pci/drivers/vfio-pci-pm/new_id
  fi

  # Absence of the unbind file implies the device has no PCI driver.
  # This is normal - either the kernel does not support the VFIO-PCI-PM driver,
  # or the PCI device failed to attach to it (most likely due to lack of PM
  # capability).
  if [[ ! -f "${driver}/unbind" ]]; then
    # Attach pci device to VFIO-PCI bus driver.
    echo "${vendor_id} ${device_id}" > /sys/bus/pci/drivers/vfio-pci/new_id
  fi
}

# Sets up PCI passthrough and outputs the necessary crosvm flags.
get_pci_passthrough() {
  cbmem -a TS_CRHV_HW_PASSTRHOUGH_START

  # VFIO: Direct attach all usable PCI devices.
  local serial_bdf=$(readlink -f /sys/class/tty/ttyS0 | cut -d / -f 5)
  for dev in `find /sys/bus/pci/devices -type l | sort`; do
    local bdf=$(basename "${dev}")
    if [[ "${bdf}" == "${serial_bdf}" ]]; then
      # Keep the serial device in the hypervisor. Configure a stub PCI device in
      # its place so enumeration of the other function works properly in the
      # guest.
      local stub_params="${bdf}"
      # Identifiers per "Google PCI Device and Subsystem ID Allocations".
      stub_params="${stub_params},vendor=0x1ae0"
      stub_params="${stub_params},device=0x0072"
      stub_params="${stub_params},subsystem_vendor=0x1ae0"
      stub_params="${stub_params},subsystem_device=0x00bf"
      # class code 0x13 is "non-essential instrumentation"
      stub_params="${stub_params},class=0x130000"
      echo "--stub-pci-device ${stub_params}"
      continue
    fi

    vfio_pci "${dev}"
    local val=$?
    if [[ $val -eq 0 ]]; then
      echo "--vfio ${dev},iommu=coiommu"
    elif [[ $val -eq 2 ]]; then
      if [ -n "${TBT_PCIE_HP_GPE}" ]; then
        echo "--pcie-root-port ${dev},hp_gpe=${TBT_PCIE_HP_GPE}"
      else
        echo "--pcie-root-port ${dev}"
      fi
    fi
  done

  cbmem -a TS_CRHV_HW_PASSTRHOUGH_END
}

# Port I/O & MMIO forwarding.
get_platform_pmio() {
  local pmio="${BOARD_PMIO:-128}"
  echo "--no-legacy --direct-pmio /dev/port@${pmio}"
  if [ -n "${BOARD_MMIO}" ]; then
    echo "--direct-mmio /dev/mem@${BOARD_MMIO}"
  fi
}

# Interrupt forwarding argument helper.
get_platform_irqs() {
  local irq
  local irqs="${BOARD_IRQS:-edge:1}"
  for irq in ${irqs}; do
    echo "--direct-${irq%:*}-irq ${irq#*:}"
  done
}

# GPE forwarding argument helper.
get_platform_gpes() {
  if [ -n "${BOARD_GPES}" ]; then
    printf "--direct-gpe %s\n" ${BOARD_GPES}
  fi

  if [ -n "${TBT_PCIE_HP_GPE}" ]; then
    echo "--direct-gpe ${TBT_PCIE_HP_GPE}"
  fi
}

# MSR forwarding argument helper.
get_platform_msrs() {
  printf "--userspace-msr=%s,type=r,action=pass\n" ${BOARD_MSR}
}

# Reads the coreboot table and generates crosvm command line options to map
# cbmem memory regions into the guest.
#
# TODO(b/173614113): This function is clearly beyond the line of what is a good
# idea to write and maintain in shell. The plan is to fold the init logic into
# trichechus, as part of which this will be rewritten in rust.
get_cbmem_mappings() {
  local cbmem
  if ! cbmem=$(cbmem -l); then
    echo "Failed to read cbmem regions" 1>&2
    return;
  fi

  # Map the page at address zero, where coreboot stores a coreboot table there
  # that contains a "forwarding entry" which in turn points at the actual
  # coreboot table. cbmem makes use of this to locate the coreboot table, so add
  # a mapping to make cbmem work in the guest.
  echo "--file-backed-mapping addr=0x0,size=0x1000,path=/dev/mem"

  # Go through the coreboot table entries and create mappings for them. Note
  # that the small region entries are only aligned to 4 bytes. The code below
  # handles this by coalescing mappings into a smaller number of page-aligned
  # mappings.
  (
    echo "${cbmem}"
    # Add a fake entry beyond the last one to trigger the start-of-a-new-region
    # condition in the last loop iteration below and output the final mapping.
    echo "99. TERMINATOR  ffffffff  fffff000   00000000"
  ) | tail +3 | awk '{ print $(NF - 1) " " $NF " " $(NF - 2) }' | sort | \
  while read -r start len id; do
    hstart="0x${start}"
    hlen="0x${len}"

    # 4k-align start and length of the region. This will potentially map more
    # memory than specified in the cbmem region. That's OK since there's no need
    # to hide any data in cbmem from the OS. Note that the large cbmem regions
    # are page-aligned anyways (they may have odd size, but coreboot allocates
    # the region with aligned size).
    rstart=$(printf '%#x' $((hstart & ~0xfff)))
    rlen=$(printf '%#x' $((((hstart + hlen + 0xfff) & ~0xfff) - rstart)))

    # Determine extra mapping options. These are generally only safe to put for
    # large regions since new mappings with changed options can only start at
    # page-aligned boundaries.
    rextra=""
    case "${id}" in
      05430095) # RAMOOPS
        rextra=",rw"
        ;;
    esac

    if [ $((addr + size)) -lt $((rstart)) ] ||
       [ "${extra}" != "${rextra}" ]; then
      # Start of the region is beyond the end of the previous ones that have
      # been gathered and coalesced into [addr, addr+size]. Thus, emit what has
      # been gathered and start a new mapping. Note that in the first iteration
      # this branch is hit as well, but there is no previous region data; the
      # tail +2 below filters the corresponding bogus line.
      params="addr=${addr},size=${size},offset=${addr},path=/dev/mem"
      echo "--file-backed-mapping ${params}${extra}"
      addr="${rstart}"
      size="${rlen}"
      extra="${rextra}"
    else
      size=$(printf "%#x" $((rstart + rlen - addr)))
    fi
  done | tail +2  # drops the bogus region emitted by the first loop iteration
}

# Prints crosvm arguments to enable virtio-vhost-user proxy devices.
get_vvu_proxy_devices() {
  # Total number of virtio devices that sibling VMs will use.
  local VVU_DEVICE_NUM="$1"
  local i=0
  while [ "$(( i += 1 ))" -le "${VVU_DEVICE_NUM}" ]; do
    # Embed the device index as the valid UUID value's lower 12 bytes.
    # So the guest can reconstruct the socket path by reading /sys/devices/.
    printf \
      "--vvu-proxy=/run/crosvm-vvu%02d.sock,\
uuid=00000000-0000-4000-8000-%012x\n" "${i}" "${i}"
  done
}

# Root bridge regions are specified in ACPI tables passed to the guest. Keep
# the guest kernel happy by limiting crosvm pci bars to those regions.
get_host_bridge_regions() {
  # Translate lines of the form "80400000-dfffffff : PCI Bus 0000:00" into
  # lines of the form "0x80400000-0xdfffffff".
  local regexp="s/^\([0-9a-f]*\)-\([0-9a-f]*\) : PCI Bus 0000:00/0x\1-0x\2/p"
  local regions=$(echo "$1" | sed -n "${regexp}" | paste -sd ',')
  echo "--mmio-address-range ${regions}"
}

# Get guest kernel command line options.
get_cmdline() {
  local cmd="$(cat /proc/cmdline)"

  # This is to avoid accessing package level MSRs which is not
  # available on the guest
  cmd="${cmd/warn_on_s0ix_failures=1\ /warn_on_s0ix_failures=0\ }"

  # PCI workaround
  cmd="pci=lastbus=255 pci=realloc=off ${cmd}"

  # Disable strict IOMMU for guest kernel.
  cmd="$(echo "${cmd}" | sed 's|iommu=on |iommu=off |')"

  # Filter out hypervisor-specific cmdline options.
  cmd="$(echo "${cmd}" | sed 's|swiotlb=noforce ||')"
  cmd="$(echo "${cmd}" | sed 's|dhash_entries=[0-9]* ||')"
  cmd="$(echo "${cmd}" | sed 's|ihash_entries=[0-9]* ||')"

  # Uncomment to disable standard boot flow.
  # cmd="$(echo "${cmd}" | sed 's|init=.*root=|init=/bin/bash root=|')"

  # Uncomment for incorrect rootfs UUID workaround.
  # cmd="$(echo "${cmd}" | sed 's|root=.* rootwait|root=/dev/nvme0n1p3|')"

  # Prevent the guest from using hardware ramoops memory.
  cmd="initcall_blacklist=chromeos_pstore_init ${cmd}"  # nocheck

  # Emulated ramoops does not have ECC.
  cmd="$(echo "${cmd}" | sed 's|ramoops.ecc=1 ||')"

  # From drivers/platform/chrome/chromeos_pstore.c in the kernel.
  cmd="${cmd} ramoops.record_size=0x40000"
  cmd="${cmd} ramoops.console_size=0x20000"
  cmd="${cmd} ramoops.ftrace_size=0x20000"
  cmd="${cmd} ramoops.pmsg_size=0x20000"
  cmd="${cmd} ramoops.max_reason=2"  # KMSG_DUMP_OOPS

  # Disallow LPS0 _DSM function 5 in the guest
  cmd="${cmd} acpi.sleep_no_lps0"

  # Since virtio-iommu doesn't advertise interrupt remapping, this param is
  # necessary for the virtio-vhost-user VFIO driver. This does not actually
  # expose any MSI attacks. Since the hypervisor does not allow unsafe
  # interrupts, passthrough devices are safe, and virtualized devices don't
  # expose hardware MSI in the first place.
  cmd="${cmd} vfio_iommu_type1.allow_unsafe_interrupts=1"

  echo "${cmd}"
}

get_serial_port_config() {
  case "${manatee_serial}" in
    off)
      echo "--serial hardware=serial,type=sink"
      ;;
    os)
      # OS to control serial port - route input to guest.
      echo "--serial hardware=serial,type=stdout,stdin=true"
      ;;
    *)
      # Send OS output to the serial port even if input is going elsewhere.
      echo "--serial hardware=serial,type=stdout"
      ;;
  esac
}

# Get the architecture to know whether it is x86_64 or arm.
get_platform_arch() {
  uname -m
}

pstore_path="/run/crosvm.pstore"

get_pstore_args() {
  size="$(stat -c "%s" "${pstore_path}")"
  echo "--pstore path=${pstore_path},size=${size}"
}

setup_pstore() {
  cbmem -a TS_CRHV_PSTORE_START
  trichechus --restore-pstore --pstore-path "${pstore_path}"
  cbmem -a TS_CRHV_PSTORE_END
}

save_pstore() {
  sync -f "${pstore_path}"
  trichechus --save-pstore --pstore-path "${pstore_path}" "$@"
}

get_pcie_ecam() {
  # Translate lines of the form "d0000000-dfffffff : PCI MMCONFIG 0000" into
  # lines of the form "0xd0000000-0xdfffffff".
  regexp="s/\([0-9a-f]*\)-\([0-9a-f]*\) : PCI MMCONFIG 0000/0x\1-0x\2/p"
  regions=$(echo "$1" | sed -n "${regexp}")
  if [ -z "${regions}" ]; then
    return;
  fi
  #Only the first found take effect
  base_end=$(echo ${regions} | awk -F ' ' '{print $1}')
  base=$(echo ${base_end} | awk -F '-' '{print $1}')
  end=$(echo ${base_end} | awk -F '-' '{print $2}')
  len=$(($end - $base + 1))
  hlen=$(printf '0x%x' $len)

  echo "--pcie-ecam=$base,$hlen"
}

# Start primary guest VM.
run() {
  # Crosvm-direct command line.
  local args="-s /run/crosvm.sock --cid 3"
  args="${args} --balloon-control /run/mms_control_0.sock"
  args="${args} --strict-balloon"

  # TODO(b/184871003): Enable user space IOAPIC implementation.
  # args="${args} --split-irqchip"

  # TODO(b/185150434): enable minijail sandboxing.
  args="${args} --disable-sandbox"

  # Use all available CPUs for primary VM.
  local nproc=$(nproc)

  local arch="$(get_platform_arch)"
  if [ $(arch) = "x86_64" ]; then
    # crosvm now only supports "--host-cpu-topology" on x86_64.
    args="${args} --cpus ${nproc} --host-cpu-topology --itmt"
  else
    local affinity=$(
      for n in $(seq 0 $((nproc - 1))); do printf "$n=$n:"; done
    )
    args="${args} --cpus ${nproc} --cpu-affinity ${affinity%?}"
  fi

  args="${args} --mem ${CROS_GUEST_MEMORY}"

  # DMI: Use host SMBIOS info
  if [[ -d "/sys/firmware/dmi/tables" ]]; then
   args="${args} --dmi /sys/firmware/dmi/tables"
  fi

  # ACPI: Collect all valid host tables.
  for acpi in `find /sys/firmware/acpi/tables/ -type f`; do
    # Filter by name
    case "${acpi##*/}" in
    DMAR | FACS | APIC | MCFG)
      ;;
    *)
      args="${args} --acpi-table ${acpi}"
      ;;
    esac
  done

  # VFIO: Disable functional reset (b/173632817).
  echo 1 > /sys/module/vfio_pci/parameters/disable_function_reset
  # VFIO: Disable power management.
  echo 1 > /sys/module/vfio_pci/parameters/disable_idle_d3

  # VFIO: Remove limit on number of pinned regions
  # TODO(b/217479627): manage vfio_iommu_type1 memory
  echo 2147483648 > /sys/module/vfio_iommu_type1/parameters/dma_entry_limit

  # Device passthrough
  args="${args} $(get_pci_passthrough)"

  # Platform IOs
  args="${args} $(get_platform_pmio)"

  # Platform IRQs
  args="${args} $(get_platform_irqs)"

  # Platform GPEs
  args="${args} $(get_platform_gpes)"

  # cbmem mappings
  args="${args} $(get_cbmem_mappings)"

  # pcie ecam address and size
  args="${args} $(get_pcie_ecam "$(cat /proc/iomem)")"

  # CrOS is a privileged guest
  args="${args} --privileged-vm"

  # serial port
  args="${args} $(get_serial_port_config)"

  # Enable virtio-vhost-user proxy devices
  args="${args} $(get_vvu_proxy_devices 10)"

  # userspace msr support
  args="${args} $(get_platform_msrs)"

  # Limit mmio regions to match ACPI
  args="${args} $(get_host_bridge_regions "`cat /proc/iomem`")"

  setup_pstore && args="${args} $(get_pstore_args)" \
    || echo "Error setting up Chrome OS pstore"

  # Arbitrary limit, as of today there's 750 open fds on a 12 core brya.
  # TODO(b/230441812): Investigate why we need all those file descriptors and
  # decide if we actually need them or can be reduced.
  ulimit -n 2048

  cbmem -a TS_CRHV_VMM_START

  /sbin/crosvm-direct --extended-status \
    run ${args} --params "$(get_cmdline)" /boot/vmlinuz
  rc="$?"

  case "${rc}" in
    0 | 32)
      # Normal exit: poweroff or reboot
      save_args=""
      ;;
    *)
      # Guest panic or crosvm crash
      save_args="--save-hypervisor-dmesg"
      ;;
  esac

  save_pstore "${save_args}" || echo "Error saving Chrome OS pstore"

  return "${rc}"
}

# Make this script sourceable for unit testing.
if [ "$(basename "$0")" = "crosvm-direct.sh" ]; then
  if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <CrOS guest memory in MiB>"
    exit 1
  fi

  CROS_GUEST_MEMORY=$1

  if [[ -f "/etc/manatee.conf" ]]; then
    source "/etc/manatee.conf"
  fi

  run
fi
