#!/bin/sh
# Copyright 2022 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

. "$(dirname $0)/crosvm-direct.sh"

set -e

MOCK_CBMEM_REGIONS=
CBMEM_EXIT_CODE=0

join_lines() {
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@"
  fi
}

expected_mapping_args() {
  # The mapping for the first page is always expected to be present.
  echo "--file-backed-mapping addr=0x0,size=0x1000,path=/dev/mem"
  join_lines "$@" | awk '{ print "--file-backed-mapping " $0 }'
}

cbmem() {
  echo "${MOCK_CBMEM_REGIONS}"
  return "${CBMEM_EXIT_CODE}"
}

mock_cbmem() {
  MOCK_CBMEM_REGIONS=$(join_lines "$@")
  CBMEM_EXIT_CODE=0
}

test_cbmem_mappings_error() {
  CBMEM_EXIT_CODE=1
  assertEquals "" "$(get_cbmem_mappings)"
}

test_cbmem_mappings_empty() {
  mock_cbmem ""
  assertEquals "$(expected_mapping_args)" "$(get_cbmem_mappings)"
}

test_cbmem_mappings_coalesce() {
  mock_cbmem \
    "CBMEM table of contents:" \
    "    NAME          ID           START      LENGTH" \
    " 0. ZERO        00000000  00001000   00001000" \
    " 1. ONE         11111111  00002000   00001000"
  assertEquals "$(expected_mapping_args \
      "addr=0x1000,size=0x2000,offset=0x1000,path=/dev/mem" \
    )" "$(get_cbmem_mappings)"
}

test_cbmem_mappings_overlap() {
  mock_cbmem \
    "CBMEM table of contents:" \
    "    NAME          ID           START      LENGTH" \
    " 0. ZERO        00000000  00001000   00002000" \
    " 1. ONE         11111111  00002000   00001000"
  assertEquals "$(expected_mapping_args \
      "addr=0x1000,size=0x2000,offset=0x1000,path=/dev/mem" \
    )" "$(get_cbmem_mappings)"
}

test_cbmem_mappings_ramoops() {
  mock_cbmem \
    "CBMEM table of contents:" \
    "    NAME          ID           START      LENGTH" \
    " 0. ZERO        00000000  00001000   00001000" \
    " 1. RAMOOPS     05430095  00002000   00001000" \
    " 2. TWO         22222222  00003000   00001000"
  assertEquals "$(expected_mapping_args \
      "addr=0x1000,size=0x1000,offset=0x1000,path=/dev/mem" \
      "addr=0x2000,size=0x1000,offset=0x2000,path=/dev/mem,rw" \
      "addr=0x3000,size=0x1000,offset=0x3000,path=/dev/mem" \
    )" "$(get_cbmem_mappings)"
}

test_cbmem_mappings_unaligned() {
  mock_cbmem \
    "CBMEM table of contents:" \
    "    NAME          ID           START      LENGTH" \
    " 0. ZERO        00000000  00001000   00001000" \
    " 1. ONE         11111111  00003100   000000ff" \
    " 2. TWO         22222222  00003af0   00000f00"
  assertEquals "$(expected_mapping_args \
      "addr=0x1000,size=0x1000,offset=0x1000,path=/dev/mem" \
      "addr=0x3000,size=0x2000,offset=0x3000,path=/dev/mem" \
    )" "$(get_cbmem_mappings)"
}

test_cbmem_mappings_long_name() {
  mock_cbmem \
    "CBMEM table of contents:" \
    "    NAME          ID           START      LENGTH" \
    " 0. MUCH LONGER THAN OTHER NAMES 00000000  00001000   00001000"
  assertEquals "$(expected_mapping_args \
      "addr=0x1000,size=0x1000,offset=0x1000,path=/dev/mem"
    )" "$(get_cbmem_mappings)"
}

test_cbmem_mappings_actual() {
  # Below is actual cbmem output from a volteer2.
  mock_cbmem \
    "CBMEM table of contents:" \
    "    NAME          ID           START      LENGTH" \
    " 0. FSP MEMORY  46535052  76c4e000   003b0000" \
    " 1. RO MCACHE   524d5346  76c4d000   00000fdc" \
    " 2. CONSOLE     434f4e53  76c2d000   00020000" \
    " 3. FMAP        464d4150  76c2c000   00000578" \
    " 4. TIME STAMP  54494d45  76c2b000   00000910" \
    " 5. VBOOT WORK  78007343  76c17000   00014000" \
    " 6. ROMSTG STCK 90357ac4  76c16000   00001000" \
    " 7. AFTER CAR   c4787a93  76c0b000   0000b000" \
    " 8. RAMSTAGE    9a357a9e  76b92000   00079000" \
    " 9. REFCODE     04efc0de  76b3d000   00055000" \
    "10. SMM BACKUP  07e9acee  76b2d000   00010000" \
    "11.             4f444749  76b2b000   00002000" \
    "12. EXT VBT     69866684  76b28000   0000219f" \
    "13. COREBOOT    43425442  76b20000   00008000" \
    "14. ACPI        41435049  76afc000   00024000" \
    "15. ACPI GNVS   474e5653  76afb000   00001000" \
    "16. RAMOOPS     05430095  769fb000   00100000" \
    "17. TPM2 TCGLOG 54504d32  769eb000   00010000" \
    "18. SMBIOS      534d4254  769ea000   00000800" \
    "19. FSP RUNTIME 52505346  76ffebe0   00000004" \
    "20. VPD         56504420  76ffeb60   0000006c" \
    "21. POWER STATE 50535454  76ffeb00   00000044" \
    "22. ROMSTAGE    47545352  76ffeae0   00000004" \
    "23. MEM INFO    494d454d  76ffe900   000001e0"
  assertEquals "$(expected_mapping_args \
      "addr=0x769ea000,size=0x11000,offset=0x769ea000,path=/dev/mem" \
      "addr=0x769fb000,size=0x100000,offset=0x769fb000,path=/dev/mem,rw" \
      "addr=0x76afb000,size=0x504000,offset=0x76afb000,path=/dev/mem" \
    )" "$(get_cbmem_mappings)"
}

MOCK_PROC_IOMEM=

expected_hostbridge_regions() {
  local IFS=","
  echo "--mmio-address-range $(echo "$*")"
}

mock_proc_iomem() {
  MOCK_PROC_IOMEM=$(join_lines "$@")
}

test_get_hostbridge_regions_single() {
  mock_proc_iomem "00000000-000fffff : PCI Bus 0000:00"

  assertEquals "$(expected_hostbridge_regions \
      "0x00000000-0x000fffff"
    )" "$(get_host_bridge_regions "${MOCK_PROC_IOMEM}")"
}

test_get_hostbridge_regions_skip_regions() {
  mock_proc_iomem "00000000-000fffff : PCI Bus 0000:01" \
    "  000a0000-000bffff : PCI Bus 0000:00"

  assertEquals "$(expected_hostbridge_regions)" \
    "$(get_host_bridge_regions "${MOCK_PROC_IOMEM}")"
}

test_get_hostbridge_regions_actual() {
  # /proc/iomem output from a delbin, with some lines
  # trimmed for brevity.
  mock_proc_iomem "000a0000-000fffff : Reserved" \
    "  000a0000-000bffff : PCI Bus 0000:00" \
    "7fc00000-dfffffff : PCI Bus 0000:00" \
    "  7fc00000-7fcfffff : PCI Bus 0000:01" \
    "  7fd00000-7fdfffff : PCI Bus 0000:02" \
    "f8000000-f9ffffff : Reserved" \
    "fc800000-fe7fffff : PCI Bus 0000:00" \
    "  fd690000-fd69ffff : INT34C5:00" \
    "fed00000-fed003ff : HPET 0" \
    "  fed00000-fed003ff : pnp 00:00" \
    "fed40000-fed47fff : PCI Bus 0000:00" \
    "280400000-7fffffffff : PCI Bus 0000:00" \
    "  280400000-2805fffff : PCI Bus 0000:01" \
    "  280600000-280600fff : 0000:00:19.0" \
    "    280600000-2806001ff : lpss_dev"

  assertEquals "$(expected_hostbridge_regions \
      "0x7fc00000-0xdfffffff" "0xfc800000-0xfe7fffff" \
      "0xfed40000-0xfed47fff" "0x280400000-0x7fffffffff"
    )" "$(get_host_bridge_regions "${MOCK_PROC_IOMEM}")"
}

test_get_platform_msrs() {
  BOARD_MSR_READ_PASS="0x01
0x02
"
  BOARD_MSR_READ_PASS_FILTER="0x03
0x04
"
  assertEquals "--userspace-msr 0x01,type=r,action=pass
--userspace-msr 0x02,type=r,action=pass
--userspace-msr 0x03,type=r,action=pass,filter=yes
--userspace-msr 0x04,type=r,action=pass,filter=yes" \
  "$(get_platform_msrs)"
}

test_get_platform_gpes() {
  BOARD_GPES="1
2"
  TBT_PCIE_HP_GPE=97
  assertEquals "--direct-gpe 1
--direct-gpe 2
--direct-gpe 97" \
  "$(get_platform_gpes)"
}

test_get_platform_pmio() {
  BOARD_PMIO="1,2,3"
  BOARD_MMIO="0xfe000000-0xfe00ffff"
  assertEquals "--no-i8042
--no-rtc
--direct-pmio /dev/port@1,2,3
--direct-mmio /dev/mem@0xfe000000-0xfe00ffff" \
  "$(get_platform_pmio)"
}

test_get_vvu_proxy_devices() {
  assertEquals \
    "--vvu-proxy /run/crosvm-vvu01.sock,\
uuid=00000000-0000-4000-8000-000000000001
--vvu-proxy /run/crosvm-vvu02.sock,\
uuid=00000000-0000-4000-8000-000000000002" \
  "$(get_vvu_proxy_devices 2)"
}

expected_pcie_ecam() {
  echo "--pcie-ecam 0xe0000000,0x10000000"
}

test_get_pcie_ecam_single() {
  mock_proc_iomem "e0000000-efffffff : PCI MMCONFIG 0000 [bus 00-ff]"

  assertEquals "$(expected_pcie_ecam)" "$(get_pcie_ecam "${MOCK_PROC_IOMEM}")"
}

test_get_pcie_ecam_single_prefix_sapce() {
  mock_proc_iomem "  e0000000-efffffff : PCI MMCONFIG 0000 [bus 00-ff]"

  assertEquals "$(expected_pcie_ecam)" "$(get_pcie_ecam "${MOCK_PROC_IOMEM}")"
}

test_get_pcie_ecam_double() {
  mock_proc_iomem "e0000000-efffffff : PCI MMCONFIG 0000 [bus 00-ff]" \
    "d0000000-dfffffff : PCI MMCONFIG 0000 [bus 00-ff]"

  assertEquals "$(expected_pcie_ecam)" "$(get_pcie_ecam "${MOCK_PROC_IOMEM}")"
}

test_get_pcie_ecam_skip_regions() {
  mock_proc_iomem "70800000-dfffffff : PCI Bus 0000:00" \
    "  70800000-dfffffff : PCI Bus 0000:00" \

  assertEquals "" \
    "$(get_pcie_ecam "${MOCK_PROC_IOMEM}")"
}

test_get_pcie_ecam_actual() {
  # /proc/iomem output from an ubuntu, with some lines
  # trimmed for brevity.
  mock_proc_iomem "00000000-000fffff : PCI Bus 0000:01" \
    "  000a0000-000bffff : PCI Bus 0000:00" \
    "e0000000-efffffff : PCI MMCONFIG 0000 [bus 00-ff]" \
    "  e0000000-efffffff : Reserved" \
    "    e0000000-efffffff : pnp 00:04" \
    "fd000000-fd68ffff : pnp 00:05"

  assertEquals "$(expected_pcie_ecam)" "$(get_pcie_ecam "${MOCK_PROC_IOMEM}")"
}

. "${SYSROOT}/usr/bin/shunit2"
