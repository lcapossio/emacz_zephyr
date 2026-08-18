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
add_files -norecurse [file join $repo_root external/emacZero/rtl/version.vh]
set_property include_dirs [list \\
    [file join $repo_root external/emacZero/rtl] \\
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
# ibus_ic: CPU instruction fetch (bootrom + DDR). axi_interconnect handles
# read-only AXI masters (VexRiscv iBUS has no aw/w/b channels); smartconnect
# does not, so we can't swap it here.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ibus_ic
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 2] [get_bd_cells ibus_ic]
# ctrl_axi_ic: DBUS -> peripherals + DDR alias. (fcapz debug added in Step 2.)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ctrl_axi_ic
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 8] [get_bd_cells ctrl_axi_ic]
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

# -------- IRQ OR-reduction into externalInterrupt --------
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat
set_property -dict [list CONFIG.NUM_PORTS 4] [get_bd_cells irq_concat]
create_bd_cell -type ip -vlnv xilinx.com:ip:util_reduced_logic:2.0 irq_or
set_property -dict [list CONFIG.C_OPERATION or CONFIG.C_SIZE 4] [get_bd_cells irq_or]

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

# Interconnect clocks — axi_interconnect (uppercase ACLK + per-port variants)
foreach ic {{ibus_ic ctrl_axi_ic dma_axi_ic}} {{
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
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins axi_dma/s_axi_lite_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins axi_dma/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins axi_dma/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins axi_dma/m_axi_sg_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins emaczero/clk]
connect_bd_net [get_bd_pins clock_root/clk25]  [get_bd_pins emaczero/phy_ref_clk_25]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins s2mm_stream_stats/clk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins emac_irq_sync/clk]

# -------- resets --------
connect_bd_net [get_bd_ports BTN0] [get_bd_pins rst/ext_reset_in]
connect_bd_net [get_bd_ports BTN0] [get_bd_pins mig_rst/ext_reset_in]
connect_bd_net [get_bd_ports BTN0] [get_bd_pins eth_rst/ext_reset_in]
connect_bd_net [get_bd_pins const1/dout] [get_bd_pins rst/aux_reset_in]
connect_bd_net [get_bd_pins clock_root/locked] [get_bd_pins rst/dcm_locked]
connect_bd_net [get_bd_pins const1/dout] [get_bd_pins mig_rst/aux_reset_in]
connect_bd_net [get_bd_pins mig_ddr/mmcm_locked] [get_bd_pins mig_rst/dcm_locked]
connect_bd_net [get_bd_pins const1/dout] [get_bd_pins eth_rst/aux_reset_in]
connect_bd_net [get_bd_pins clock_root/locked] [get_bd_pins eth_rst/dcm_locked]
connect_bd_net [get_bd_ports BTN0] [get_bd_pins mig_ddr/sys_rst]

connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins cpu/aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins bootrom/aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins mtimer/aresetn]

foreach ic {{ibus_ic ctrl_axi_ic dma_axi_ic}} {{
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
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins axi_dma/axi_resetn]
connect_bd_net [get_bd_pins eth_rst/peripheral_aresetn] [get_bd_pins emaczero/rst_n]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins s2mm_stream_stats/rst_n]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins emac_irq_sync/rst_n]

# -------- AXI plumbing --------
# IBUS: CPU instruction fetch -> boot ROM @ 0x0 + DDR @ 0x9000_0000
connect_bd_intf_net [get_bd_intf_pins cpu/M_AXI_IBUS] [get_bd_intf_pins ibus_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ibus_ic/M00_AXI] [get_bd_intf_pins bootrom/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ibus_ic/M01_AXI] [get_bd_intf_pins ddr_axi_ic/S02_AXI]

# DBUS: CPU data -> ctrl_axi_ic (peripherals + DDR alias)
connect_bd_intf_net [get_bd_intf_pins cpu/M_AXI_DBUS] [get_bd_intf_pins ctrl_axi_ic/S00_AXI]

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
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M07_AXI] [get_bd_intf_pins ddr_axi_ic/S01_AXI]

# ddr_axi_ic sink -> MIG
connect_bd_intf_net [get_bd_intf_pins ddr_axi_ic/M00_AXI] [get_bd_intf_pins mig_ddr/S_AXI]

# emacZero AXIS <-> AXI DMA (single 100 MHz domain — no CDCs)
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXIS_MM2S] [get_bd_intf_pins emaczero/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins emaczero/M_AXIS] [get_bd_intf_pins s2mm_stream_stats/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins s2mm_stream_stats/M_AXIS] [get_bd_intf_pins axi_dma/S_AXIS_S2MM]

# BRAM ports
connect_bd_intf_net [get_bd_intf_pins bram_ctrl_cpu/BRAM_PORTA] [get_bd_intf_pins bram/BRAM_PORTA]

# -------- interrupts: OR-reduce -> externalInterrupt --------
connect_bd_net [get_bd_pins uart/interrupt]          [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins gpio/ip2intc_irpt]       [get_bd_pins irq_concat/In1]
connect_bd_net [get_bd_pins axi_dma/mm2s_introut]    [get_bd_pins irq_concat/In2]
connect_bd_net [get_bd_pins axi_dma/s2mm_introut]    [get_bd_pins irq_concat/In3]
connect_bd_net [get_bd_pins irq_concat/dout] [get_bd_pins irq_or/Op1]
connect_bd_net [get_bd_pins irq_or/Res] [get_bd_pins cpu/externalInterrupt]
# emaczero IRQ syncs but is currently unused as an external source; leave
# the input driven by const0 so timing is defined until Zephyr wires it up.
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins emac_irq_sync/din]

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
map_seg cpu/M_AXI_DBUS mig_ddr/memmap/memaddr   {DDR_BASE} {DDR_RANGE}

# DMA masters — DDR only
map_seg axi_dma/Data_MM2S mig_ddr/memmap/memaddr {DDR_BASE} {DDR_RANGE}
map_seg axi_dma/Data_SG   mig_ddr/memmap/memaddr {DDR_BASE} {DDR_RANGE}
map_seg axi_dma/Data_S2MM mig_ddr/memmap/memaddr {DDR_BASE} {DDR_RANGE}

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
