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

# The demo top hardcodes resetVector = 0x8000_0000, which is not mapped in the
# arty_a7_vex shell. Patch to 0x9000_0000 (DDR base) so the CPU fetches Zephyr
# directly. The CPU is held in reset from bitstream program-time via the
# cpu_reset_gpio DOUT_DEFAULT so the fcapz loader can push zephyr.bin to DDR
# before the CPU starts fetching — no bootrom trampoline required.
sed -i \
    's/IBusCachedPlugin_fetchPc_pcReg <= (32.b10000000000000000000000000000000);/IBusCachedPlugin_fetchPc_pcReg <= (32'"'"'b10010000000000000000000000000000);   \/\/ bard0: resetVector -> 0x9000_0000 (DDR direct)/' \
    "$repo_root/hardware/rtl/vexriscv/VexRiscvAxi4.v"

# Narrow the DataCache cacheable range to Zephyr code+data only. Demo default
# marks only 0xFxxxxxxx as I/O, so ALL of 0x00000000-0xEFFFFFFF gets cached —
# both peripherals (0x40xxxxxx) AND our uncached DMA memory region (0x9f000000).
# Cache only the Zephyr .text/.data range (0x90000000-0x97FFFFFF, matching mbv's
# C_DCACHE_BASEADDR/HIGHADDR); everything else is I/O = uncached. This is
# essential for DMA coherency: BD writes to 0x9f000000+ must reach DDR before
# the DMA fetches them, and without cbo.clean/inval that only works if the
# region is uncached.
sed -i \
    's|assign _zz_263_ = (_zz_109_\[31 : 28\] == (4.b1111));|assign _zz_263_ = (_zz_109_[31 : 27] != (5.b10010));   // bard0: data cached ONLY in 0x90000000-0x97FFFFFF (matches mbv D-cache range); DMA memory at 0x9F000000 stays uncached so BD writes reach DDR|' \
    "$repo_root/hardware/rtl/vexriscv/VexRiscvAxi4.v"

# The demo config sets mtvecAccess=CsrAccess.NONE which drops CSR writes to
# mtvec on the floor. Zephyr writes mtvec on entry to point at _isr_wrapper;
# with NONE the write raises an illegal-instruction trap and the CPU jumps to
# the hardcoded mtvecInit (0x20 → bootrom nops). Patch mtvec_base to a reg
# and add a CSR read+write case for address 0x305.
python3 - "$repo_root/hardware/rtl/vexriscv/VexRiscvAxi4.v" <<'PY'
import re, sys, io
p = sys.argv[1]
s = open(p, "r").read()

# 1) wire -> reg for mtvec_base, with power-on init at declaration so the
#    write always block is the sole driver (no async-reset multi-driver)
s = s.replace(
    "wire [29:0] CsrPlugin_mtvec_base;",
    "reg  [29:0] CsrPlugin_mtvec_base = 30'h00000008;   // bard0: made writable; power-on init = 0x20 via base<<2",
    1,
)
# 2) drop the constant assign
s = s.replace(
    "assign CsrPlugin_mtvec_base = (30'b000000000000000000000000001000);",
    "// bard0: CsrPlugin_mtvec_base is now a reg — driven by reset init and CSR write case",
    1,
)
# 3) add mtvec (0x305) READ case before the default in the read switch
old = ("      12'b001101000010 : begin\n"
       "        if(execute_CSR_READ_OPCODE)begin\n"
       "          execute_CsrPlugin_illegalAccess = 1'b0;\n"
       "        end\n"
       "        execute_CsrPlugin_readData[31 : 31] = CsrPlugin_mcause_interrupt;\n"
       "        execute_CsrPlugin_readData[3 : 0] = CsrPlugin_mcause_exceptionCode;\n"
       "      end\n"
       "      default : begin\n"
       "      end\n"
       "    endcase\n")
new = ("      12'b001101000010 : begin\n"
       "        if(execute_CSR_READ_OPCODE)begin\n"
       "          execute_CsrPlugin_illegalAccess = 1'b0;\n"
       "        end\n"
       "        execute_CsrPlugin_readData[31 : 31] = CsrPlugin_mcause_interrupt;\n"
       "        execute_CsrPlugin_readData[3 : 0] = CsrPlugin_mcause_exceptionCode;\n"
       "      end\n"
       "      12'b001100000101 : begin   // bard0: mtvec (0x305) — read/write\n"
       "        execute_CsrPlugin_illegalAccess = 1'b0;\n"
       "        execute_CsrPlugin_readData[31 : 2] = CsrPlugin_mtvec_base;\n"
       "        execute_CsrPlugin_readData[1 : 0]  = CsrPlugin_mtvec_mode;\n"
       "      end\n"
       "      12'b111100010100 : begin   // bard0: mhartid (0xf14) — read-only zero\n"
       "        if(execute_CSR_READ_OPCODE)begin\n"
       "          execute_CsrPlugin_illegalAccess = 1'b0;\n"
       "        end\n"
       "      end\n"
       "      12'b111100010001 : begin   // bard0: mvendorid (0xf11) — read-only zero\n"
       "        if(execute_CSR_READ_OPCODE)begin\n"
       "          execute_CsrPlugin_illegalAccess = 1'b0;\n"
       "        end\n"
       "      end\n"
       "      12'b111100010010 : begin   // bard0: marchid (0xf12) — read-only zero\n"
       "        if(execute_CSR_READ_OPCODE)begin\n"
       "          execute_CsrPlugin_illegalAccess = 1'b0;\n"
       "        end\n"
       "      end\n"
       "      12'b111100010011 : begin   // bard0: mimpid (0xf13) — read-only zero\n"
       "        if(execute_CSR_READ_OPCODE)begin\n"
       "          execute_CsrPlugin_illegalAccess = 1'b0;\n"
       "        end\n"
       "      end\n"
       "      12'b001100000001 : begin   // bard0: misa (0x301) — read-only zero\n"
       "        if(execute_CSR_READ_OPCODE)begin\n"
       "          execute_CsrPlugin_illegalAccess = 1'b0;\n"
       "        end\n"
       "      end\n"
       "      default : begin\n"
       "      end\n"
       "    endcase\n")
assert old in s, "mtvec read case pattern not found"
s = s.replace(old, new, 1)

# 4) add mtvec (0x305) WRITE case
old = ("      12'b001101000010 : begin\n"
       "      end\n"
       "      default : begin\n"
       "      end\n"
       "    endcase\n"
       "  end\n\n"
       "  always @ (posedge clk) begin\n"
       "    DebugPlugin_firstCycle <= 1'b0;\n")
new = ("      12'b001101000010 : begin\n"
       "      end\n"
       "      12'b001100000101 : begin   // bard0: mtvec (0x305) write\n"
       "        if(execute_CsrPlugin_writeEnable)begin\n"
       "          CsrPlugin_mtvec_base <= execute_CsrPlugin_writeData[31 : 2];\n"
       "        end\n"
       "      end\n"
       "      default : begin\n"
       "      end\n"
       "    endcase\n"
       "  end\n\n"
       "  always @ (posedge clk) begin\n"
       "    DebugPlugin_firstCycle <= 1'b0;\n")
assert old in s, "mtvec write case pattern not found"
s = s.replace(old, new, 1)

# 5) intentionally NO separate mtvec_base reset init in the async-reset block:
#    would multi-drive the reg. Init happens at declaration (step 1).

open(p, "w").write(s)
PY

echo "generated: $repo_root/hardware/rtl/vexriscv/VexRiscvAxi4.v"
