#!/bin/sh
# Copyright 2022 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

. "$(dirname $0)/init"

set -e

test_get_cros_guest_memory() {
  local meminfo="MemTotal:       16258968 kB
MemFree:        13847068 kB
MemAvailable:   13717936 kB
Buffers:               0 kB
Cached:          2285452 kB
SwapCached:            0 kB
Active:           809048 kB
Inactive:        1444200 kB
Active(anon):     809048 kB
Inactive(anon):  1444200 kB
Active(file):          0 kB
Inactive(file):        0 kB
Unevictable:       34860 kB
Mlocked:               0 kB
SwapTotal:             0 kB
SwapFree:              0 kB
Dirty:                 0 kB
Writeback:             0 kB
AnonPages:          2792 kB
Mapped:          2260892 kB
Shmem:           2250592 kB
KReclaimable:      12048 kB
Slab:              58012 kB
SReclaimable:      12048 kB
SUnreclaim:        45964 kB
KernelStack:        1600 kB
PageTables:         5528 kB
NFS_Unstable:          0 kB
Bounce:                0 kB
WritebackTmp:          0 kB
CommitLimit:     8129484 kB
Committed_AS:    2286392 kB
VmallocTotal:   34359738367 kB
VmallocUsed:       36756 kB
VmallocChunk:          0 kB
Percpu:             2848 kB
AnonHugePages:         0 kB
ShmemHugePages:        0 kB
ShmemPmdMapped:        0 kB
FileHugePages:         0 kB
FilePmdMapped:         0 kB
DirectMap4k:       18380 kB
DirectMap2M:     1929216 kB
DirectMap1G:    15728640 kB
"
  assertEquals "15365" "$(get_cros_guest_memory "$meminfo")"
}

. "${SYSROOT}/usr/bin/shunit2"
