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
    return 1  # Ignore PCI-PCI Bridge.
    ;;
  esac

  case "${bdf}" in
    0000:00:1e.?)
# Uncomment to keep hypervisor access to serial console.
# FIME/keep hypervisor console to enable guest kernel bringup
      return 1
      ;;
  esac

  # Detach from current driver if any.
  local driver="${sysfs}/driver"
  if [[ -f "${driver}/unbind" ]]; then
    echo "${bdf}" > "${driver}/unbind"
  fi

  # Attach pci device to VFIO-PCI bus driver.
  echo "${vendor_id} ${device_id}" > /sys/bus/pci/drivers/vfio-pci/new_id
}

# Port I/O forwarding.
get_platform_pmio() {
  local pmio="${BOARD_PMIO:-128}"
  echo "--no-legacy --direct-pmio /dev/port@${pmio}"
}

# Interrupt forwarding argument helper.
get_platform_irqs() {
  local irq
  local args=""
  local irqs="${BOARD_IRQS:-edge:1}"
  for irq in ${irqs}; do
    args="${args} --direct-${irq%:*}-irq ${irq#*:}"
  done
  echo "${args}"
}

# Get guest kernel command line options.
get_cmdline() {
  local cmd="$(cat /proc/cmdline)"

  # PCI workaround
  cmd="pci=lastbus=255 pci=nocrs pci=realloc=off ${cmd}"

  # Disable strict IOMMU for guest kernel.
  cmd="${cmd/iommu=on\ /iommu=off\ }"

  # Uncomment to disable standard boot flow.
  # cmd="${cmd/init=*root=/root=} init=/bin/bash"

  # Uncomment for incorrect rootfs UUID workaround
  # cmd="${cmd/root=*\ rootwait/root=\/dev\/nvme0n1p3}"

  echo "${cmd}"
}

# Start primary guest VM.
run() {
  # Crosvm-direct command line.
  local args="-s /run/crosvm.sock --cid 3"

  # TODO(b/184871003): Enable user space IOAPIC implementation.
  # args="${args} --split-irqchip"

  # TODO(b/185150434): enable minijail sandboxing.
  args="${args} --disable-sandbox"

  # Use all available CPUs for primary VM.
  local nproc=$(nproc)
  local affinity=$(for n in $(seq 0 $((nproc - 1))); do echo -n "$n=$n:"; done)
  args="${args} --cpus ${nproc} --cpu-affinity ${affinity%?}"

  # Reserve 512MB of total system memory for hypervisor.
  local mem_total=$(grep MemTotal /proc/meminfo)
  local mem_kb=${mem_total//[^0-9]/}
  local mem_vm=$((mem_kb/1024 - 512))
  args="${args} --mem ${mem_vm}"

  # DMI: Use host SMBIOS info
  if [[ -d "/sys/firmware/dmi/tables" ]]; then
   args="${args} --dmi /sys/firmware/dmi/tables"
  fi

  # ACPI: Collect all valid host tables.
  for acpi in `find /sys/firmware/acpi/tables/ -type f`; do
    # Filter by name
    case "${acpi##*/}" in
    DMAR | FACS | APIC)
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

  # VFIO: Direct attach all usable PCI devices.
  for dev in `find /sys/bus/pci/devices -type l | sort`; do
    vfio_pci "${dev}"
    if [[ $? -eq 0 ]]; then
      args="${args} --vfio ${dev}"
    fi
  done

  # Platform IOs
  args="${args} $(get_platform_pmio)"

  # Platform IRQs
  args="${args} $(get_platform_irqs)"

  exec /sbin/crosvm-direct run ${args} --params "$(get_cmdline)" /boot/vmlinuz
}

if [[ -f "/etc/manatee.conf" ]]; then
  source "/etc/manatee.conf"
fi

run

