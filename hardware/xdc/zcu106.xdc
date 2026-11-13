# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design
#
# AMD ZCU106 + emacZero hardware shells (hardware/scripts/build_zcu106.py).
# Pins from the Vivado ZCU106 board files (part0_pins.xml) and emacZero's
# fpga/zcu106 constraints. Both variants share every pin here; the R5
# variant leaves the PL UART pins unused and its build drops them.

# ---- 300 MHz user clock (Si570). clk_wiz constrains its own input. ----
set_property PACKAGE_PIN AH12 [get_ports USER_SI570_SYSCLK_clk_p]
set_property PACKAGE_PIN AJ12 [get_ports USER_SI570_SYSCLK_clk_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports {USER_SI570_SYSCLK_clk_p USER_SI570_SYSCLK_clk_n}]

# ---- CPU_RESET push button, active high ----
set_property PACKAGE_PIN G13 [get_ports CPU_RESET]
set_property IOSTANDARD LVCMOS18 [get_ports CPU_RESET]

# ---- SFP GTH reference clock: USER_MGT_SI570 (U56) through the SI53340
#      (U51), 156.25 MHz from power-up, on Quad 226 MGTREFCLK1. It reaches
#      SFP0's channel in Quad 225 over the GT reference clock routing. ----
set_property PACKAGE_PIN U10 [get_ports SFP_REFCLK_clk_p]
set_property PACKAGE_PIN U9  [get_ports SFP_REFCLK_clk_n]
create_clock -name sfp_refclk -period 6.400 [get_ports SFP_REFCLK_clk_p]

# ---- SFP cage 0 serial lanes (GTH X0Y10, set in the PCS/PMA core) ----
set_property PACKAGE_PIN Y4  [get_ports SFP0_TX_P]
set_property PACKAGE_PIN Y3  [get_ports SFP0_TX_N]
set_property PACKAGE_PIN AA2 [get_ports SFP0_RX_P]
set_property PACKAGE_PIN AA1 [get_ports SFP0_RX_N]

# ---- SFP0 TX_DISABLE (drives Q9, so high = laser on; jumper J16 forces
#      the laser on regardless) ----
set_property PACKAGE_PIN AE22 [get_ports SFP0_TX_DISABLE_B]
set_property IOSTANDARD LVCMOS12 [get_ports SFP0_TX_DISABLE_B]

# ---- GPIO_DIP_SW0: turns 1000BASE-X auto-negotiation
#      off, for link partners that do not negotiate ----
set_property PACKAGE_PIN A17 [get_ports DIP_AN_DISABLE]
set_property IOSTANDARD LVCMOS18 [get_ports DIP_AN_DISABLE]

# ---- User LEDs 0-3: GT reset done, PCS sync, link up, userclk2 heartbeat ----
set_property PACKAGE_PIN AL11 [get_ports {LED[0]}]
set_property PACKAGE_PIN AL13 [get_ports {LED[1]}]
set_property PACKAGE_PIN AK13 [get_ports {LED[2]}]
set_property PACKAGE_PIN AE15 [get_ports {LED[3]}]
set_property IOSTANDARD LVCMOS12 [get_ports {LED[*]}]

# ---- PL UART (CP2108 channel uart2_pl); FPGA TX on AL17, FPGA RX on AH17 ----
set_property -quiet PACKAGE_PIN AL17 [get_ports UART_TXD]
set_property -quiet PACKAGE_PIN AH17 [get_ports UART_RXD]
set_property -quiet IOSTANDARD LVCMOS12 [get_ports {UART_TXD UART_RXD}]

# ---- fcapz JTAG-AXI bridge: TCK from BSCANE2 ----
# On UltraScale+ the BSCANE2 TCK output has a timing arc from the JTAG port,
# so Vivado flags a clock defined on it (TIMING-2). It is still the point
# that starts the TCK domain, as in the fcapz and emacZero ZCU106 designs.
create_clock -name tck_bscan -period 100.0 \
    [get_pins -of_objects [get_cells -hierarchical -filter {REF_NAME == BSCANE2}] \
              -filter {REF_PIN_NAME == TCK}]
create_waiver -type METHODOLOGY -id TIMING-2 -user emacz_zephyr \
    -objects [get_clocks tck_bscan] \
    -description "fcapz BSCANE2 TCK is the intended JTAG clock source"

# ---- Clock domains ----
# The SoC clocks (from the 300 MHz Si570 through clk_wiz), the transceiver
# clocks (userclk2 and friends, from sfp_refclk through the GTH) and TCK are
# unrelated. Everything crossing between them goes through synchronizers or
# async FIFOs: emacZero's gmii_cdc, sfp_pcs_ctrl, the AXI GPIO input stage
# and fcapz's own CDC.
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks -of_objects [get_ports USER_SI570_SYSCLK_clk_p]] \
    -group [get_clocks -include_generated_clocks sfp_refclk] \
    -group [get_clocks tck_bscan]

# Static or slow board I/O
set_false_path -from [get_ports {CPU_RESET DIP_AN_DISABLE}]
set_false_path -to   [get_ports {LED[*] SFP0_TX_DISABLE_B}]
