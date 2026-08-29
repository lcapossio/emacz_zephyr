# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
#
# Arty A7-100T MicroBlaze V + emacZero hardware shell constraints.

set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]
create_clock -period 10.000 -name sys_clk [get_ports CLK100MHZ]

set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports BTN0]

set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports UART_TXD]

set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS33} [get_ports {ETH_TXD[0]}]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports {ETH_TXD[1]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {ETH_TXD[2]}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {ETH_TXD[3]}]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports ETH_TX_EN]
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports ETH_TX_CLK]

set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {ETH_RXD[0]}]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports {ETH_RXD[1]}]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports {ETH_RXD[2]}]
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports {ETH_RXD[3]}]
set_property -dict {PACKAGE_PIN G16 IOSTANDARD LVCMOS33} [get_ports ETH_RX_DV]
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS33} [get_ports ETH_RXERR]
set_property -dict {PACKAGE_PIN F15 IOSTANDARD LVCMOS33} [get_ports ETH_RX_CLK]

set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS33} [get_ports ETH_CRS]
set_property -dict {PACKAGE_PIN D17 IOSTANDARD LVCMOS33} [get_ports ETH_COL]

set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS33} [get_ports ETH_MDIO]
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33} [get_ports ETH_MDC]
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports ETH_REF_CLK]
set_property -dict {PACKAGE_PIN C16 IOSTANDARD LVCMOS33} [get_ports ETH_RSTN]

create_clock -period 40.000 -name eth_rx_clk [get_ports ETH_RX_CLK]
create_clock -period 40.000 -name eth_tx_clk [get_ports ETH_TX_CLK]

# DP83848 MII timing at 100 Mb/s.  The PHY drives RX data 10-30 ns after
# RX_CLK; the FPGA drives TX data for the PHY to sample on the next TX_CLK.
set_input_delay  -clock [get_clocks eth_rx_clk] -min 10.000 [get_ports {ETH_RXD[*] ETH_RX_DV ETH_RXERR}]
set_input_delay  -clock [get_clocks eth_rx_clk] -max 30.000 [get_ports {ETH_RXD[*] ETH_RX_DV ETH_RXERR}]
set_output_delay -clock [get_clocks eth_tx_clk] -min 0.000  [get_ports {ETH_TXD[*] ETH_TX_EN}]
set_output_delay -clock [get_clocks eth_tx_clk] -max 10.000 [get_ports {ETH_TXD[*] ETH_TX_EN}]

set_false_path -quiet -from [get_ports {ETH_CRS ETH_COL}]

set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks sys_clk] \
    -group [get_clocks eth_rx_clk] \
    -group [get_clocks eth_tx_clk]

set_false_path -quiet -to [get_pins -quiet -hierarchical -filter {NAME =~ */mii_if/rx_rst_n_s1_reg/CLR}]
set_false_path -quiet -to [get_pins -quiet -hierarchical -filter {NAME =~ */mii_if/tx_rst_n_s1_reg/CLR}]
set_false_path -quiet -to [get_pins -quiet -hierarchical -filter {NAME =~ */emac_irq_sync*/sync_0_reg/D}]
set_false_path -quiet -to [get_pins -quiet -hierarchical -filter {NAME =~ */async_fifo*/wr_ptr_gray_sync1_reg*/D}]
set_false_path -quiet -to [get_pins -quiet -hierarchical -filter {NAME =~ */async_fifo*/rd_ptr_gray_sync1_reg*/D}]
set_false_path -quiet -to [get_pins -quiet -hierarchical -filter {NAME =~ */xpm_fifo_rst_inst/*/D}]
set_false_path -quiet -to [get_pins -quiet -hierarchical -filter {NAME =~ */debug/inst/eth_ref_clk_sync_reg*/D}]
set_false_path -quiet -to [get_pins -quiet -hierarchical -filter {NAME =~ */debug/inst/eth_rstn_sync_reg*/D}]

# proc_sys_reset internal LPF: dcm_locked -> lpf_int_reg. The MIG's
# init_calib_complete (~200 MHz clk_pll_i domain) feeds rst/dcm_locked and
# is by design asynchronous — proc_sys_reset's EXT_LPF already contains
# its own synchronizer/filter. Without this constraint the tool reports a
# spurious -2.8 ns setup violation on this single-endpoint CDC path.
set_false_path -quiet -to [get_pins -quiet -hierarchical -filter {NAME =~ */EXT_LPF/lpf_int_reg/D}]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
