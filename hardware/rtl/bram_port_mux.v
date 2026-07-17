// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Leonardo Capossio - bard0 design
//
// Reset-time native BRAM port mux for the Arty A7 MicroBlaze V shell.
//
// The CPU side owns the memory during normal execution. The loader side owns it
// only while fcapz holds the processor in reset, allowing EJTAG-AXI to patch the
// boot BRAM without requiring a new bitstream.

`timescale 1ns / 1ps

module bram_port_mux #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer WE_WIDTH = DATA_WIDTH / 8
) (
    input wire select_loader,

    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 CPU CLK" *)
    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL, MEM_SIZE 32768, MEM_WIDTH 32, READ_WRITE_MODE READ_WRITE" *)
    input wire cpu_clk,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 CPU RST" *)
    input wire cpu_rst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 CPU EN" *)
    input wire cpu_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 CPU WE" *)
    input wire [WE_WIDTH-1:0] cpu_we,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 CPU ADDR" *)
    input wire [ADDR_WIDTH-1:0] cpu_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 CPU DIN" *)
    input wire [DATA_WIDTH-1:0] cpu_din,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 CPU DOUT" *)
    output wire [DATA_WIDTH-1:0] cpu_dout,

    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 LOADER CLK" *)
    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL, MEM_SIZE 32768, MEM_WIDTH 32, READ_WRITE_MODE READ_WRITE" *)
    input wire loader_clk,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 LOADER RST" *)
    input wire loader_rst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 LOADER EN" *)
    input wire loader_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 LOADER WE" *)
    input wire [WE_WIDTH-1:0] loader_we,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 LOADER ADDR" *)
    input wire [ADDR_WIDTH-1:0] loader_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 LOADER DIN" *)
    input wire [DATA_WIDTH-1:0] loader_din,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 LOADER DOUT" *)
    output wire [DATA_WIDTH-1:0] loader_dout,

    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MEM CLK" *)
    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL, MEM_SIZE 32768, MEM_WIDTH 32, READ_WRITE_MODE READ_WRITE" *)
    output wire mem_clk,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MEM RST" *)
    output wire mem_rst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MEM EN" *)
    output wire mem_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MEM WE" *)
    output wire [WE_WIDTH-1:0] mem_we,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MEM ADDR" *)
    output wire [ADDR_WIDTH-1:0] mem_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MEM DIN" *)
    output wire [DATA_WIDTH-1:0] mem_din,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MEM DOUT" *)
    input wire [DATA_WIDTH-1:0] mem_dout
);

assign mem_clk = select_loader ? loader_clk : cpu_clk;
assign mem_rst = select_loader ? loader_rst : cpu_rst;
assign mem_en = select_loader ? loader_en : cpu_en;
assign mem_we = select_loader ? loader_we : cpu_we;
assign mem_addr = select_loader ? loader_addr : cpu_addr;
assign mem_din = select_loader ? loader_din : cpu_din;

assign cpu_dout = mem_dout;
assign loader_dout = mem_dout;

endmodule
