#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Build the Arty A7-100T VexRiscv-full + emacZero Vivado hardware shell.

Sibling to build_arty_a7_mbv.py. Differences from the MicroBlaze V shell:

  * CPU is SpinalHDL VexRiscv-full (external/VexRiscv), instantiated via the
    Verilog wrapper hardware/rtl/vexriscv/vexriscv_full_axi_wrapper.v. iBUS +
    dBUS are AXI4 masters; no LMB, no separate loader BRAM controller.
  * Single 100 MHz SoC domain (clock_root/clk100 from the MMCM). MIG's own
    ui_clk (81.25 MHz) stays isolated behind the ddr smartconnect, which
    also handles the clock crossing — no per-lane axi/axis clock converters.
  * Boot ROM: tiny 1 KiB RV32 ROM at 0x00000000 that jumps into DDR at
    0x90000000, where fcapz JTAG-AXI has already staged the Zephyr image.
  * RISC-V machine-timer (mtime/mtimecmp) replaces axi_timer; drives Vex's
    timerInterrupt directly. Zephyr's riscv,machine-timer driver covers it.
  * External interrupt: all peripheral IRQ lines OR-reduced into Vex's
    externalInterrupt bit (Step 2/3 will decide whether to add a PLIC).
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
from pathlib import Path


PART = "xc7a100tcsg324-1"
TOP = "arty_a7_100t_vex"
BUILD_DIR = Path("build") / "vivado" / TOP
DDR_BASE = "0x90000000"
DDR_RANGE = "0x10000000"
SOC_CLK_HZ = 100000000
BOOTROM_BASE = "0x00000000"
BOOTROM_RANGE = "0x00000400"      # 1 KiB
SCRATCH_BRAM_BASE = "0x80040000"
SCRATCH_BRAM_RANGE = "0x00008000"
SCRATCH_BRAM_WORDS = 8192
MTIMER_BASE = "0x02000000"        # CLINT-ish; DT reg = <0x02000000 8 0x02000008 8>
MTIMER_RANGE = "0x00010000"
CPU_RESET_GPIO_BASE = "0x40020000"  # bit0 asserts CPU-only reset (OR with sys reset)
CPU_RESET_GPIO_RANGE = "0x00010000"
CPU_LIVENESS_GPIO_BASE = "0x40030000"  # read-only: cpu_liveness_probe status
CPU_LIVENESS_GPIO_RANGE = "0x00010000"
CPU_LAST_IBUS_GPIO_BASE = "0x40040000"  # read-only: last IBUS AR address
CPU_LAST_IBUS_GPIO_RANGE = "0x00010000"
CPU_LAST_DBUS_GPIO_BASE = "0x40050000"  # read-only: last DBUS AW address
CPU_LAST_DBUS_GPIO_RANGE = "0x00010000"


EMACZERO_RTL = [
    "external/emacZero/rtl/crc32.v",
    "external/emacZero/rtl/async_fifo.v",
    "external/emacZero/rtl/sync_fifo.v",
    "external/emacZero/rtl/mii_if.v",
    "external/emacZero/rtl/mii_tx_saf.v",
    "external/emacZero/rtl/axil_arb2.v",
    "external/emacZero/rtl/eth_mac_rx.v",
    "external/emacZero/rtl/eth_mac_tx.v",
    "external/emacZero/rtl/eth_mac.v",
    "external/emacZero/rtl/mdio_master.v",
    "external/emacZero/rtl/eth_stats.v",
    "external/emacZero/rtl/eth_pause.v",
    "external/emacZero/rtl/axilite_regs.v",
    "external/emacZero/rtl/ddr_output.v",
    "external/emacZero/rtl/ddr_input.v",
    "external/emacZero/rtl/rgmii_if.v",
    "external/emacZero/rtl/gmii_cdc.v",
    "external/emacZero/rtl/net/tx_csum_off.v",
    "external/emacZero/rtl/eth_mac_sys.v",
    "hardware/rtl/axis_frame_error_drop.v",
    "hardware/rtl/axis_elastic_fifo.v",
    "hardware/rtl/axis_async_fifo.v",
    "hardware/rtl/axis_store_forward.v",
    "hardware/rtl/clock_root_100m.v",
    "hardware/rtl/emaczero_axi_mii_wrapper.v",
    "hardware/rtl/sync_level.v",
]

# fcapz sources omitted from this shell — Step 1c is CPU-boot-into-DDR only,
# not the JTAG-AXI loader path. Added back in Step 2 once the debug bridge is
# adapted to the VexRiscv AXI4 masters.

LOCAL_DEBUG_RTL = [
    "hardware/rtl/axis_rx_stream_stats.v",
    "hardware/rtl/vexriscv/VexRiscvAxi4.v",
    "hardware/rtl/vexriscv/vexriscv_full_axi_wrapper.v",
    "hardware/rtl/vexriscv/boot_bram_rv32.v",
    "hardware/rtl/vexriscv/riscv_mtimer.v",
    "hardware/rtl/vexriscv/cpu_liveness_probe.v",
]

# fcapz JTAG-AXI bridge on USER3 — the host loader (scripts/load_zephyr_bram.py)
# uses this path to write Zephyr images into DDR before releasing CPU reset.
# All plain Verilog-2001 (verified) — must be read that way so the Module
# Reference on fcapz_ejtagaxi_xilinx7 will pick a Verilog top file.
FCAPZ_RTL = [
    "fcapz/rtl/reset_sync.v",
    "fcapz/rtl/dpram.v",
    "fcapz/rtl/fcapz_async_fifo.v",
    "fcapz/rtl/trig_compare.v",
    "fcapz/rtl/jtag_reg_iface.v",
    "fcapz/rtl/jtag_pipe_iface.v",
    "fcapz/rtl/jtag_burst_read.v",
    "fcapz/rtl/fcapz_regbus_mux.v",
    "fcapz/rtl/fcapz_ejtagaxi.v",
    "fcapz/rtl/fcapz_ejtagaxi_xilinx7.v",
    "fcapz/rtl/jtag_tap/jtag_tap_xilinx7.v",
]


def rel_list(paths: list[str]) -> str:
    return " ".join(paths)


def make_tcl(args: argparse.Namespace) -> str:
    synth_impl = "1" if args.synth else "0"
    jobs = max(1, args.jobs)
    return f"""
set repo_root [file normalize [file join [pwd] .. .. ..]]
set part {PART}
set top {TOP}
set synth_impl {synth_impl}
set jobs {jobs}

create_project $top . -part $part -force
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]
set_property verilog_define XILINX_7SERIES [current_fileset]

set rtl_files [list {rel_list(EMACZERO_RTL + LOCAL_DEBUG_RTL)}]
foreach f $rtl_files {{
    read_verilog [file join $repo_root $f]
}}
set fcapz_rtl_files [list {rel_list(FCAPZ_RTL)}]
foreach f $fcapz_rtl_files {{
    read_verilog [file join $repo_root $f]
}}
add_files -norecurse [file join $repo_root external/emacZero/rtl/version.vh]
add_files -norecurse [file join $repo_root fcapz/rtl/fcapz_version.vh]
set_property include_dirs [list \\
    [file join $repo_root external/emacZero/rtl] \\
    [file join $repo_root fcapz/rtl] \\
] [current_fileset]
# Same physical pinout as the MBV shell — top-level port names match.
read_xdc [file join $repo_root hardware/xdc/arty_a7_100t_mbv.xdc]

create_bd_design $top

# -------- top-level ports (must match XDC) --------
create_bd_port -dir I -type clk -freq_hz 100000000 CLK100MHZ
create_bd_port -dir I -type rst BTN0
set_property -dict [list CONFIG.POLARITY ACTIVE_HIGH] [get_bd_ports BTN0]

create_bd_port -dir O UART_TXD
create_bd_port -dir O -from 3 -to 0 ETH_TXD
create_bd_port -dir O ETH_TX_EN
create_bd_port -dir I ETH_TX_CLK
create_bd_port -dir I -from 3 -to 0 ETH_RXD
create_bd_port -dir I ETH_RX_DV
create_bd_port -dir I ETH_RXERR
create_bd_port -dir I ETH_RX_CLK
create_bd_port -dir I ETH_CRS
create_bd_port -dir I ETH_COL
create_bd_port -dir O ETH_MDC
create_bd_port -dir IO ETH_MDIO
create_bd_port -dir O ETH_REF_CLK
create_bd_port -dir O ETH_RSTN

create_bd_port -dir O -from 13 -to 0 ddr3_addr
create_bd_port -dir O -from 2 -to 0 ddr3_ba
create_bd_port -dir O ddr3_cas_n
create_bd_port -dir O -from 0 -to 0 ddr3_ck_n
create_bd_port -dir O -from 0 -to 0 ddr3_ck_p
create_bd_port -dir O -from 0 -to 0 ddr3_cke
create_bd_port -dir O -from 0 -to 0 ddr3_cs_n
create_bd_port -dir O -from 1 -to 0 ddr3_dm
create_bd_port -dir IO -from 15 -to 0 ddr3_dq
create_bd_port -dir IO -from 1 -to 0 ddr3_dqs_n
create_bd_port -dir IO -from 1 -to 0 ddr3_dqs_p
create_bd_port -dir O -from 0 -to 0 ddr3_odt
create_bd_port -dir O ddr3_ras_n
create_bd_port -dir O ddr3_reset_n
create_bd_port -dir O ddr3_we_n

# -------- resets --------
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 mig_rst
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 eth_rst

# -------- CPU + boot ROM + machine timer --------
create_bd_cell -type module -reference vexriscv_full_axi_wrapper cpu
create_bd_cell -type module -reference boot_bram_rv32 bootrom
create_bd_cell -type module -reference riscv_mtimer mtimer

# -------- interconnects --------
# ibus_ic: CPU instruction fetch (bootrom + DDR). SmartConnect — the earlier
# axi_interconnect 2.1 refused to assert arready to the CPU (probe showed
# ibus_arvalid=1 forever, arready never), likely because the bootrom slave
# is full-R+W while the CPU master is read-only, and 2.1's crossbar hangs
# on that mode mismatch. SmartConnect auto-adapts R-only masters and
# R-only-effective slave ports without complaint.
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 ibus_ic
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 2 CONFIG.NUM_CLKS 1] [get_bd_cells ibus_ic]
# ctrl_axi_ic: DBUS + fcapz_axi -> peripherals + DDR alias. fcapz gets its
# own SI so the host loader can push Zephyr images into DDR while the CPU
# is held in reset.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ctrl_axi_ic
set_property -dict [list CONFIG.NUM_SI 2 CONFIG.NUM_MI 13] [get_bd_cells ctrl_axi_ic]
# dbus_r_slice: register slice on the R channel of CPU DBUS -> ctrl_axi_ic.
# Breaks a 12-level combinational path (xbar R-mux -> CPU d-cache rresp ->
# IBusCachedPlugin_injector -> I-cache tag BRAM ADDRARDADDR) that was
# failing setup by -0.571 ns on sys_clk. REG_R=1 fully registers only the
# R channel; AR/AW/W/B pass through (REG_*=0), so the memory-read latency
# penalty is exactly +1 cycle and writes / addresses are untouched.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_register_slice:2.1 dbus_r_slice
set_property -dict [list \\
    CONFIG.REG_AW {{0}} CONFIG.REG_AR {{0}} CONFIG.REG_W {{0}} \\
    CONFIG.REG_R  {{1}} CONFIG.REG_B  {{0}}] [get_bd_cells dbus_r_slice]
# dma_axi_ic: three DMA masters -> DDR.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 dma_axi_ic
set_property -dict [list CONFIG.NUM_SI 3 CONFIG.NUM_MI 1] [get_bd_cells dma_axi_ic]
# ddr_axi_ic: single sink into MIG. SmartConnect earns its keep here by
# also handling the SoC-clk (100 MHz) -> mig ui_clk (81.25 MHz) crossing.
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 ddr_axi_ic
set_property -dict [list CONFIG.NUM_SI 3 CONFIG.NUM_MI 1 CONFIG.NUM_CLKS 2] [get_bd_cells ddr_axi_ic]

# -------- scratch BRAM --------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 bram_ctrl_cpu
set_property -dict [list CONFIG.SINGLE_PORT_BRAM 1 CONFIG.DATA_WIDTH 32] [get_bd_cells bram_ctrl_cpu]
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 bram
set_property -dict [list CONFIG.Memory_Type True_Dual_Port_RAM CONFIG.Use_Byte_Write_Enable true CONFIG.Byte_Size 8 CONFIG.Write_Depth_A {SCRATCH_BRAM_WORDS} CONFIG.Enable_32bit_Address true] [get_bd_cells bram]

# -------- MIG DDR --------
create_bd_cell -type ip -vlnv xilinx.com:ip:mig_7series:4.2 mig_ddr
set_property -dict [list \\
    CONFIG.XML_INPUT_FILE [file join $repo_root hardware/mig/arty_a7_100t_mig.prj] \\
    CONFIG.RESET_BOARD_INTERFACE Custom \\
    CONFIG.MIG_DONT_TOUCH_PARAM Custom \\
] [get_bd_cells mig_ddr]

# -------- peripherals --------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 uart
set_property -dict [list CONFIG.C_BAUDRATE 115200 CONFIG.C_DATA_BITS 8] [get_bd_cells uart]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH 2 CONFIG.C_ALL_INPUTS 1 CONFIG.C_INTERRUPT_PRESENT 1] [get_bd_cells gpio]

# AXI INTC — numbered IRQ dispatch so Zephyr can wire IRQ_CONNECT() per line.
# Replaces the old irq_or OR-reduction; intc/interrupt drives cpu/externalInterrupt.
# C_KIND_OF_INTR bit-per-input: 1=EDGE, 0=LEVEL.
# Input-line assignment on this shell (see irq_concat wiring below):
#   In0=uart  In1=gpio  In2=mm2s_introut  In3=s2mm_introut  In4=emac_irq
# axi_dma's mm2s/s2mm_introut are LEVEL outputs (per PG021) — INTC line 2/3
# MUST be LEVEL or the DMA IRQ can go unlatched (rising edge missed while
# introut is held high across bursts). Only the GPIO push-button (In1) is
# genuinely edge, so mask = 0x02. The mbv shell also uses 0x0A, but only
# because its s2mm sits on line 7 (LEVEL); the mask value is per-line, not
# per-source, and cannot be blindly copied across different IRQ maps.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 intc
set_property -dict [list CONFIG.C_KIND_OF_INTR 0x00000002] [get_bd_cells intc]

# Host-writable CPU-only reset (bit 0 = assert CPU reset). fcapz writes to
# this GPIO to reset the VexRiscv without touching MIG/DDR contents, so the
# just-loaded Zephyr image survives across the reboot.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 cpu_reset_gpio
# C_DOUT_DEFAULT=1 -> CPU held in reset from bitstream program, so it can't
# race the host loader by fetching garbage from uninitialised DDR (which can
# hang the shared ddr_axi_ic before we get a chance to install Zephyr).
set_property -dict [list CONFIG.C_GPIO_WIDTH 1 CONFIG.C_ALL_INPUTS 0 CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_DOUT_DEFAULT 0x00000001] [get_bd_cells cpu_reset_gpio]

# Read-only status GPIO fed from cpu_liveness_probe: latched flags for each
# CPU-issued AXI channel handshake, plus a 16-bit ibus AR handshake count.
# Lets the host confirm whether the CPU is actually issuing fetches.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 cpu_liveness_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH 32 CONFIG.C_ALL_INPUTS 1 CONFIG.C_ALL_OUTPUTS 0] [get_bd_cells cpu_liveness_gpio]
# 32-bit input GPIOs for the last accepted IBUS fetch address and last DBUS
# store address — pinpoint where the CPU is fetching / storing when it stalls.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 cpu_last_ibus_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH 32 CONFIG.C_ALL_INPUTS 1 CONFIG.C_ALL_OUTPUTS 0] [get_bd_cells cpu_last_ibus_gpio]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 cpu_last_dbus_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH 32 CONFIG.C_ALL_INPUTS 1 CONFIG.C_ALL_OUTPUTS 0] [get_bd_cells cpu_last_dbus_gpio]
create_bd_cell -type module -reference cpu_liveness_probe cpu_liveness_probe
# cpu/aresetn (active-low) = peripheral_aresetn AND NOT(host_bit).
# Both inputs are active-low: both must be 1 for CPU to run.
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 host_reset_inv
set_property -dict [list CONFIG.C_SIZE 1 CONFIG.C_OPERATION not] [get_bd_cells host_reset_inv]
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 cpu_reset_and
set_property -dict [list CONFIG.C_SIZE 1 CONFIG.C_OPERATION and] [get_bd_cells cpu_reset_and]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma
set_property -dict [list \\
    CONFIG.c_include_sg 1 \\
    CONFIG.c_include_mm2s 1 \\
    CONFIG.c_include_s2mm 1 \\
    CONFIG.c_m_axi_mm2s_data_width 32 \\
    CONFIG.c_m_axi_s2mm_data_width 32 \\
    CONFIG.c_m_axis_mm2s_tdata_width 8 \\
    CONFIG.c_s_axis_s2mm_tdata_width 8 \\
    CONFIG.c_sg_include_stscntrl_strm 0 \\
    CONFIG.c_sg_length_width 16 \\
    CONFIG.c_addr_width 32 \\
] [get_bd_cells axi_dma]
create_bd_cell -type module -reference axis_rx_stream_stats s2mm_stream_stats
create_bd_cell -type module -reference clock_root_100m clock_root
create_bd_cell -type module -reference emaczero_axi_mii_wrapper emaczero
set_property -dict [list CONFIG.MII_DEBUG 0] [get_bd_cells emaczero]
create_bd_cell -type module -reference sync_level emac_irq_sync

# fcapz JTAG-AXI master on USER3. Its M_AXI goes into ctrl_axi_ic (via a
# register slice for timing), giving the host loader write access to every
# peripheral and to DDR (through the ctrl_axi_ic -> ddr_axi_ic M07_AXI path).
create_bd_cell -type module -reference fcapz_ejtagaxi_xilinx7 fcapz_axi
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_register_slice:2.1 fcapz_axi_slice

# -------- IRQ concat -> axi_intc -> externalInterrupt --------
# 5 lines: uart(0), gpio(1), mm2s(2), s2mm(3), emaczero(4). Order matches
# arty_a7_vex.overlay's interrupt cells.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat
set_property -dict [list CONFIG.NUM_PORTS 5] [get_bd_cells irq_concat]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const0
set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 0] [get_bd_cells const0]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const1
set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 1] [get_bd_cells const1]

# -------- clocking --------
# clk100 (from MMCM) is the SoC clock for CPU + all peripherals + emaczero.
# clk25 is the ETH PHY reference. mig_ddr/ui_clk (81.25 MHz) stays a private
# domain sunk into ddr_axi_ic — the smartconnect handles the crossing.
connect_bd_net [get_bd_ports CLK100MHZ] [get_bd_pins clock_root/clk_in]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins mig_ddr/sys_clk_i]
connect_bd_net [get_bd_pins mig_ddr/ui_addn_clk_0] [get_bd_pins mig_ddr/clk_ref_i]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins rst/slowest_sync_clk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk]    [get_bd_pins mig_rst/slowest_sync_clk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins eth_rst/slowest_sync_clk]

# CPU clock
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins cpu/aclk]

# Boot ROM / mtimer on the SoC clock
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins bootrom/aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins mtimer/aclk]

# ibus_ic is a SmartConnect (lowercase aclk); others are axi_interconnect (ACLK).
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins ibus_ic/aclk]
# Interconnect clocks — axi_interconnect (uppercase ACLK + per-port variants)
foreach ic {{ctrl_axi_ic dma_axi_ic}} {{
    connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins $ic/ACLK]
    foreach p [get_bd_pins $ic/*ACLK] {{
        if {{[llength [get_bd_nets -quiet -of_objects $p]] == 0}} {{
            connect_bd_net [get_bd_pins clock_root/clk100] $p
        }}
    }}
}}
# ddr_axi_ic (smartconnect): aclk = 100 MHz SIs, aclk1 = ui_clk MI to mig_ddr.
# SmartConnect auto-derives ASSOCIATED_BUSIF from the actual connectivity,
# so we do not (and cannot) set it manually — the property is read-only.
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins ddr_axi_ic/aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk]    [get_bd_pins ddr_axi_ic/aclk1]

# Peripherals — all on clk100
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins bram_ctrl_cpu/s_axi_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins uart/s_axi_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins gpio/s_axi_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins intc/s_axi_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins axi_dma/s_axi_lite_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins axi_dma/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins axi_dma/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins axi_dma/m_axi_sg_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins emaczero/clk]
connect_bd_net [get_bd_pins clock_root/clk25]  [get_bd_pins emaczero/phy_ref_clk_25]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins s2mm_stream_stats/clk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins emac_irq_sync/clk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins fcapz_axi/axi_clk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins fcapz_axi_slice/aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins dbus_r_slice/aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins cpu_reset_gpio/s_axi_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins cpu_liveness_gpio/s_axi_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins cpu_last_ibus_gpio/s_axi_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins cpu_last_dbus_gpio/s_axi_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins cpu_liveness_probe/aclk]

# -------- resets --------
connect_bd_net [get_bd_ports BTN0] [get_bd_pins rst/ext_reset_in]
connect_bd_net [get_bd_ports BTN0] [get_bd_pins mig_rst/ext_reset_in]
connect_bd_net [get_bd_ports BTN0] [get_bd_pins eth_rst/ext_reset_in]
connect_bd_net [get_bd_pins const1/dout] [get_bd_pins rst/aux_reset_in]
# Wait for MIG's init_calib_complete (not just MMCM lock) before releasing
# peripheral_aresetn. axi_dma's internal soft-reset uses its own M_AXI
# masters to drain in-flight transactions; if it comes out of hard reset
# while mig_ddr is still calibrating, an early m_axi probe hangs and
# DMACR.Reset (bit 1) never self-clears. mbv matches this pattern.
connect_bd_net [get_bd_pins mig_ddr/init_calib_complete] [get_bd_pins rst/dcm_locked]
connect_bd_net [get_bd_pins const1/dout] [get_bd_pins mig_rst/aux_reset_in]
connect_bd_net [get_bd_pins mig_ddr/mmcm_locked] [get_bd_pins mig_rst/dcm_locked]
connect_bd_net [get_bd_pins const1/dout] [get_bd_pins eth_rst/aux_reset_in]
connect_bd_net [get_bd_pins clock_root/locked] [get_bd_pins eth_rst/dcm_locked]
connect_bd_net [get_bd_ports BTN0] [get_bd_pins mig_ddr/sys_rst]

# CPU reset = peripheral_aresetn AND NOT(host_bit). Both active-low into AND.
connect_bd_net [get_bd_pins cpu_reset_gpio/gpio_io_o] [get_bd_pins host_reset_inv/Op1]
connect_bd_net [get_bd_pins rst/peripheral_aresetn]   [get_bd_pins cpu_reset_and/Op1]
connect_bd_net [get_bd_pins host_reset_inv/Res]       [get_bd_pins cpu_reset_and/Op2]
connect_bd_net [get_bd_pins cpu_reset_and/Res]        [get_bd_pins cpu/aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins cpu_reset_gpio/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins cpu_liveness_gpio/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins cpu_last_ibus_gpio/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins cpu_last_dbus_gpio/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins cpu_liveness_probe/aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins bootrom/aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins mtimer/aresetn]

connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins ibus_ic/aresetn]
foreach ic {{ctrl_axi_ic dma_axi_ic}} {{
    connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins $ic/ARESETN]
    foreach p [get_bd_pins $ic/*ARESETN] {{
        if {{[llength [get_bd_nets -quiet -of_objects $p]] == 0}} {{
            connect_bd_net [get_bd_pins rst/peripheral_aresetn] $p
        }}
    }}
}}
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins ddr_axi_ic/aresetn]
connect_bd_net [get_bd_pins mig_rst/peripheral_aresetn] [get_bd_pins mig_ddr/aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins bram_ctrl_cpu/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins uart/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins gpio/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins intc/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins axi_dma/axi_resetn]
connect_bd_net [get_bd_pins eth_rst/peripheral_aresetn] [get_bd_pins emaczero/rst_n]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins s2mm_stream_stats/rst_n]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins emac_irq_sync/rst_n]
# fcapz_axi uses active-HIGH reset; slice takes the usual aresetn.
connect_bd_net [get_bd_pins rst/peripheral_reset]   [get_bd_pins fcapz_axi/axi_rst]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins fcapz_axi_slice/aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins dbus_r_slice/aresetn]

# -------- AXI plumbing --------
# IBUS: CPU instruction fetch -> boot ROM @ 0x0 + DDR @ 0x9000_0000
connect_bd_intf_net [get_bd_intf_pins cpu/M_AXI_IBUS] [get_bd_intf_pins ibus_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ibus_ic/M00_AXI] [get_bd_intf_pins bootrom/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ibus_ic/M01_AXI] [get_bd_intf_pins ddr_axi_ic/S02_AXI]

# DBUS: CPU data -> R-slice -> ctrl_axi_ic (peripherals + DDR alias). The
# R-slice registers only the R channel; see dbus_r_slice creation above for
# the timing rationale (breaks a 12-level xbar-R-mux -> I-cache-tag path).
connect_bd_intf_net [get_bd_intf_pins cpu/M_AXI_DBUS]        [get_bd_intf_pins dbus_r_slice/S_AXI]
connect_bd_intf_net [get_bd_intf_pins dbus_r_slice/M_AXI]    [get_bd_intf_pins ctrl_axi_ic/S00_AXI]

# fcapz JTAG-AXI (host loader) -> slice -> ctrl_axi_ic S01_AXI
connect_bd_intf_net [get_bd_intf_pins fcapz_axi/M_AXI]      [get_bd_intf_pins fcapz_axi_slice/S_AXI]
connect_bd_intf_net [get_bd_intf_pins fcapz_axi_slice/M_AXI] [get_bd_intf_pins ctrl_axi_ic/S01_AXI]

# DMA masters -> DDR via dma_axi_ic
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_MM2S] [get_bd_intf_pins dma_axi_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_S2MM] [get_bd_intf_pins dma_axi_ic/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_SG]   [get_bd_intf_pins dma_axi_ic/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins dma_axi_ic/M00_AXI] [get_bd_intf_pins ddr_axi_ic/S00_AXI]

# ctrl_axi_ic -> peripherals (M00..M08) + DDR alias (M08 last)
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M00_AXI] [get_bd_intf_pins uart/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M01_AXI] [get_bd_intf_pins mtimer/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M02_AXI] [get_bd_intf_pins gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M03_AXI] [get_bd_intf_pins emaczero/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M04_AXI] [get_bd_intf_pins axi_dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M05_AXI] [get_bd_intf_pins bram_ctrl_cpu/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M06_AXI] [get_bd_intf_pins s2mm_stream_stats/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M07_AXI] [get_bd_intf_pins cpu_reset_gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M08_AXI] [get_bd_intf_pins ddr_axi_ic/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M09_AXI] [get_bd_intf_pins cpu_liveness_gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M10_AXI] [get_bd_intf_pins cpu_last_ibus_gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M11_AXI] [get_bd_intf_pins cpu_last_dbus_gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M12_AXI] [get_bd_intf_pins intc/s_axi]

# CPU liveness probe — tap the wrapper's dbg_* outputs (separate ports, not
# AXI interface pins, so BD nets on them cannot break interface wiring).
connect_bd_net [get_bd_pins cpu/dbg_ibus_arvalid] [get_bd_pins cpu_liveness_probe/ibus_arvalid]
connect_bd_net [get_bd_pins cpu/dbg_ibus_arready] [get_bd_pins cpu_liveness_probe/ibus_arready]
connect_bd_net [get_bd_pins cpu/dbg_ibus_rvalid]  [get_bd_pins cpu_liveness_probe/ibus_rvalid]
connect_bd_net [get_bd_pins cpu/dbg_dbus_arvalid] [get_bd_pins cpu_liveness_probe/dbus_arvalid]
connect_bd_net [get_bd_pins cpu/dbg_dbus_awvalid] [get_bd_pins cpu_liveness_probe/dbus_awvalid]
connect_bd_net [get_bd_pins cpu/dbg_dbus_wvalid]  [get_bd_pins cpu_liveness_probe/dbus_wvalid]
connect_bd_net [get_bd_pins cpu/dbg_dbus_bvalid]  [get_bd_pins cpu_liveness_probe/dbus_bvalid]
connect_bd_net [get_bd_pins cpu/dbg_reset_i]      [get_bd_pins cpu_liveness_probe/reset_i]
connect_bd_net [get_bd_pins cpu/dbg_ibus_araddr]  [get_bd_pins cpu_liveness_probe/ibus_araddr]
connect_bd_net [get_bd_pins cpu/dbg_dbus_awaddr]  [get_bd_pins cpu_liveness_probe/dbus_awaddr]
connect_bd_net [get_bd_pins cpu_liveness_probe/status] [get_bd_pins cpu_liveness_gpio/gpio_io_i]
connect_bd_net [get_bd_pins cpu_liveness_probe/last_ibus_araddr] [get_bd_pins cpu_last_ibus_gpio/gpio_io_i]
connect_bd_net [get_bd_pins cpu_liveness_probe/last_dbus_awaddr] [get_bd_pins cpu_last_dbus_gpio/gpio_io_i]

# ddr_axi_ic sink -> MIG
connect_bd_intf_net [get_bd_intf_pins ddr_axi_ic/M00_AXI] [get_bd_intf_pins mig_ddr/S_AXI]

# emacZero AXIS <-> AXI DMA (single 100 MHz domain — no CDCs)
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXIS_MM2S] [get_bd_intf_pins emaczero/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins emaczero/M_AXIS] [get_bd_intf_pins s2mm_stream_stats/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins s2mm_stream_stats/M_AXIS] [get_bd_intf_pins axi_dma/S_AXIS_S2MM]

# BRAM ports
connect_bd_intf_net [get_bd_intf_pins bram_ctrl_cpu/BRAM_PORTA] [get_bd_intf_pins bram/BRAM_PORTA]

# -------- interrupts: concat -> axi_intc -> externalInterrupt --------
# IRQ index order MUST match arty_a7_vex.overlay's `interrupts = <N ...>` cells.
connect_bd_net [get_bd_pins uart/interrupt]          [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins gpio/ip2intc_irpt]       [get_bd_pins irq_concat/In1]
connect_bd_net [get_bd_pins axi_dma/mm2s_introut]    [get_bd_pins irq_concat/In2]
connect_bd_net [get_bd_pins axi_dma/s2mm_introut]    [get_bd_pins irq_concat/In3]
# emaczero irq crosses from its 100 MHz sync into the (single) SoC clock via
# emac_irq_sync — kept for topology symmetry with the mbv shell even though
# both domains are 100 MHz here, so a two-FF resync stays in place.
connect_bd_net [get_bd_pins emaczero/irq]            [get_bd_pins emac_irq_sync/din]
connect_bd_net [get_bd_pins emac_irq_sync/dout]      [get_bd_pins irq_concat/In4]
connect_bd_net [get_bd_pins irq_concat/dout]         [get_bd_pins intc/intr]
connect_bd_net [get_bd_pins intc/irq]                [get_bd_pins cpu/externalInterrupt]

# machine-timer IRQ (level) -> Vex timerInterrupt
connect_bd_net [get_bd_pins mtimer/timer_irq] [get_bd_pins cpu/timerInterrupt]

# -------- ETH pins --------
connect_bd_net [get_bd_pins emaczero/eth_txd] [get_bd_ports ETH_TXD]
connect_bd_net [get_bd_pins emaczero/eth_tx_en] [get_bd_ports ETH_TX_EN]
connect_bd_net [get_bd_ports ETH_TX_CLK] [get_bd_pins emaczero/eth_tx_clk]
connect_bd_net [get_bd_ports ETH_RXD] [get_bd_pins emaczero/eth_rxd]
connect_bd_net [get_bd_ports ETH_RX_DV] [get_bd_pins emaczero/eth_rx_dv]
connect_bd_net [get_bd_ports ETH_RXERR] [get_bd_pins emaczero/eth_rxerr]
connect_bd_net [get_bd_ports ETH_RX_CLK] [get_bd_pins emaczero/eth_rx_clk]
connect_bd_net [get_bd_ports ETH_CRS] [get_bd_pins emaczero/eth_crs]
connect_bd_net [get_bd_ports ETH_COL] [get_bd_pins emaczero/eth_col]
connect_bd_net [get_bd_pins emaczero/eth_mdc] [get_bd_ports ETH_MDC]
connect_bd_net [get_bd_pins emaczero/eth_mdio] [get_bd_ports ETH_MDIO]
connect_bd_net [get_bd_pins emaczero/eth_ref_clk] [get_bd_ports ETH_REF_CLK]
connect_bd_net [get_bd_pins emaczero/eth_rstn] [get_bd_ports ETH_RSTN]
connect_bd_net [get_bd_pins uart/tx] [get_bd_ports UART_TXD]

# -------- DDR3 pins --------
connect_bd_net [get_bd_pins mig_ddr/ddr3_addr] [get_bd_ports ddr3_addr]
connect_bd_net [get_bd_pins mig_ddr/ddr3_ba] [get_bd_ports ddr3_ba]
connect_bd_net [get_bd_pins mig_ddr/ddr3_cas_n] [get_bd_ports ddr3_cas_n]
connect_bd_net [get_bd_pins mig_ddr/ddr3_ck_n] [get_bd_ports ddr3_ck_n]
connect_bd_net [get_bd_pins mig_ddr/ddr3_ck_p] [get_bd_ports ddr3_ck_p]
connect_bd_net [get_bd_pins mig_ddr/ddr3_cke] [get_bd_ports ddr3_cke]
connect_bd_net [get_bd_pins mig_ddr/ddr3_cs_n] [get_bd_ports ddr3_cs_n]
connect_bd_net [get_bd_pins mig_ddr/ddr3_dm] [get_bd_ports ddr3_dm]
connect_bd_net [get_bd_pins mig_ddr/ddr3_dq] [get_bd_ports ddr3_dq]
connect_bd_net [get_bd_pins mig_ddr/ddr3_dqs_n] [get_bd_ports ddr3_dqs_n]
connect_bd_net [get_bd_pins mig_ddr/ddr3_dqs_p] [get_bd_ports ddr3_dqs_p]
connect_bd_net [get_bd_pins mig_ddr/ddr3_odt] [get_bd_ports ddr3_odt]
connect_bd_net [get_bd_pins mig_ddr/ddr3_ras_n] [get_bd_ports ddr3_ras_n]
connect_bd_net [get_bd_pins mig_ddr/ddr3_reset_n] [get_bd_ports ddr3_reset_n]
connect_bd_net [get_bd_pins mig_ddr/ddr3_we_n] [get_bd_ports ddr3_we_n]

# -------- address map --------
proc map_seg {{space seg offset range}} {{
    set as [get_bd_addr_spaces -quiet $space]
    set ss [get_bd_addr_segs -quiet $seg]
    if {{[llength $as] != 1 || [llength $ss] != 1}} {{
        puts "WARNING: cannot map $seg into $space"
        return
    }}
    catch {{include_bd_addr_seg -target_address_space $as $ss}}
    assign_bd_address -target_address_space $as -offset $offset -range $range $ss
    catch {{include_bd_addr_seg -target_address_space $as $ss}}
}}

# IBUS: boot ROM (@0) + DDR mirror
map_seg cpu/M_AXI_IBUS bootrom/S_AXI/reg0     {BOOTROM_BASE} {BOOTROM_RANGE}
map_seg cpu/M_AXI_IBUS mig_ddr/memmap/memaddr {DDR_BASE} {DDR_RANGE}

# DBUS: peripheral view + DDR + scratch (bootrom is IBUS-only)
map_seg cpu/M_AXI_DBUS uart/S_AXI/Reg           0x40600000 0x00010000
map_seg cpu/M_AXI_DBUS mtimer/S_AXI/reg0        {MTIMER_BASE} {MTIMER_RANGE}
map_seg cpu/M_AXI_DBUS gpio/S_AXI/Reg           0x40010000 0x00010000
map_seg cpu/M_AXI_DBUS emaczero/S_AXI/reg0      0x44A00000 0x00001000
map_seg cpu/M_AXI_DBUS axi_dma/S_AXI_LITE/Reg   0x41E00000 0x00010000
map_seg cpu/M_AXI_DBUS bram_ctrl_cpu/S_AXI/Mem0 {SCRATCH_BRAM_BASE} {SCRATCH_BRAM_RANGE}
map_seg cpu/M_AXI_DBUS s2mm_stream_stats/S_AXI/reg0 0x41F00000 0x00010000
map_seg cpu/M_AXI_DBUS cpu_reset_gpio/S_AXI/Reg  {CPU_RESET_GPIO_BASE} {CPU_RESET_GPIO_RANGE}
map_seg cpu/M_AXI_DBUS cpu_liveness_gpio/S_AXI/Reg {CPU_LIVENESS_GPIO_BASE} {CPU_LIVENESS_GPIO_RANGE}
map_seg cpu/M_AXI_DBUS cpu_last_ibus_gpio/S_AXI/Reg {CPU_LAST_IBUS_GPIO_BASE} {CPU_LAST_IBUS_GPIO_RANGE}
map_seg cpu/M_AXI_DBUS cpu_last_dbus_gpio/S_AXI/Reg {CPU_LAST_DBUS_GPIO_BASE} {CPU_LAST_DBUS_GPIO_RANGE}
map_seg cpu/M_AXI_DBUS intc/S_AXI/Reg           0x41200000 0x00010000
map_seg cpu/M_AXI_DBUS mig_ddr/memmap/memaddr   {DDR_BASE} {DDR_RANGE}

# DMA masters — DDR only
map_seg axi_dma/Data_MM2S mig_ddr/memmap/memaddr {DDR_BASE} {DDR_RANGE}
map_seg axi_dma/Data_SG   mig_ddr/memmap/memaddr {DDR_BASE} {DDR_RANGE}
map_seg axi_dma/Data_S2MM mig_ddr/memmap/memaddr {DDR_BASE} {DDR_RANGE}

# fcapz loader — same view as DBUS: peripherals + DDR (peripherals are useful
# for host-side reg pokes; DDR is the loader target for zephyr.bin).
map_seg fcapz_axi/m_axi uart/S_AXI/Reg           0x40600000 0x00010000
map_seg fcapz_axi/m_axi mtimer/S_AXI/reg0        {MTIMER_BASE} {MTIMER_RANGE}
map_seg fcapz_axi/m_axi gpio/S_AXI/Reg           0x40010000 0x00010000
map_seg fcapz_axi/m_axi emaczero/S_AXI/reg0      0x44A00000 0x00001000
map_seg fcapz_axi/m_axi axi_dma/S_AXI_LITE/Reg   0x41E00000 0x00010000
map_seg fcapz_axi/m_axi bram_ctrl_cpu/S_AXI/Mem0 {SCRATCH_BRAM_BASE} {SCRATCH_BRAM_RANGE}
map_seg fcapz_axi/m_axi s2mm_stream_stats/S_AXI/reg0 0x41F00000 0x00010000
map_seg fcapz_axi/m_axi cpu_reset_gpio/S_AXI/Reg  {CPU_RESET_GPIO_BASE} {CPU_RESET_GPIO_RANGE}
map_seg fcapz_axi/m_axi cpu_liveness_gpio/S_AXI/Reg {CPU_LIVENESS_GPIO_BASE} {CPU_LIVENESS_GPIO_RANGE}
map_seg fcapz_axi/m_axi cpu_last_ibus_gpio/S_AXI/Reg {CPU_LAST_IBUS_GPIO_BASE} {CPU_LAST_IBUS_GPIO_RANGE}
map_seg fcapz_axi/m_axi cpu_last_dbus_gpio/S_AXI/Reg {CPU_LAST_DBUS_GPIO_BASE} {CPU_LAST_DBUS_GPIO_RANGE}
map_seg fcapz_axi/m_axi intc/S_AXI/Reg           0x41200000 0x00010000
map_seg fcapz_axi/m_axi mig_ddr/memmap/memaddr   {DDR_BASE} {DDR_RANGE}

validate_bd_design
save_bd_design
make_wrapper -files [get_files [file join [get_property DIRECTORY [current_project]] ${{top}}.srcs/sources_1/bd/${{top}}/${{top}}.bd]] -top
set bd_file [get_files [file join [get_property DIRECTORY [current_project]] ${{top}}.srcs/sources_1/bd/${{top}}/${{top}}.bd]]
set_property synth_checkpoint_mode None $bd_file
generate_target all $bd_file
add_files -norecurse [file join [get_property DIRECTORY [current_project]] ${{top}}.gen/sources_1/bd/${{top}}/hdl/${{top}}_wrapper.v]
set_property top ${{top}}_wrapper [current_fileset]
update_compile_order -fileset sources_1

if {{$synth_impl}} {{
    file mkdir reports
    synth_design -top ${{top}}_wrapper -part $part
    write_checkpoint -force ${{top}}_wrapper_synth.dcp
    report_utilization -file reports/utilization_synth.rpt
    opt_design
    place_design
    phys_opt_design
    route_design
    write_checkpoint -force ${{top}}_wrapper_routed.dcp
    report_utilization -file reports/utilization_route.rpt
    report_timing_summary -file reports/timing.rpt
    write_bitstream -force ${{top}}_wrapper.bit
    if {{[catch {{write_hw_platform -fixed -force -file ${{top}}.xsa}} hw_err]}} {{
        puts "WARNING: write_hw_platform failed after bitstream generation: $hw_err"
    }}
}}
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--synth", action="store_true", help="run synthesis/implementation/bitstream")
    parser.add_argument("--jobs", type=int, default=2, help="Vivado implementation jobs")
    args = parser.parse_args()

    vivado = shutil.which("vivado")
    if vivado is None:
        raise SystemExit("ERROR: vivado was not found in PATH")

    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    (BUILD_DIR / "reports").mkdir(exist_ok=True)
    tcl = BUILD_DIR / "build.tcl"
    tcl.write_text(make_tcl(args), encoding="utf-8")

    cmd = [vivado, "-mode", "batch", "-source", str(tcl.name)]
    env = os.environ.copy()
    env["XILINX_TCLAPP_REPO"] = str(
        (Path("no_commit") / "force_vivado_install_tclstore_missing").resolve()
    )
    rc = subprocess.call(cmd, cwd=BUILD_DIR, env=env)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
