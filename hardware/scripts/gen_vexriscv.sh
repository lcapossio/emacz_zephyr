#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
#
# Regenerate the VexRiscv-full AXI4 Verilog from the pinned submodule.
# Requires SBT/JDK on PATH (install via coursier or the distro package).
# Output goes to hardware/rtl/vexriscv/VexRiscv.v.

set -euo pipefail

repo_root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$repo_root/external/VexRiscv"
# sbt 0.13.16 uses the deprecated SecurityManager. JDK 17+ blocks it by
# default; the -Djava.security.manager=allow opt-in keeps it working.
export SBT_OPTS="${SBT_OPTS:-} -Djava.security.manager=allow"
sbt "runMain vexriscv.demo.VexRiscvAxi4WithIntegratedJtag"
mkdir -p "$repo_root/hardware/rtl/vexriscv"
cp VexRiscvAxi4.v "$repo_root/hardware/rtl/vexriscv/VexRiscvAxi4.v"
echo "generated: $repo_root/hardware/rtl/vexriscv/VexRiscvAxi4.v"
