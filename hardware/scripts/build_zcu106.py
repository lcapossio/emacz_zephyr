#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Build an AMD ZCU106 + emacZero Vivado hardware shell.

Two variants share one PL Ethernet subsystem: emacZero in GMII mode behind
the AMD 1G/2.5G Ethernet PCS/PMA core (1000BASE-X on SFP cage 0, GTH X0Y10,
156.25 MHz USER_MGT_SI570 reference clock, as in emacZero's fpga/zcu106
demo), an AXI DMA in scatter-gather mode, the RX stream counters, a PCS
status GPIO and an fcapz JTAG-AXI bridge on USER4.

  vex  VexRiscv-full in the PL, the Arty A7 Vex shell's CPU complex and
       address map. Memory is UltraRAM: 512 KiB at 0x9000_0000 inside the
       CPU's D-cache aperture for Zephyr, and 512 KiB at 0x9FF8_0000 outside
       it for DMA descriptors, frame buffers and the host page, which stays
       at 0x9FFF_E000 as on the Arty. No PS configuration is needed.
  r5   The PS: Zephyr on Cortex-R5 #0 reaches the PL over M_AXI_HPM0_LPD at
       0x8000_0000 and the DMA reaches PS DDR over S_AXI_HP0_FPD. The PL
       interrupts go to the GIC on pl_ps_irq0. Its console is PS UART0.
       The build also makes a Zynq MP FSBL for R5 #0 from the XSA (xsct,
       from Vitis): the loader runs it before Zephyr to set up the PS.

The SoC side runs at 150 MHz from the 300 MHz USER_SI570 clock: emacZero
in GMII mode needs at least 125 MHz there (one byte per clock at 1 Gb/s).
The MAC's own CDC crosses to the 125 MHz transceiver userclk2.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path

from emaczero_rtl import emaczero_rtl


REPO_ROOT = Path(__file__).resolve().parents[2]
PART = "xczu7ev-ffvc1156-2-e"
SOC_CLK_HZ = 150_000_000

# PL Ethernet subsystem addresses, relative to the CPU's PL window. The Vex
# shell keeps the Arty addresses; the R5 shell moves them into the
# M_AXI_HPM0_LPD aperture (see R5_PL_BASE).
EMACZERO_OFFSET = 0x04A00000
AXI_DMA_OFFSET = 0x01E00000
STREAM_STATS_OFFSET = 0x01F00000
PCS_GPIO_OFFSET = 0x00010000

# Vex address map: the Arty A7 Vex shell's, with UltraRAM for the MIG
VEX_PERIPH_BASE = 0x40000000
VEX_BOOTROM = (0x00000000, 0x400)
VEX_MTIMER = (0x02000000, 0x10000)
VEX_UART = (0x40600000, 0x10000)
VEX_INTC = (0x41200000, 0x10000)
VEX_CPU_RESET_GPIO = (0x40020000, 0x10000)
VEX_CPU_LIVENESS_GPIO = (0x40030000, 0x10000)
VEX_CPU_LAST_IBUS_GPIO = (0x40040000, 0x10000)
VEX_CPU_LAST_DBUS_GPIO = (0x40050000, 0x10000)
VEX_SCRATCH_BRAM = (0x80040000, 0x8000)
VEX_RAM_MAIN = (0x90000000, 0x80000)   # cached by the Vex D-cache
VEX_RAM_DMA = (0x9FF80000, 0x80000)    # outside the D-cache aperture

# R5 address map. M_AXI_HPM0_LPD's aperture is 0x8000_0000-0x9FFF_FFFF
# (512 MiB); the Ethernet blocks sit at its base + offset. S_AXI_HP0_FPD
# reaches the low 2 GiB of PS DDR.
R5_PL_BASE = 0x80000000
R5_DDR = (0x00000000, 0x80000000)
R5_BOARD_PART = "xilinx.com:zcu106:part0:2.6"

URAM_READ_LATENCY = 3

COMMON_RTL = emaczero_rtl(REPO_ROOT) + [
    "hardware/rtl/axis_frame_error_drop.v",
    "hardware/rtl/axis_elastic_fifo.v",
    "hardware/rtl/axis_store_forward.v",
    "hardware/rtl/emaczero_axi_gmii_wrapper.v",
    "hardware/rtl/sfp_pcs_ctrl.v",
    "hardware/rtl/axis_rx_stream_stats.v",
]

VEX_RTL = [
    "hardware/rtl/uram_bram_port.v",
    "hardware/rtl/vexriscv/VexRiscvAxi4.v",
    "hardware/rtl/vexriscv/vexriscv_full_axi_wrapper.v",
    "hardware/rtl/vexriscv/boot_bram_rv32.v",
    "hardware/rtl/vexriscv/riscv_mtimer.v",
    "hardware/rtl/vexriscv/cpu_liveness_probe.v",
]

# fcapz JTAG-AXI bridge (USER4); plain Verilog-2001, read as such so the
# module reference picks a Verilog top file.
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
    "fcapz/rtl/fcapz_ejtagaxi_xilinxus.v",
    "fcapz/rtl/jtag_tap/jtag_tap_xilinx7.v",
]


def hx(value: int) -> str:
    return f"0x{value:08X}"


def project_tcl(top: str, rtl: list[str], synth: bool, board_part: str | None = None) -> str:
    board = f"set_property board_part {board_part} [current_project]" if board_part else ""
    return f"""
set repo_root [file normalize [file join [pwd] .. .. ..]]
set part {PART}
set top {top}
set synth_impl {1 if synth else 0}
# PROJECTS.md: at most 4 build jobs
set_param general.maxThreads 4

create_project $top . -part $part -force
{board}
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

foreach f [list {" ".join(rtl + FCAPZ_RTL)}] {{
    read_verilog [file join $repo_root $f]
}}
add_files -norecurse [file join $repo_root external/emacZero/rtl/version.vh]
add_files -norecurse [file join $repo_root fcapz/rtl/fcapz_version.vh]
set_property include_dirs [list \\
    [file join $repo_root external/emacZero/rtl] \\
    [file join $repo_root fcapz/rtl] \\
] [current_fileset]
# emacZero's DDR I/O cells (the GMII TX clock forwarder) need a vendor primitive;
# XILINX_XPM puts the local FIFOs and frame store on AMD's XPM macros
set_property verilog_define {{XILINX_ULTRASCALE_PLUS XILINX_XPM}} [current_fileset]
read_xdc [file join $repo_root hardware/xdc/zcu106.xdc]

create_bd_design $top

proc map_seg {{space seg offset range}} {{
    set as [get_bd_addr_spaces -quiet $space]
    set ss [get_bd_addr_segs -quiet $seg]
    if {{[llength $as] != 1 || [llength $ss] != 1}} {{
        error "cannot map $seg into $space"
    }}
    assign_bd_address -target_address_space $as -offset $offset -range $range $ss
}}
"""


def eth_tcl() -> str:
    """Board clocking and the PL Ethernet subsystem, shared by both variants.

    Leaves these nets for the variant to use: clk_wiz/clk_soc (150 MHz),
    rst/peripheral_aresetn and rst/interconnect_aresetn on it, the DMA
    masters axi_dma/M_AXI_{MM2S,S2MM,SG}, the AXI-Lite slaves emaczero,
    axi_dma, s2mm_stream_stats and pcs_gpio, fcapz_axi_slice/M_AXI, and the
    interrupt outputs.
    """
    return f"""
# -------- board ports --------
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 USER_SI570_SYSCLK
set_property CONFIG.FREQ_HZ 300000000 [get_bd_intf_ports USER_SI570_SYSCLK]
create_bd_port -dir I -type rst CPU_RESET
set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports CPU_RESET]
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 SFP_REFCLK
set_property CONFIG.FREQ_HZ 156250000 [get_bd_intf_ports SFP_REFCLK]
create_bd_port -dir O SFP0_TX_P
create_bd_port -dir O SFP0_TX_N
create_bd_port -dir I SFP0_RX_P
create_bd_port -dir I SFP0_RX_N
create_bd_port -dir O SFP0_TX_DISABLE_B
create_bd_port -dir I DIP_AN_DISABLE
create_bd_port -dir O -from 3 -to 0 LED

# -------- clocks and resets --------
# clk_soc: CPU or PS-PL ports, AXI fabric, DMA and the MAC's system clock.
# clk_pcs: the PCS/PMA independent (DRP / reset) clock, 50 MHz as in
# emacZero's demo, which also runs sfp_pcs_ctrl's watchdog.
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz
set_property -dict [list \\
    CONFIG.PRIM_SOURCE Differential_clock_capable_pin \\
    CONFIG.PRIM_IN_FREQ 300.000 \\
    CONFIG.CLK_OUT1_PORT clk_soc \\
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {SOC_CLK_HZ / 1e6:.3f} \\
    CONFIG.CLKOUT2_USED true \\
    CONFIG.CLK_OUT2_PORT clk_pcs \\
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 50.000 \\
    CONFIG.RESET_TYPE ACTIVE_HIGH \\
    CONFIG.RESET_PORT reset \\
] [get_bd_cells clk_wiz]
connect_bd_intf_net [get_bd_intf_ports USER_SI570_SYSCLK] [get_bd_intf_pins clk_wiz/CLK_IN1_D]
connect_bd_net [get_bd_ports CPU_RESET] [get_bd_pins clk_wiz/reset]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst
connect_bd_net [get_bd_pins clk_wiz/clk_soc] [get_bd_pins rst/slowest_sync_clk]
connect_bd_net [get_bd_ports CPU_RESET] [get_bd_pins rst/ext_reset_in]
connect_bd_net [get_bd_pins clk_wiz/locked] [get_bd_pins rst/dcm_locked]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 pcs_rst
connect_bd_net [get_bd_pins clk_wiz/clk_pcs] [get_bd_pins pcs_rst/slowest_sync_clk]
connect_bd_net [get_bd_ports CPU_RESET] [get_bd_pins pcs_rst/ext_reset_in]
connect_bd_net [get_bd_pins clk_wiz/locked] [get_bd_pins pcs_rst/dcm_locked]

# -------- 1000BASE-X PCS/PMA on SFP0 (emacZero fpga/zcu106 settings) --------
create_bd_cell -type ip -vlnv xilinx.com:ip:gig_ethernet_pcs_pma:17.0 pcs
set_property -dict [list \\
    CONFIG.Standard 1000BASEX \\
    CONFIG.Physical_Interface Transceiver \\
    CONFIG.GT_Type GTH \\
    CONFIG.GT_Location X0Y10 \\
    CONFIG.RefClkRate 156.25 \\
    CONFIG.DrpClkRate 50.0 \\
    CONFIG.SupportLevel Include_Shared_Logic_in_Core \\
    CONFIG.Management_Interface false \\
    CONFIG.Auto_Negotiation true \\
] [get_bd_cells pcs]
connect_bd_intf_net [get_bd_intf_ports SFP_REFCLK] [get_bd_intf_pins pcs/gtrefclk_in]
connect_bd_net [get_bd_pins pcs/txp] [get_bd_ports SFP0_TX_P]
connect_bd_net [get_bd_pins pcs/txn] [get_bd_ports SFP0_TX_N]
connect_bd_net [get_bd_ports SFP0_RX_P] [get_bd_pins pcs/rxp]
connect_bd_net [get_bd_ports SFP0_RX_N] [get_bd_pins pcs/rxn]
connect_bd_net [get_bd_pins clk_wiz/clk_pcs] [get_bd_pins pcs/independent_clock_bufg]

create_bd_cell -type module -reference sfp_pcs_ctrl sfp_ctrl
connect_bd_net [get_bd_pins clk_wiz/clk_pcs] [get_bd_pins sfp_ctrl/clk]
connect_bd_net [get_bd_pins pcs_rst/peripheral_reset] [get_bd_pins sfp_ctrl/rst]
connect_bd_net [get_bd_pins pcs/resetdone] [get_bd_pins sfp_ctrl/gt_resetdone]
connect_bd_net [get_bd_pins pcs/mmcm_locked_out] [get_bd_pins sfp_ctrl/gt_mmcm_locked]
connect_bd_net [get_bd_pins pcs/pma_reset_out] [get_bd_pins sfp_ctrl/pma_reset_out]
connect_bd_net [get_bd_pins pcs/userclk2_out] [get_bd_pins sfp_ctrl/userclk2]
connect_bd_net [get_bd_pins pcs/status_vector] [get_bd_pins sfp_ctrl/status_vector]
connect_bd_net [get_bd_ports DIP_AN_DISABLE] [get_bd_pins sfp_ctrl/an_disable]
connect_bd_net [get_bd_pins sfp_ctrl/pcs_reset] [get_bd_pins pcs/reset]
connect_bd_net [get_bd_pins sfp_ctrl/configuration_vector] [get_bd_pins pcs/configuration_vector]
connect_bd_net [get_bd_pins sfp_ctrl/an_adv_config_vector] [get_bd_pins pcs/an_adv_config_vector]
connect_bd_net [get_bd_pins sfp_ctrl/an_restart_config] [get_bd_pins pcs/an_restart_config]
connect_bd_net [get_bd_pins sfp_ctrl/signal_detect] [get_bd_pins pcs/signal_detect]
connect_bd_net [get_bd_pins sfp_ctrl/sfp_tx_disable_b] [get_bd_ports SFP0_TX_DISABLE_B]
connect_bd_net [get_bd_pins sfp_ctrl/led] [get_bd_ports LED]

# -------- emacZero (GMII) + AXI DMA + RX stream counters --------
create_bd_cell -type module -reference emaczero_axi_gmii_wrapper emaczero
set_property CONFIG.CLK_FREQ_HZ {SOC_CLK_HZ} [get_bd_cells emaczero]
connect_bd_intf_net [get_bd_intf_pins emaczero/GMII] [get_bd_intf_pins pcs/gmii_pcs_pma]
connect_bd_net [get_bd_pins pcs/userclk2_out] [get_bd_pins emaczero/gmii_clk]

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
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXIS_MM2S] [get_bd_intf_pins emaczero/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins emaczero/M_AXIS] [get_bd_intf_pins s2mm_stream_stats/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins s2mm_stream_stats/M_AXIS] [get_bd_intf_pins axi_dma/S_AXIS_S2MM]

# PCS/PMA status for software and the host: status_vector (link, sync,
# auto-negotiation), GT reset done, MMCM locked. Its interrupt fires on any
# change of those bits.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 pcs_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH 32 CONFIG.C_ALL_INPUTS 1 CONFIG.C_INTERRUPT_PRESENT 1] [get_bd_cells pcs_gpio]
connect_bd_net [get_bd_pins sfp_ctrl/status] [get_bd_pins pcs_gpio/gpio_io_i]

# fcapz JTAG-AXI bridge on USER4, through a register slice for timing
create_bd_cell -type module -reference fcapz_ejtagaxi_xilinxus fcapz_axi
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_register_slice:2.1 fcapz_axi_slice
connect_bd_intf_net [get_bd_intf_pins fcapz_axi/M_AXI] [get_bd_intf_pins fcapz_axi_slice/S_AXI]

foreach p {{emaczero/clk axi_dma/s_axi_lite_aclk axi_dma/m_axi_mm2s_aclk
           axi_dma/m_axi_s2mm_aclk axi_dma/m_axi_sg_aclk s2mm_stream_stats/clk
           pcs_gpio/s_axi_aclk fcapz_axi/axi_clk fcapz_axi_slice/aclk}} {{
    connect_bd_net [get_bd_pins clk_wiz/clk_soc] [get_bd_pins $p]
}}
foreach p {{emaczero/rst_n axi_dma/axi_resetn s2mm_stream_stats/rst_n
           pcs_gpio/s_axi_aresetn fcapz_axi_slice/aresetn}} {{
    connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins $p]
}}
# fcapz_axi takes an active-high reset
connect_bd_net [get_bd_pins rst/peripheral_reset] [get_bd_pins fcapz_axi/axi_rst]
"""


def vex_tcl() -> str:
    """VexRiscv-full CPU complex, UltraRAM memories and the address map."""
    main_base, main_range = VEX_RAM_MAIN
    dma_base, dma_range = VEX_RAM_DMA
    eth = {
        "emaczero/S_AXI/reg0": (VEX_PERIPH_BASE + EMACZERO_OFFSET, 0x1000),
        "axi_dma/S_AXI_LITE/Reg": (VEX_PERIPH_BASE + AXI_DMA_OFFSET, 0x10000),
        "s2mm_stream_stats/S_AXI/reg0": (VEX_PERIPH_BASE + STREAM_STATS_OFFSET, 0x10000),
        "pcs_gpio/S_AXI/Reg": (VEX_PERIPH_BASE + PCS_GPIO_OFFSET, 0x10000),
    }
    periph = {
        "uart/S_AXI/Reg": VEX_UART,
        "mtimer/S_AXI/reg0": VEX_MTIMER,
        "intc/S_AXI/Reg": VEX_INTC,
        "bram_ctrl_cpu/S_AXI/Mem0": VEX_SCRATCH_BRAM,
        "cpu_reset_gpio/S_AXI/Reg": VEX_CPU_RESET_GPIO,
        "cpu_liveness_gpio/S_AXI/Reg": VEX_CPU_LIVENESS_GPIO,
        "cpu_last_ibus_gpio/S_AXI/Reg": VEX_CPU_LAST_IBUS_GPIO,
        "cpu_last_dbus_gpio/S_AXI/Reg": VEX_CPU_LAST_DBUS_GPIO,
        **eth,
        "ram_main_ctrl/S_AXI/Mem0": VEX_RAM_MAIN,
        "ram_dma_ctrl/S_AXI/Mem0": VEX_RAM_DMA,
    }
    rams = {
        "ram_main_ctrl/S_AXI/Mem0": VEX_RAM_MAIN,
        "ram_dma_ctrl/S_AXI/Mem0": VEX_RAM_DMA,
    }
    maps = []
    maps.append(f"map_seg cpu/M_AXI_IBUS bootrom/S_AXI/reg0 {hx(VEX_BOOTROM[0])} {hx(VEX_BOOTROM[1])}")
    maps.append(f"map_seg cpu/M_AXI_IBUS ram_main_ctrl/S_AXI/Mem0 {hx(main_base)} {hx(main_range)}")
    for master in ("cpu/M_AXI_DBUS", "fcapz_axi/m_axi"):
        for seg, (base, size) in periph.items():
            maps.append(f"map_seg {master} {seg} {hx(base)} {hx(size)}")
    for master in ("axi_dma/Data_MM2S", "axi_dma/Data_S2MM", "axi_dma/Data_SG"):
        for seg, (base, size) in rams.items():
            maps.append(f"map_seg {master} {seg} {hx(base)} {hx(size)}")
    # IBUS reaches the boot ROM and Zephyr's RAM only
    maps.append("exclude_bd_addr_seg -target_address_space [get_bd_addr_spaces cpu/M_AXI_IBUS] "
                "[get_bd_addr_segs ram_dma_ctrl/S_AXI/Mem0]")
    address_map = "\n".join(maps)

    return f"""
create_bd_port -dir O UART_TXD
create_bd_port -dir I UART_RXD

# -------- CPU + boot ROM + machine timer (the Arty A7 Vex complex) --------
create_bd_cell -type module -reference vexriscv_full_axi_wrapper cpu
create_bd_cell -type module -reference boot_bram_rv32 bootrom
create_bd_cell -type module -reference riscv_mtimer mtimer

# ibus_ic: instruction fetch -> boot ROM + main RAM (SmartConnect adapts the
# read-only master; see build_arty_a7_vex.py).
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 ibus_ic
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 2 CONFIG.NUM_CLKS 1] [get_bd_cells ibus_ic]
# ctrl_axi_ic: DBUS + fcapz -> peripherals and both RAMs
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ctrl_axi_ic
set_property -dict [list CONFIG.NUM_SI 2 CONFIG.NUM_MI 13] [get_bd_cells ctrl_axi_ic]
# R-channel slice on DBUS, as on the Arty (breaks the xbar R-mux ->
# D-cache -> I-cache tag RAM path)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_register_slice:2.1 dbus_r_slice
set_property -dict [list \\
    CONFIG.REG_AW {{0}} CONFIG.REG_AR {{0}} CONFIG.REG_W {{0}} \\
    CONFIG.REG_R  {{1}} CONFIG.REG_B  {{0}}] [get_bd_cells dbus_r_slice]
# dma_axi_ic: the three DMA masters
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 dma_axi_ic
set_property -dict [list CONFIG.NUM_SI 3 CONFIG.NUM_MI 1] [get_bd_cells dma_axi_ic]
# mem_ic: DMA, DBUS and IBUS paths -> the two UltraRAM memories (64-bit)
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 mem_ic
set_property -dict [list CONFIG.NUM_SI 3 CONFIG.NUM_MI 2 CONFIG.NUM_CLKS 1] [get_bd_cells mem_ic]

# -------- UltraRAM memories --------
foreach {{name size}} {{ram_main {main_range} ram_dma {dma_range}}} {{
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 ${{name}}_ctrl
    set_property -dict [list CONFIG.SINGLE_PORT_BRAM 1 CONFIG.DATA_WIDTH 64 \\
        CONFIG.READ_LATENCY {URAM_READ_LATENCY}] [get_bd_cells ${{name}}_ctrl]
    create_bd_cell -type module -reference uram_bram_port $name
    set_property -dict [list CONFIG.ADDR_WIDTH [expr {{int(log($size) / log(2))}}] \\
        CONFIG.DATA_WIDTH 64 CONFIG.READ_LATENCY {URAM_READ_LATENCY}] [get_bd_cells $name]
    set_property -dict [list CONFIG.MEM_SIZE $size CONFIG.MEM_WIDTH 64] [get_bd_intf_pins $name/BRAM_PORTA]
    connect_bd_intf_net [get_bd_intf_pins ${{name}}_ctrl/BRAM_PORTA] [get_bd_intf_pins $name/BRAM_PORTA]
}}

# -------- scratch BRAM (host-visible, as on the Arty) --------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 bram_ctrl_cpu
set_property -dict [list CONFIG.SINGLE_PORT_BRAM 1 CONFIG.DATA_WIDTH 32] [get_bd_cells bram_ctrl_cpu]
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 bram
set_property -dict [list CONFIG.Memory_Type True_Dual_Port_RAM CONFIG.Use_Byte_Write_Enable true \\
    CONFIG.Byte_Size 8 CONFIG.Write_Depth_A {VEX_SCRATCH_BRAM[1] // 4} CONFIG.Enable_32bit_Address true] [get_bd_cells bram]
connect_bd_intf_net [get_bd_intf_pins bram_ctrl_cpu/BRAM_PORTA] [get_bd_intf_pins bram/BRAM_PORTA]

# -------- peripherals --------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 uart
set_property -dict [list CONFIG.C_BAUDRATE 115200 CONFIG.C_DATA_BITS 8] [get_bd_cells uart]
# AXI INTC; each line's edge/level kind follows its source's SENSITIVITY
# (the uartlite pulse is an edge, the rest are levels).
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 intc
set_property CONFIG.C_IRQ_CONNECTION 1 [get_bd_cells intc]
# Host-writable CPU-only reset; powers up asserted so the CPU cannot run
# from empty RAM before the loader has written Zephyr.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 cpu_reset_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH 1 CONFIG.C_ALL_INPUTS 0 CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_DOUT_DEFAULT 0x00000001] [get_bd_cells cpu_reset_gpio]
foreach g {{cpu_liveness_gpio cpu_last_ibus_gpio cpu_last_dbus_gpio}} {{
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 $g
    set_property -dict [list CONFIG.C_GPIO_WIDTH 32 CONFIG.C_ALL_INPUTS 1 CONFIG.C_ALL_OUTPUTS 0] [get_bd_cells $g]
}}
create_bd_cell -type module -reference cpu_liveness_probe cpu_liveness_probe
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 host_reset_inv
set_property -dict [list CONFIG.C_SIZE 1 CONFIG.C_OPERATION not] [get_bd_cells host_reset_inv]
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 cpu_reset_and
set_property -dict [list CONFIG.C_SIZE 1 CONFIG.C_OPERATION and] [get_bd_cells cpu_reset_and]

# IRQ lines, same order as the Arty Vex shell (the overlay's interrupt
# cells): uart(0), pcs_gpio(1), mm2s(2), s2mm(3), emaczero(4)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat
set_property -dict [list CONFIG.NUM_PORTS 5] [get_bd_cells irq_concat]

# -------- clocks --------
foreach p {{cpu/aclk bootrom/aclk mtimer/aclk ibus_ic/aclk mem_ic/aclk dbus_r_slice/aclk
           ram_main_ctrl/s_axi_aclk ram_dma_ctrl/s_axi_aclk bram_ctrl_cpu/s_axi_aclk
           uart/s_axi_aclk intc/s_axi_aclk cpu_reset_gpio/s_axi_aclk
           cpu_liveness_gpio/s_axi_aclk cpu_last_ibus_gpio/s_axi_aclk
           cpu_last_dbus_gpio/s_axi_aclk cpu_liveness_probe/aclk}} {{
    connect_bd_net [get_bd_pins clk_wiz/clk_soc] [get_bd_pins $p]
}}
foreach ic {{ctrl_axi_ic dma_axi_ic}} {{
    connect_bd_net [get_bd_pins clk_wiz/clk_soc] [get_bd_pins $ic/ACLK]
    foreach p [get_bd_pins $ic/*ACLK] {{
        if {{[llength [get_bd_nets -quiet -of_objects $p]] == 0}} {{
            connect_bd_net [get_bd_pins clk_wiz/clk_soc] $p
        }}
    }}
}}

# -------- resets --------
foreach p {{bootrom/aresetn mtimer/aresetn ibus_ic/aresetn mem_ic/aresetn dbus_r_slice/aresetn
           ram_main_ctrl/s_axi_aresetn ram_dma_ctrl/s_axi_aresetn bram_ctrl_cpu/s_axi_aresetn
           uart/s_axi_aresetn intc/s_axi_aresetn cpu_reset_gpio/s_axi_aresetn
           cpu_liveness_gpio/s_axi_aresetn cpu_last_ibus_gpio/s_axi_aresetn
           cpu_last_dbus_gpio/s_axi_aresetn cpu_liveness_probe/aresetn}} {{
    connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins $p]
}}
foreach ic {{ctrl_axi_ic dma_axi_ic}} {{
    connect_bd_net [get_bd_pins rst/interconnect_aresetn] [get_bd_pins $ic/ARESETN]
    foreach p [get_bd_pins $ic/*ARESETN] {{
        if {{[llength [get_bd_nets -quiet -of_objects $p]] == 0}} {{
            connect_bd_net [get_bd_pins rst/peripheral_aresetn] $p
        }}
    }}
}}
# CPU reset = peripheral_aresetn AND NOT(host bit)
connect_bd_net [get_bd_pins cpu_reset_gpio/gpio_io_o] [get_bd_pins host_reset_inv/Op1]
connect_bd_net [get_bd_pins rst/peripheral_aresetn]   [get_bd_pins cpu_reset_and/Op1]
connect_bd_net [get_bd_pins host_reset_inv/Res]       [get_bd_pins cpu_reset_and/Op2]
connect_bd_net [get_bd_pins cpu_reset_and/Res]        [get_bd_pins cpu/aresetn]

# -------- AXI plumbing --------
connect_bd_intf_net [get_bd_intf_pins cpu/M_AXI_IBUS] [get_bd_intf_pins ibus_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ibus_ic/M00_AXI] [get_bd_intf_pins bootrom/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ibus_ic/M01_AXI] [get_bd_intf_pins mem_ic/S02_AXI]

connect_bd_intf_net [get_bd_intf_pins cpu/M_AXI_DBUS]     [get_bd_intf_pins dbus_r_slice/S_AXI]
connect_bd_intf_net [get_bd_intf_pins dbus_r_slice/M_AXI] [get_bd_intf_pins ctrl_axi_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins fcapz_axi_slice/M_AXI] [get_bd_intf_pins ctrl_axi_ic/S01_AXI]

connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_MM2S] [get_bd_intf_pins dma_axi_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_S2MM] [get_bd_intf_pins dma_axi_ic/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_SG]   [get_bd_intf_pins dma_axi_ic/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins dma_axi_ic/M00_AXI] [get_bd_intf_pins mem_ic/S00_AXI]

connect_bd_intf_net [get_bd_intf_pins mem_ic/M00_AXI] [get_bd_intf_pins ram_main_ctrl/S_AXI]
connect_bd_intf_net [get_bd_intf_pins mem_ic/M01_AXI] [get_bd_intf_pins ram_dma_ctrl/S_AXI]

set ctrl_slaves {{uart/S_AXI mtimer/S_AXI pcs_gpio/S_AXI emaczero/S_AXI axi_dma/S_AXI_LITE
                 bram_ctrl_cpu/S_AXI s2mm_stream_stats/S_AXI cpu_reset_gpio/S_AXI
                 mem_ic/S01_AXI cpu_liveness_gpio/S_AXI cpu_last_ibus_gpio/S_AXI
                 cpu_last_dbus_gpio/S_AXI intc/s_axi}}
set mi 0
foreach s $ctrl_slaves {{
    connect_bd_intf_net [get_bd_intf_pins [format ctrl_axi_ic/M%02d_AXI $mi]] [get_bd_intf_pins $s]
    incr mi
}}

# CPU liveness probe on the wrapper's dbg_* outputs
foreach {{src dst}} {{
    dbg_ibus_arvalid ibus_arvalid dbg_ibus_arready ibus_arready dbg_ibus_rvalid ibus_rvalid
    dbg_dbus_arvalid dbus_arvalid dbg_dbus_awvalid dbus_awvalid dbg_dbus_wvalid dbus_wvalid
    dbg_dbus_bvalid dbus_bvalid dbg_reset_i reset_i dbg_ibus_araddr ibus_araddr
    dbg_dbus_awaddr dbus_awaddr
}} {{
    connect_bd_net [get_bd_pins cpu/$src] [get_bd_pins cpu_liveness_probe/$dst]
}}
connect_bd_net [get_bd_pins cpu_liveness_probe/status] [get_bd_pins cpu_liveness_gpio/gpio_io_i]
connect_bd_net [get_bd_pins cpu_liveness_probe/last_ibus_araddr] [get_bd_pins cpu_last_ibus_gpio/gpio_io_i]
connect_bd_net [get_bd_pins cpu_liveness_probe/last_dbus_awaddr] [get_bd_pins cpu_last_dbus_gpio/gpio_io_i]

# -------- interrupts --------
connect_bd_net [get_bd_pins uart/interrupt]       [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins pcs_gpio/ip2intc_irpt] [get_bd_pins irq_concat/In1]
connect_bd_net [get_bd_pins axi_dma/mm2s_introut] [get_bd_pins irq_concat/In2]
connect_bd_net [get_bd_pins axi_dma/s2mm_introut] [get_bd_pins irq_concat/In3]
connect_bd_net [get_bd_pins emaczero/irq]         [get_bd_pins irq_concat/In4]
connect_bd_net [get_bd_pins irq_concat/dout]      [get_bd_pins intc/intr]
connect_bd_net [get_bd_pins intc/irq]             [get_bd_pins cpu/externalInterrupt]
connect_bd_net [get_bd_pins mtimer/timer_irq]     [get_bd_pins cpu/timerInterrupt]

connect_bd_net [get_bd_pins uart/tx] [get_bd_ports UART_TXD]
connect_bd_net [get_bd_ports UART_RXD] [get_bd_pins uart/rx]

# -------- address map --------
{address_map}
"""


def r5_tcl() -> str:
    """Zynq UltraScale+ PS: Cortex-R5 #0 runs Zephyr from PS DDR.

    The R5 reaches the Ethernet blocks over M_AXI_HPM0_LPD; the DMA and the
    fcapz bridge reach PS DDR over S_AXI_HP0_FPD. The PS ports run on the PL's
    150 MHz clock, and pl_resetn0 also resets the PL fabric, so the loader's
    PS-PL reset puts the Ethernet subsystem in a known state.
    """
    eth = {
        "emaczero/S_AXI/reg0": (R5_PL_BASE + EMACZERO_OFFSET, 0x1000),
        "axi_dma/S_AXI_LITE/Reg": (R5_PL_BASE + AXI_DMA_OFFSET, 0x10000),
        "s2mm_stream_stats/S_AXI/reg0": (R5_PL_BASE + STREAM_STATS_OFFSET, 0x10000),
        "pcs_gpio/S_AXI/Reg": (R5_PL_BASE + PCS_GPIO_OFFSET, 0x10000),
    }
    ddr_seg = "ps/SAXIGP2/HP0_DDR_LOW"
    maps = []
    for master in ("ps/Data", "fcapz_axi/m_axi"):
        for seg, (base, size) in eth.items():
            maps.append(f"map_seg {master} {seg} {hx(base)} {hx(size)}")
    for master in ("fcapz_axi/m_axi", "axi_dma/Data_MM2S", "axi_dma/Data_S2MM", "axi_dma/Data_SG"):
        maps.append(f"map_seg {master} {ddr_seg} {hx(R5_DDR[0])} {hx(R5_DDR[1])}")
    # The PL masters use the low DDR window only, and the R5 must not see
    # DDR again through the PL
    maps.append(f"exclude_hp0 fcapz_axi/m_axi {{{ddr_seg}}}")
    for master in ("axi_dma/Data_MM2S", "axi_dma/Data_S2MM", "axi_dma/Data_SG"):
        maps.append(f"exclude_hp0 {master} {{{ddr_seg}}}")
    maps.append("exclude_hp0 ps/Data {}")
    address_map = "\n".join(maps)

    return f"""
# -------- PS: board preset (DDR4, MIO, UART0, clocks), then the PL ports --------
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 ps
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {{apply_board_preset "1"}} [get_bd_cells ps]
set_property -dict [list \\
    CONFIG.PSU__USE__M_AXI_GP0 0 \\
    CONFIG.PSU__USE__M_AXI_GP1 0 \\
    CONFIG.PSU__USE__M_AXI_GP2 1 \\
    CONFIG.PSU__MAXIGP2__DATA_WIDTH 32 \\
    CONFIG.PSU__USE__S_AXI_GP2 1 \\
    CONFIG.PSU__SAXIGP2__DATA_WIDTH 32 \\
    CONFIG.PSU__USE__IRQ0 1 \\
    CONFIG.PSU__NUM_FABRIC_RESETS 1 \\
] [get_bd_cells ps]
# Zephyr's devicetree has to match these: the TTC (system timer) runs on
# LPD_LSBUS and the console on UART0's reference clock
set ps [get_bd_cells ps]
puts "PS_CLOCKS LPD_LSBUS_MHZ=[get_property CONFIG.PSU__CRL_APB__LPD_LSBUS_CTRL__ACT_FREQMHZ $ps]"
puts "PS_CLOCKS UART0_REF_MHZ=[get_property CONFIG.PSU__CRL_APB__UART0_REF_CTRL__ACT_FREQMHZ $ps]"

# lpd_ic: R5 (HPM0_LPD) and fcapz -> the Ethernet blocks; fcapz also -> DDR
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 lpd_ic
set_property -dict [list CONFIG.NUM_SI 2 CONFIG.NUM_MI 5] [get_bd_cells lpd_ic]
# ddr_ic: the three DMA masters and fcapz -> HP0_FPD
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 ddr_ic
set_property -dict [list CONFIG.NUM_SI 4 CONFIG.NUM_MI 1 CONFIG.NUM_CLKS 1] [get_bd_cells ddr_ic]

# IRQs to pl_ps_irq0[3:0], GIC SPI 89..92: pcs_gpio, mm2s, s2mm, emaczero
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat
set_property -dict [list CONFIG.NUM_PORTS 4] [get_bd_cells irq_concat]

# -------- clocks and resets --------
foreach p {{ps/maxihpm0_lpd_aclk ps/saxihp0_fpd_aclk ddr_ic/aclk lpd_ic/ACLK}} {{
    connect_bd_net [get_bd_pins clk_wiz/clk_soc] [get_bd_pins $p]
}}
foreach p [get_bd_pins lpd_ic/*ACLK] {{
    if {{[llength [get_bd_nets -quiet -of_objects $p]] == 0}} {{
        connect_bd_net [get_bd_pins clk_wiz/clk_soc] $p
    }}
}}
connect_bd_net [get_bd_pins rst/interconnect_aresetn] [get_bd_pins lpd_ic/ARESETN]
foreach p [get_bd_pins lpd_ic/*ARESETN] {{
    if {{[llength [get_bd_nets -quiet -of_objects $p]] == 0}} {{
        connect_bd_net [get_bd_pins rst/peripheral_aresetn] $p
    }}
}}
connect_bd_net [get_bd_pins rst/interconnect_aresetn] [get_bd_pins ddr_ic/aresetn]
set_property CONFIG.C_AUX_RESET_HIGH 0 [get_bd_cells rst]
connect_bd_net [get_bd_pins ps/pl_resetn0] [get_bd_pins rst/aux_reset_in]

# -------- AXI plumbing --------
connect_bd_intf_net [get_bd_intf_pins ps/M_AXI_HPM0_LPD] [get_bd_intf_pins lpd_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins fcapz_axi_slice/M_AXI] [get_bd_intf_pins lpd_ic/S01_AXI]
set lpd_slaves {{emaczero/S_AXI axi_dma/S_AXI_LITE s2mm_stream_stats/S_AXI pcs_gpio/S_AXI ddr_ic/S03_AXI}}
set mi 0
foreach s $lpd_slaves {{
    connect_bd_intf_net [get_bd_intf_pins [format lpd_ic/M%02d_AXI $mi]] [get_bd_intf_pins $s]
    incr mi
}}
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_MM2S] [get_bd_intf_pins ddr_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_S2MM] [get_bd_intf_pins ddr_ic/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_SG]   [get_bd_intf_pins ddr_ic/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins ddr_ic/M00_AXI] [get_bd_intf_pins ps/S_AXI_HP0_FPD]

# -------- interrupts --------
connect_bd_net [get_bd_pins pcs_gpio/ip2intc_irpt] [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins axi_dma/mm2s_introut] [get_bd_pins irq_concat/In1]
connect_bd_net [get_bd_pins axi_dma/s2mm_introut] [get_bd_pins irq_concat/In2]
connect_bd_net [get_bd_pins emaczero/irq]         [get_bd_pins irq_concat/In3]
connect_bd_net [get_bd_pins irq_concat/dout]      [get_bd_pins ps/pl_ps_irq0]

# -------- address map --------
# Exclude every HP0 segment but `keep` from a master's address space
proc exclude_hp0 {{space keep}} {{
    set as [get_bd_addr_spaces $space]
    foreach seg [get_bd_addr_segs ps/SAXIGP2/*] {{
        if {{[lsearch -exact $keep [string trimleft $seg /]] < 0}} {{
            exclude_bd_addr_seg -target_address_space $as $seg
        }}
    }}
}}
{address_map}
"""


def finish_tcl(xsa_required: bool = False) -> str:
    """Wrapper, synthesis, implementation, bitstream and the XSA.

    With xsa_required (the R5 shell) a failed write_hw_platform fails the
    build, since the FSBL is built from the XSA.
    """
    on_xsa_error = "exit 1" if xsa_required else "# the XSA is optional here"
    return """
validate_bd_design
save_bd_design
set bd_file [get_files [file join [get_property DIRECTORY [current_project]] ${top}.srcs/sources_1/bd/${top}/${top}.bd]]
make_wrapper -files $bd_file -top
set_property synth_checkpoint_mode None $bd_file
generate_target all $bd_file
add_files -norecurse [file join [get_property DIRECTORY [current_project]] ${top}.gen/sources_1/bd/${top}/hdl/${top}_wrapper.v]
set_property top ${top}_wrapper [current_fileset]
update_compile_order -fileset sources_1

if {$synth_impl} {
    file mkdir reports
    synth_design -top ${top}_wrapper -part $part
    write_checkpoint -force ${top}_wrapper_synth.dcp
    report_utilization -file reports/utilization_synth.rpt
    opt_design
    place_design
    phys_opt_design
    route_design
    write_checkpoint -force ${top}_wrapper_routed.dcp
    report_utilization -file reports/utilization_route.rpt
    report_timing_summary -file reports/timing.rpt
    # A failing image must never replace the bitstream the programming flow
    # loads, and the build must report failure.
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
    puts "TIMING_SUMMARY WNS=$wns WHS=$whs"
    if {$wns < 0 || $whs < 0} {
        puts "ERROR: timing not met (WNS=$wns ns, WHS=$whs ns); bitstream not written"
        exit 1
    }
    write_bitstream -force ${top}_wrapper.bit
    # The bitstream stays a separate file: -include_bit needs a project
    # implementation run, and this flow implements in memory
    if {[catch {write_hw_platform -fixed -force -file ${top}.xsa} hw_err]} {
        puts "WARNING: write_hw_platform failed: $hw_err"
        ON_XSA_ERROR
    }
}
""".replace("ON_XSA_ERROR", on_xsa_error)


def make_tcl(variant: str, synth: bool) -> str:
    top = f"zcu106_{variant}"
    if variant == "vex":
        return project_tcl(top, COMMON_RTL + VEX_RTL, synth) + eth_tcl() + vex_tcl() + finish_tcl()
    if variant == "r5":
        return (project_tcl(top, COMMON_RTL, synth, R5_BOARD_PART) + eth_tcl() + r5_tcl() +
                finish_tcl(xsa_required=True))
    raise SystemExit(f"ERROR: unknown variant {variant}")


# xsct: generate the standalone BSP and zynqmp_fsbl for the lockstep R5
# from the hardware platform, and compile them
FSBL_TCL = """
hsi open_hw_design [lindex $argv 0]
hsi generate_app -hw [hsi current_hw_design] -os standalone -proc psu_cortexr5_0 \
    -app zynqmp_fsbl -compile -sw fsbl -dir [lindex $argv 1]
"""


def find_xsct(vivado: str | None) -> str | None:
    """xsct from PATH, else from the Vitis install next to Vivado's."""
    xsct = shutil.which("xsct")
    if xsct is None and vivado is not None:
        vitis_bin = Path(vivado).resolve().parents[2] / "Vitis" / "bin"
        xsct = shutil.which("xsct", path=str(vitis_bin))
    return xsct


def build_fsbl(build_dir: Path, top: str, xsct: str) -> int:
    """Build the R5 FSBL from the XSA into <top>_fsbl.elf."""
    xsa = build_dir / f"{top}.xsa"
    if not xsa.is_file():
        print(f"ERROR: {xsa} not found; build the hardware first (--synth)")
        return 1
    fsbl_dir = build_dir / "fsbl"
    shutil.rmtree(fsbl_dir, ignore_errors=True)
    tcl = build_dir / "fsbl.tcl"
    tcl.write_text(FSBL_TCL, encoding="utf-8")
    ret = subprocess.call([xsct, tcl.name, xsa.name, fsbl_dir.name], cwd=build_dir)
    elf = fsbl_dir / "executable.elf"
    if ret != 0 or not elf.is_file():
        print("ERROR: FSBL build failed")
        return ret or 1
    shutil.copyfile(elf, build_dir / f"{top}_fsbl.elf")
    print(f"FSBL {build_dir / f'{top}_fsbl.elf'}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--variant", choices=("vex", "r5"), required=True)
    parser.add_argument("--synth", action="store_true",
                        help="run synthesis, implementation and bitstream (and, for r5, "
                             "the FSBL)")
    parser.add_argument("--fsbl", action="store_true",
                        help="r5 only: just build the FSBL from the existing XSA")
    args = parser.parse_args()
    if args.fsbl and args.variant != "r5":
        parser.error("--fsbl applies to --variant r5")

    top = f"zcu106_{args.variant}"
    build_dir = REPO_ROOT / "build" / "vivado" / top
    vivado = shutil.which("vivado")
    xsct = find_xsct(vivado) if args.variant == "r5" and (args.synth or args.fsbl) else None
    if args.variant == "r5" and (args.synth or args.fsbl) and xsct is None:
        raise SystemExit("ERROR: xsct (Vitis) was not found in PATH or next to Vivado")
    if args.fsbl:
        return build_fsbl(build_dir, top, xsct)

    if vivado is None:
        raise SystemExit("ERROR: vivado was not found in PATH")
    (build_dir / "reports").mkdir(parents=True, exist_ok=True)
    tcl = build_dir / "build.tcl"
    tcl.write_text(make_tcl(args.variant, args.synth), encoding="utf-8")

    ret = subprocess.call([vivado, "-mode", "batch", "-source", tcl.name], cwd=build_dir)
    if ret != 0 or xsct is None:
        return ret
    return build_fsbl(build_dir, top, xsct)


if __name__ == "__main__":
    raise SystemExit(main())
