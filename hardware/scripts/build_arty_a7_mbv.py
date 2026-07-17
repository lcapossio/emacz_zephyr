#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
"""Build the Arty A7-100T MicroBlaze V + emacZero Vivado hardware shell."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
from pathlib import Path


PART = "xc7a100tcsg324-1"
TOP = "arty_a7_100t_mbv"
BUILD_DIR = Path("build") / "vivado" / TOP
DDR_BASE = "0x90000000"
DDR_RANGE = "0x10000000"
SOC_CLK_HZ = 81247969
LOADER_BRAM_RANGE = "0x00008000"
LOADER_BRAM_WORDS = 8192
LOADER_AXI_BASE = "0x80008000"
SCRATCH_BRAM_BASE = "0x80040000"
SCRATCH_BRAM_RANGE = "0x00008000"
SCRATCH_BRAM_WORDS = 8192


EMACZERO_RTL = [
    "external/emacZero/rtl/crc32.v",
    "external/emacZero/rtl/async_fifo.v",
    "external/emacZero/rtl/sync_fifo.v",
    "external/emacZero/rtl/mii_if.v",
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

FCAPZ_RTL = [
    "fcapz/rtl/reset_sync.v",
    "fcapz/rtl/dpram.v",
    "fcapz/rtl/fcapz_async_fifo.v",
    "fcapz/rtl/trig_compare.v",
    "fcapz/rtl/jtag_reg_iface.v",
    "fcapz/rtl/jtag_pipe_iface.v",
    "fcapz/rtl/jtag_burst_read.v",
    "fcapz/rtl/fcapz_regbus_mux.v",
    "fcapz/rtl/fcapz_eio.v",
    "fcapz/rtl/fcapz_ela.v",
    "fcapz/rtl/fcapz_ela_xilinx7.v",
    "fcapz/rtl/fcapz_ejtagaxi.v",
    "fcapz/rtl/fcapz_ejtagaxi_xilinx7.v",
    "fcapz/rtl/fcapz_ejtaguart.v",
    "fcapz/rtl/jtag_tap/jtag_tap_xilinx7.v",
    "fcapz/rtl/fcapz_ejtaguart_xilinx7.v",
]

LOCAL_DEBUG_RTL = [
    "hardware/rtl/bram_port_mux.v",
    "hardware/rtl/fcapz_mbv_debug.v",
]


def rel_list(paths: list[str]) -> str:
    return " ".join(paths)


def make_tcl(args: argparse.Namespace) -> str:
    synth_impl = "1" if args.synth else "0"
    jobs = max(1, args.jobs)
    elf = Path(args.elf).resolve().as_posix() if args.elf else ""
    return f"""
set repo_root [file normalize [file join [pwd] .. .. ..]]
set part {PART}
set top {TOP}
set synth_impl {synth_impl}
set jobs {jobs}
set elf_file {{{elf}}}

proc stage_mbv_elf {{}} {{
    global elf_file top
    if {{$elf_file eq ""}} {{
        return
    }}
    if {{![file exists $elf_file]}} {{
        error "ELF file not found: $elf_file"
    }}
    set mbv_data_dir [file join [get_property DIRECTORY [current_project]] ${{top}}.gen/sources_1/bd/${{top}}/ip/${{top}}_mbv_0/data]
    file mkdir $mbv_data_dir
    set staged_elf [file join $mbv_data_dir riscv_bootloop.elf]
    file copy -force $elf_file $staged_elf
    puts "INFO: staged MicroBlaze V boot ELF $elf_file -> $staged_elf ([file size $staged_elf] bytes)"
}}

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
    read_verilog -sv [file join $repo_root $f]
}}
add_files -norecurse [file join $repo_root external/emacZero/rtl/version.vh]
add_files -norecurse [file join $repo_root fcapz/rtl/fcapz_version.vh]
set_property include_dirs [list \\
    [file join $repo_root external/emacZero/rtl] \\
    [file join $repo_root fcapz/rtl] \\
] [current_fileset]
read_xdc [file join $repo_root hardware/xdc/arty_a7_100t_mbv.xdc]

create_bd_design $top

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

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 mig_rst
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 eth_rst
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 mb_rst_or
set_property -dict [list CONFIG.C_SIZE 1 CONFIG.C_OPERATION or] [get_bd_cells mb_rst_or]
create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze_riscv:1.0 mbv
set_property -dict [list \\
    CONFIG.C_USE_MULDIV 2 \\
    CONFIG.C_USE_ATOMIC 1 \\
    CONFIG.C_USE_COMPRESSION 1 \\
    CONFIG.C_USE_INTERRUPT 1 \\
    CONFIG.C_BASE_VECTORS 0x0000000090000000 \\
    CONFIG.C_PC_WIDTH 32 \\
    CONFIG.C_FREQ {SOC_CLK_HZ} \\
    CONFIG.C_I_LMB 1 \\
    CONFIG.C_D_LMB 1 \\
    CONFIG.C_I_AXI 1 \\
    CONFIG.C_D_AXI 1 \\
    CONFIG.C_USE_ICACHE 1 \\
    CONFIG.C_ICACHE_BASEADDR 0x0000000090000000 \\
    CONFIG.C_ICACHE_HIGHADDR 0x000000009fffffff \\
    CONFIG.C_ICACHE_BYTE_SIZE 16384 \\
    CONFIG.C_ICACHE_LINE_LEN 4 \\
    CONFIG.C_USE_DCACHE 1 \\
    CONFIG.C_DCACHE_BASEADDR 0x0000000090000000 \\
    CONFIG.C_DCACHE_HIGHADDR 0x0000000097ffffff \\
    CONFIG.C_DCACHE_BYTE_SIZE 16384 \\
    CONFIG.C_DCACHE_LINE_LEN 4 \\
    CONFIG.C_DCACHE_USE_WRITEBACK 0 \\
    CONFIG.C_INTERCONNECT 2 \\
    CONFIG.C_DEBUG_ENABLED 0 \\
] [get_bd_cells mbv]

create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10:3.0 ilmb
create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10:3.0 dlmb
create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr:4.0 ilmb_cntlr
create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr:4.0 dlmb_cntlr
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 lmb_bram
set_property -dict [list CONFIG.Memory_Type True_Dual_Port_RAM CONFIG.Use_Byte_Write_Enable true CONFIG.Byte_Size 8 CONFIG.Write_Depth_A {LOADER_BRAM_WORDS} CONFIG.Enable_32bit_Address true] [get_bd_cells lmb_bram]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ctrl_axi_ic
set_property -dict [list CONFIG.NUM_SI 3 CONFIG.NUM_MI 9] [get_bd_cells ctrl_axi_ic]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 dma_axi_ic
set_property -dict [list CONFIG.NUM_SI 3 CONFIG.NUM_MI 1] [get_bd_cells dma_axi_ic]
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 ddr_axi_ic
set_property -dict [list CONFIG.NUM_SI 4 CONFIG.NUM_MI 1] [get_bd_cells ddr_axi_ic]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_clock_converter:2.1 emac_axi_cc
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 bram_ctrl_cpu
set_property -dict [list CONFIG.SINGLE_PORT_BRAM 1 CONFIG.DATA_WIDTH 32] [get_bd_cells bram_ctrl_cpu]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 lmb_loader_ctrl
set_property -dict [list CONFIG.SINGLE_PORT_BRAM 1 CONFIG.DATA_WIDTH 32] [get_bd_cells lmb_loader_ctrl]
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 bram
set_property -dict [list CONFIG.Memory_Type True_Dual_Port_RAM CONFIG.Use_Byte_Write_Enable true CONFIG.Byte_Size 8 CONFIG.Write_Depth_A {SCRATCH_BRAM_WORDS} CONFIG.Enable_32bit_Address true] [get_bd_cells bram]

create_bd_cell -type ip -vlnv xilinx.com:ip:mig_7series:4.2 mig_ddr
set_property -dict [list \\
    CONFIG.XML_INPUT_FILE [file join $repo_root hardware/mig/arty_a7_100t_mig.prj] \\
    CONFIG.RESET_BOARD_INTERFACE Custom \\
    CONFIG.MIG_DONT_TOUCH_PARAM Custom \\
] [get_bd_cells mig_ddr]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 uart
set_property -dict [list CONFIG.C_BAUDRATE 115200 CONFIG.C_DATA_BITS 8] [get_bd_cells uart]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_timer:2.0 timer
set_property -dict [list CONFIG.enable_timer2 1] [get_bd_cells timer]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 intc
set_property -dict [list CONFIG.C_KIND_OF_INTR 0x0000000A] [get_bd_cells intc]
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
create_bd_cell -type module -reference axis_async_fifo tx_axis_cc
create_bd_cell -type module -reference axis_async_fifo rx_axis_cc
create_bd_cell -type module -reference clock_root_100m clock_root
create_bd_cell -type module -reference emaczero_axi_mii_wrapper emaczero
set_property -dict [list CONFIG.MII_DEBUG 1] [get_bd_cells emaczero]
create_bd_cell -type module -reference fcapz_mbv_debug debug
create_bd_cell -type module -reference bram_port_mux lmb_bram_mux
create_bd_cell -type module -reference sync_level emac_irq_sync
set_property -dict [list CONFIG.CLK_HZ {SOC_CLK_HZ} CONFIG.UART_BAUD 115200 CONFIG.ELA_DEPTH 512] [get_bd_cells debug]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_register_slice:2.1 debug_axi_slice

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat
set_property -dict [list CONFIG.NUM_PORTS 11] [get_bd_cells irq_concat]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const0
set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 0] [get_bd_cells const0]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const0_8
set_property -dict [list CONFIG.CONST_WIDTH 8 CONFIG.CONST_VAL 0] [get_bd_cells const0_8]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const0_2
set_property -dict [list CONFIG.CONST_WIDTH 2 CONFIG.CONST_VAL 0] [get_bd_cells const0_2]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const1
set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 1] [get_bd_cells const1]

set_property FREQ_HZ 100000000 [get_bd_intf_pins emac_axi_cc/M_AXI]
set_property FREQ_HZ {SOC_CLK_HZ} [get_bd_intf_pins emac_axi_cc/S_AXI]
set_property FREQ_HZ {SOC_CLK_HZ} [get_bd_intf_pins tx_axis_cc/S_AXIS]
set_property FREQ_HZ 100000000 [get_bd_intf_pins tx_axis_cc/M_AXIS]
set_property FREQ_HZ 100000000 [get_bd_intf_pins rx_axis_cc/S_AXIS]
set_property FREQ_HZ {SOC_CLK_HZ} [get_bd_intf_pins rx_axis_cc/M_AXIS]

connect_bd_net [get_bd_ports CLK100MHZ] [get_bd_pins clock_root/clk_in]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins mig_ddr/sys_clk_i]
connect_bd_net [get_bd_pins mig_ddr/ui_addn_clk_0] [get_bd_pins mig_ddr/clk_ref_i]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins rst/slowest_sync_clk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins mig_rst/slowest_sync_clk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins eth_rst/slowest_sync_clk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins mbv/Clk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins ilmb/LMB_Clk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins dlmb/LMB_Clk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins ilmb_cntlr/LMB_Clk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins dlmb_cntlr/LMB_Clk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins ctrl_axi_ic/ACLK]
foreach p [get_bd_pins ctrl_axi_ic/*ACLK] {{
    if {{[llength [get_bd_nets -quiet -of_objects $p]] == 0}} {{
        connect_bd_net [get_bd_pins mig_ddr/ui_clk] $p
    }}
}}
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins dma_axi_ic/ACLK]
foreach p [get_bd_pins dma_axi_ic/*ACLK] {{
    if {{[llength [get_bd_nets -quiet -of_objects $p]] == 0}} {{
        connect_bd_net [get_bd_pins mig_ddr/ui_clk] $p
    }}
}}
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins ddr_axi_ic/aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins bram_ctrl_cpu/s_axi_aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins lmb_loader_ctrl/s_axi_aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins uart/s_axi_aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins timer/s_axi_aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins intc/s_axi_aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins gpio/s_axi_aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins axi_dma/s_axi_lite_aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins axi_dma/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins axi_dma/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins axi_dma/m_axi_sg_aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins emac_axi_cc/s_axi_aclk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins emac_axi_cc/m_axi_aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins tx_axis_cc/s_clk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins tx_axis_cc/m_clk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins rx_axis_cc/s_clk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins rx_axis_cc/m_clk]
connect_bd_net [get_bd_pins clock_root/clk100] [get_bd_pins emaczero/clk]
connect_bd_net [get_bd_pins clock_root/clk25] [get_bd_pins emaczero/phy_ref_clk_25]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins debug/clk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins debug_axi_slice/aclk]
connect_bd_net [get_bd_pins mig_ddr/ui_clk] [get_bd_pins emac_irq_sync/clk]

connect_bd_net [get_bd_ports BTN0] [get_bd_pins rst/ext_reset_in]
connect_bd_net [get_bd_ports BTN0] [get_bd_pins mig_rst/ext_reset_in]
connect_bd_net [get_bd_ports BTN0] [get_bd_pins eth_rst/ext_reset_in]
connect_bd_net [get_bd_pins const1/dout] [get_bd_pins rst/aux_reset_in]
connect_bd_net [get_bd_pins mig_ddr/init_calib_complete] [get_bd_pins rst/dcm_locked]
connect_bd_net [get_bd_pins const1/dout] [get_bd_pins mig_rst/aux_reset_in]
connect_bd_net [get_bd_pins mig_ddr/mmcm_locked] [get_bd_pins mig_rst/dcm_locked]
connect_bd_net [get_bd_pins const1/dout] [get_bd_pins eth_rst/aux_reset_in]
connect_bd_net [get_bd_pins clock_root/locked] [get_bd_pins eth_rst/dcm_locked]
connect_bd_net [get_bd_ports BTN0] [get_bd_pins mig_ddr/sys_rst]
connect_bd_net [get_bd_pins rst/mb_reset] [get_bd_pins mb_rst_or/Op1]
connect_bd_net [get_bd_pins debug/debug_reset_req] [get_bd_pins mb_rst_or/Op2]
connect_bd_net [get_bd_pins mb_rst_or/Res] [get_bd_pins mbv/Reset]
connect_bd_net [get_bd_pins rst/peripheral_reset] [get_bd_pins ilmb/SYS_Rst]
connect_bd_net [get_bd_pins rst/peripheral_reset] [get_bd_pins dlmb/SYS_Rst]
connect_bd_net [get_bd_pins rst/peripheral_reset] [get_bd_pins ilmb_cntlr/LMB_Rst]
connect_bd_net [get_bd_pins rst/peripheral_reset] [get_bd_pins dlmb_cntlr/LMB_Rst]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins ctrl_axi_ic/ARESETN]
foreach p [get_bd_pins ctrl_axi_ic/*ARESETN] {{
    if {{[llength [get_bd_nets -quiet -of_objects $p]] == 0}} {{
        connect_bd_net [get_bd_pins rst/peripheral_aresetn] $p
    }}
}}
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins dma_axi_ic/ARESETN]
foreach p [get_bd_pins dma_axi_ic/*ARESETN] {{
    if {{[llength [get_bd_nets -quiet -of_objects $p]] == 0}} {{
        connect_bd_net [get_bd_pins rst/peripheral_aresetn] $p
    }}
}}
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins ddr_axi_ic/aresetn]
connect_bd_net [get_bd_pins mig_rst/peripheral_aresetn] [get_bd_pins mig_ddr/aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins bram_ctrl_cpu/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins lmb_loader_ctrl/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins uart/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins timer/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins intc/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins gpio/s_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins axi_dma/axi_resetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins emac_axi_cc/s_axi_aresetn]
connect_bd_net [get_bd_pins eth_rst/peripheral_aresetn] [get_bd_pins emac_axi_cc/m_axi_aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins tx_axis_cc/s_rst_n]
connect_bd_net [get_bd_pins eth_rst/peripheral_aresetn] [get_bd_pins tx_axis_cc/m_rst_n]
connect_bd_net [get_bd_pins eth_rst/peripheral_aresetn] [get_bd_pins rx_axis_cc/s_rst_n]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins rx_axis_cc/m_rst_n]
connect_bd_net [get_bd_pins eth_rst/peripheral_aresetn] [get_bd_pins emaczero/rst_n]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins debug_axi_slice/aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins emac_irq_sync/rst_n]
connect_bd_net [get_bd_pins rst/peripheral_reset] [get_bd_pins debug/rst]

connect_bd_intf_net [get_bd_intf_pins mbv/M_AXI_IP] [get_bd_intf_pins ctrl_axi_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins mbv/M_AXI_DP] [get_bd_intf_pins ctrl_axi_ic/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins mbv/ILMB] [get_bd_intf_pins ilmb/LMB_M]
connect_bd_intf_net [get_bd_intf_pins mbv/DLMB] [get_bd_intf_pins dlmb/LMB_M]
connect_bd_intf_net [get_bd_intf_pins ilmb/LMB_Sl_0] [get_bd_intf_pins ilmb_cntlr/SLMB]
connect_bd_intf_net [get_bd_intf_pins dlmb/LMB_Sl_0] [get_bd_intf_pins dlmb_cntlr/SLMB]
connect_bd_intf_net [get_bd_intf_pins debug/M_AXI] [get_bd_intf_pins debug_axi_slice/S_AXI]
connect_bd_intf_net [get_bd_intf_pins debug_axi_slice/M_AXI] [get_bd_intf_pins ctrl_axi_ic/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_MM2S] [get_bd_intf_pins dma_axi_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_S2MM] [get_bd_intf_pins dma_axi_ic/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXI_SG] [get_bd_intf_pins dma_axi_ic/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M00_AXI] [get_bd_intf_pins uart/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M01_AXI] [get_bd_intf_pins timer/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M02_AXI] [get_bd_intf_pins intc/s_axi]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M03_AXI] [get_bd_intf_pins gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M04_AXI] [get_bd_intf_pins emac_axi_cc/S_AXI]
connect_bd_intf_net [get_bd_intf_pins emac_axi_cc/M_AXI] [get_bd_intf_pins emaczero/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M05_AXI] [get_bd_intf_pins axi_dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M06_AXI] [get_bd_intf_pins bram_ctrl_cpu/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M07_AXI] [get_bd_intf_pins lmb_loader_ctrl/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_axi_ic/M08_AXI] [get_bd_intf_pins ddr_axi_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma_axi_ic/M00_AXI] [get_bd_intf_pins ddr_axi_ic/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins mbv/M_AXI_IC] [get_bd_intf_pins ddr_axi_ic/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins mbv/M_AXI_DC] [get_bd_intf_pins ddr_axi_ic/S03_AXI]
connect_bd_intf_net [get_bd_intf_pins ddr_axi_ic/M00_AXI] [get_bd_intf_pins mig_ddr/S_AXI]

connect_bd_intf_net [get_bd_intf_pins axi_dma/M_AXIS_MM2S] [get_bd_intf_pins tx_axis_cc/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins tx_axis_cc/M_AXIS] [get_bd_intf_pins emaczero/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins emaczero/M_AXIS] [get_bd_intf_pins rx_axis_cc/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins rx_axis_cc/M_AXIS] [get_bd_intf_pins axi_dma/S_AXIS_S2MM]

connect_bd_net [get_bd_pins const0_8/dout] [get_bd_pins debug/dma_rx_axis_tdata]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/dma_rx_axis_tvalid]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/dma_rx_axis_tready]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/dma_rx_axis_tlast]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/dma_rx_axis_tsof]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/dma_rx_axis_terror]
connect_bd_net [get_bd_pins const0_8/dout] [get_bd_pins debug/s2mm_awlen]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/s2mm_awvalid]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/s2mm_awready]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/s2mm_wvalid]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/s2mm_wready]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/s2mm_wlast]
connect_bd_net [get_bd_pins const0_2/dout] [get_bd_pins debug/s2mm_bresp]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/s2mm_bvalid]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/s2mm_bready]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/sg_awvalid]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/sg_awready]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/sg_wvalid]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/sg_wready]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/sg_bvalid]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/sg_bready]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/sg_arvalid]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/sg_arready]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/sg_rvalid]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/sg_rready]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/sg_rlast]
connect_bd_net [get_bd_pins const0_8/dout] [get_bd_pins debug/mac_rx_axis_tdata]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/mac_rx_axis_tvalid]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/mac_rx_axis_tready]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/mac_rx_axis_tlast]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/mac_rx_axis_tsof]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins debug/mac_rx_axis_terror]

connect_bd_intf_net [get_bd_intf_pins ilmb_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram/BRAM_PORTA]
connect_bd_intf_net [get_bd_intf_pins dlmb_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram_mux/CPU]
connect_bd_intf_net [get_bd_intf_pins lmb_loader_ctrl/BRAM_PORTA] [get_bd_intf_pins lmb_bram_mux/LOADER]
connect_bd_intf_net [get_bd_intf_pins lmb_bram_mux/MEM] [get_bd_intf_pins lmb_bram/BRAM_PORTB]
connect_bd_intf_net [get_bd_intf_pins bram_ctrl_cpu/BRAM_PORTA] [get_bd_intf_pins bram/BRAM_PORTA]
connect_bd_intf_net [get_bd_intf_pins intc/interrupt] [get_bd_intf_pins mbv/INTERRUPT]

connect_bd_net [get_bd_pins debug/debug_reset_req] [get_bd_pins lmb_bram_mux/select_loader]

# Re-assert converter interface metadata after interface connection, since
# IP integrator can re-propagate the default 10 MHz values during connect.
set_property FREQ_HZ 100000000 [get_bd_intf_pins emac_axi_cc/M_AXI]
set_property FREQ_HZ {SOC_CLK_HZ} [get_bd_intf_pins emac_axi_cc/S_AXI]
set_property FREQ_HZ {SOC_CLK_HZ} [get_bd_intf_pins tx_axis_cc/S_AXIS]
set_property FREQ_HZ 100000000 [get_bd_intf_pins tx_axis_cc/M_AXIS]
set_property FREQ_HZ 100000000 [get_bd_intf_pins rx_axis_cc/S_AXIS]
set_property FREQ_HZ {SOC_CLK_HZ} [get_bd_intf_pins rx_axis_cc/M_AXIS]

connect_bd_net [get_bd_pins timer/interrupt] [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins uart/interrupt] [get_bd_pins irq_concat/In1]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins irq_concat/In2]
connect_bd_net [get_bd_pins const0/dout] [get_bd_pins irq_concat/In3]
connect_bd_net [get_bd_pins gpio/ip2intc_irpt] [get_bd_pins irq_concat/In4]
connect_bd_net [get_bd_pins emaczero/irq] [get_bd_pins emac_irq_sync/din]
connect_bd_net [get_bd_pins emac_irq_sync/dout] [get_bd_pins irq_concat/In5]
connect_bd_net [get_bd_pins axi_dma/mm2s_introut] [get_bd_pins irq_concat/In6]
connect_bd_net [get_bd_pins axi_dma/s2mm_introut] [get_bd_pins irq_concat/In7]
for {{set i 8}} {{$i < 11}} {{incr i}} {{
    connect_bd_net [get_bd_pins const0/dout] [get_bd_pins irq_concat/In$i]
}}
connect_bd_net [get_bd_pins irq_concat/dout] [get_bd_pins intc/intr]
connect_bd_net [get_bd_pins uart/tx] [get_bd_ports UART_TXD]
connect_bd_net [get_bd_pins uart/tx] [get_bd_pins debug/cpu_uart_tx]
connect_bd_net [get_bd_pins debug/cpu_uart_rx] [get_bd_pins uart/rx]
connect_bd_net [get_bd_pins timer/interrupt] [get_bd_pins debug/timer_irq]
connect_bd_net [get_bd_pins uart/interrupt] [get_bd_pins debug/uart_irq]
connect_bd_net [get_bd_pins gpio/ip2intc_irpt] [get_bd_pins debug/gpio_irq]
connect_bd_net [get_bd_pins emac_irq_sync/dout] [get_bd_pins debug/emac_irq]
connect_bd_net [get_bd_pins mb_rst_or/Res] [get_bd_pins debug/mb_reset]
connect_bd_net [get_bd_pins rst/peripheral_reset] [get_bd_pins debug/peripheral_reset]

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
connect_bd_net [get_bd_pins emaczero/eth_rstn] [get_bd_pins debug/phy_rstn]
connect_bd_net [get_bd_pins emaczero/dbg_mii_txd_pre_iob] [get_bd_pins debug/mii_txd_pre_iob]
connect_bd_net [get_bd_pins emaczero/dbg_mii_tx_en_pre_iob] [get_bd_pins debug/mii_tx_en_pre_iob]
connect_bd_net [get_bd_ports ETH_TX_CLK] [get_bd_pins debug/eth_tx_clk]
connect_bd_net [get_bd_pins clock_root/clk25] [get_bd_pins debug/phy_ref_clk_25]

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

proc exclude_seg {{space seg}} {{
    set as [get_bd_addr_spaces -quiet $space]
    set ss [get_bd_addr_segs -quiet $seg]
    if {{[llength $as] != 1 || [llength $ss] != 1}} {{
        return
    }}
    catch {{exclude_bd_addr_seg -target_address_space $as $ss}}
}}

map_seg mbv/Instruction ilmb_cntlr/SLMB/Mem       0x80000000 {LOADER_BRAM_RANGE}
map_seg mbv/Data        dlmb_cntlr/SLMB/Mem       0x80000000 {LOADER_BRAM_RANGE}
map_seg mbv/Instruction bram_ctrl_cpu/S_AXI/Mem0  {SCRATCH_BRAM_BASE} {SCRATCH_BRAM_RANGE}
map_seg mbv/Data        bram_ctrl_cpu/S_AXI/Mem0  {SCRATCH_BRAM_BASE} {SCRATCH_BRAM_RANGE}
map_seg debug/m_axi     lmb_loader_ctrl/S_AXI/Mem0 {LOADER_AXI_BASE} {LOADER_BRAM_RANGE}
map_seg debug/m_axi     bram_ctrl_cpu/S_AXI/Mem0  {SCRATCH_BRAM_BASE} {SCRATCH_BRAM_RANGE}
map_seg mbv/Instruction mig_ddr/memmap/memaddr    {DDR_BASE} {DDR_RANGE}
map_seg mbv/Data        mig_ddr/memmap/memaddr    {DDR_BASE} {DDR_RANGE}
map_seg debug/m_axi     mig_ddr/memmap/memaddr    {DDR_BASE} {DDR_RANGE}
map_seg axi_dma/Data_MM2S mig_ddr/memmap/memaddr  {DDR_BASE} {DDR_RANGE}
map_seg axi_dma/Data_SG   mig_ddr/memmap/memaddr  {DDR_BASE} {DDR_RANGE}
map_seg axi_dma/Data_S2MM mig_ddr/memmap/memaddr  {DDR_BASE} {DDR_RANGE}

exclude_seg mbv/Instruction lmb_loader_ctrl/S_AXI/Mem0
exclude_seg mbv/Data        lmb_loader_ctrl/S_AXI/Mem0

foreach {{space}} {{mbv/Instruction mbv/Data debug/m_axi}} {{
    map_seg $space uart/S_AXI/Reg         0x40600000 0x00010000
    map_seg $space timer/S_AXI/Reg        0x41C00000 0x00010000
    map_seg $space intc/S_AXI/Reg         0x41200000 0x00010000
    map_seg $space gpio/S_AXI/Reg         0x40010000 0x00010000
    map_seg $space emaczero/S_AXI/reg0    0x44A00000 0x00001000
    map_seg $space axi_dma/S_AXI_LITE/Reg 0x41E00000 0x00010000
}}

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
    stage_mbv_elf
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


def write_bitstream_retry_tcl() -> str:
    """Return a small Tcl fallback for Vivado managed-run bitgen crashes."""
    dcp = f"{TOP}.runs/impl_1/{TOP}_wrapper_routed.dcp"
    bit = f"{TOP}_recovered.bit"
    ltx = f"{TOP}_recovered.ltx"
    mmi = f"{TOP}_recovered.mmi"
    return f"""\
set dcp [file normalize "{dcp}"]
set bit [file normalize "{bit}"]
set ltx [file normalize "{ltx}"]
set mmi [file normalize "{mmi}"]

puts "Fallback bitstream generation from routed checkpoint"
puts "  DCP: $dcp"
puts "  BIT: $bit"
open_checkpoint $dcp
catch {{ write_mem_info -force -no_partial_mmi $mmi }} mem_result
puts "write_mem_info: $mem_result"
write_bitstream -force $bit
catch {{ write_debug_probes -quiet -force $ltx }} ltx_result
puts "write_debug_probes: $ltx_result"
puts "Fallback bitstream complete: $bit"
"""


def retry_bitstream_from_routed(vivado: str, env: dict[str, str]) -> int:
    """Recover from Vivado managed-run crashes during write_bitstream."""
    routed_dcp = BUILD_DIR / f"{TOP}.runs" / "impl_1" / f"{TOP}_wrapper_routed.dcp"
    if not routed_dcp.exists():
        print(f"ERROR: no routed checkpoint for bitstream retry: {routed_dcp}")
        return 1

    retry_tcl = BUILD_DIR / "write_bitstream_retry.tcl"
    retry_tcl.write_text(write_bitstream_retry_tcl(), encoding="utf-8")
    cmd = [
        vivado,
        "-mode",
        "batch",
        "-source",
        retry_tcl.name,
        "-log",
        "write_bitstream_retry.log",
        "-journal",
        "write_bitstream_retry.jou",
    ]
    print("Vivado managed run failed after routing; retrying bitstream from routed DCP")
    return subprocess.call(cmd, cwd=BUILD_DIR, env=env)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--synth", action="store_true", help="run synthesis/implementation/bitstream")
    parser.add_argument("--jobs", type=int, default=2, help="Vivado implementation jobs")
    parser.add_argument("--elf", help="optional ELF to embed in the MicroBlaze V BRAM bitstream")
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
