// Generator : SpinalHDL v1.2.2    git head : 3159d9865a8de00378e0b0405c338a97c2f5a601
// Date      : 11/08/2026, 18:05:09
// Component : VexRiscvAxi4


`define Src1CtrlEnum_defaultEncoding_type [1:0]
`define Src1CtrlEnum_defaultEncoding_RS 2'b00
`define Src1CtrlEnum_defaultEncoding_IMU 2'b01
`define Src1CtrlEnum_defaultEncoding_PC_INCREMENT 2'b10
`define Src1CtrlEnum_defaultEncoding_URS1 2'b11

`define AluBitwiseCtrlEnum_defaultEncoding_type [1:0]
`define AluBitwiseCtrlEnum_defaultEncoding_XOR_1 2'b00
`define AluBitwiseCtrlEnum_defaultEncoding_OR_1 2'b01
`define AluBitwiseCtrlEnum_defaultEncoding_AND_1 2'b10
`define AluBitwiseCtrlEnum_defaultEncoding_SRC1 2'b11

`define EnvCtrlEnum_defaultEncoding_type [0:0]
`define EnvCtrlEnum_defaultEncoding_NONE 1'b0
`define EnvCtrlEnum_defaultEncoding_XRET 1'b1

`define JtagState_defaultEncoding_type [3:0]
`define JtagState_defaultEncoding_RESET 4'b0000
`define JtagState_defaultEncoding_IDLE 4'b0001
`define JtagState_defaultEncoding_IR_SELECT 4'b0010
`define JtagState_defaultEncoding_IR_CAPTURE 4'b0011
`define JtagState_defaultEncoding_IR_SHIFT 4'b0100
`define JtagState_defaultEncoding_IR_EXIT1 4'b0101
`define JtagState_defaultEncoding_IR_PAUSE 4'b0110
`define JtagState_defaultEncoding_IR_EXIT2 4'b0111
`define JtagState_defaultEncoding_IR_UPDATE 4'b1000
`define JtagState_defaultEncoding_DR_SELECT 4'b1001
`define JtagState_defaultEncoding_DR_CAPTURE 4'b1010
`define JtagState_defaultEncoding_DR_SHIFT 4'b1011
`define JtagState_defaultEncoding_DR_EXIT1 4'b1100
`define JtagState_defaultEncoding_DR_PAUSE 4'b1101
`define JtagState_defaultEncoding_DR_EXIT2 4'b1110
`define JtagState_defaultEncoding_DR_UPDATE 4'b1111

`define Src2CtrlEnum_defaultEncoding_type [1:0]
`define Src2CtrlEnum_defaultEncoding_RS 2'b00
`define Src2CtrlEnum_defaultEncoding_IMI 2'b01
`define Src2CtrlEnum_defaultEncoding_IMS 2'b10
`define Src2CtrlEnum_defaultEncoding_PC 2'b11

`define AluCtrlEnum_defaultEncoding_type [1:0]
`define AluCtrlEnum_defaultEncoding_ADD_SUB 2'b00
`define AluCtrlEnum_defaultEncoding_SLT_SLTU 2'b01
`define AluCtrlEnum_defaultEncoding_BITWISE 2'b10

`define BranchCtrlEnum_defaultEncoding_type [1:0]
`define BranchCtrlEnum_defaultEncoding_INC 2'b00
`define BranchCtrlEnum_defaultEncoding_B 2'b01
`define BranchCtrlEnum_defaultEncoding_JAL 2'b10
`define BranchCtrlEnum_defaultEncoding_JALR 2'b11

`define DataCacheCpuCmdKind_defaultEncoding_type [0:0]
`define DataCacheCpuCmdKind_defaultEncoding_MEMORY 1'b0
`define DataCacheCpuCmdKind_defaultEncoding_MANAGMENT 1'b1

`define ShiftCtrlEnum_defaultEncoding_type [1:0]
`define ShiftCtrlEnum_defaultEncoding_DISABLE_1 2'b00
`define ShiftCtrlEnum_defaultEncoding_SLL_1 2'b01
`define ShiftCtrlEnum_defaultEncoding_SRL_1 2'b10
`define ShiftCtrlEnum_defaultEncoding_SRA_1 2'b11

module BufferCC (
      input   io_dataIn,
      output  io_dataOut,
      input   clk,
      input   reset);
  reg  buffers_0;
  reg  buffers_1;
  assign io_dataOut = buffers_1;
  always @ (posedge clk) begin
    buffers_0 <= io_dataIn;
    buffers_1 <= buffers_0;
  end

endmodule

module FlowCCByToggle (
      input   io_input_valid,
      input   io_input_payload_last,
      input  [0:0] io_input_payload_fragment,
      output  io_output_valid,
      output  io_output_payload_last,
      output [0:0] io_output_payload_fragment,
      input   io_jtag_tck,
      input   clk,
      input   reset);
  wire  _zz_1_;
  wire  outHitSignal;
  reg  inputArea_target = 0;
  reg  inputArea_data_last;
  reg [0:0] inputArea_data_fragment;
  wire  outputArea_target;
  reg  outputArea_hit;
  wire  outputArea_flow_valid;
  wire  outputArea_flow_payload_last;
  wire [0:0] outputArea_flow_payload_fragment;
  reg  outputArea_flow_m2sPipe_valid;
  reg  outputArea_flow_m2sPipe_payload_last;
  reg [0:0] outputArea_flow_m2sPipe_payload_fragment;
  BufferCC bufferCC_1_ ( 
    .io_dataIn(inputArea_target),
    .io_dataOut(_zz_1_),
    .clk(clk),
    .reset(reset) 
  );
  assign outputArea_target = _zz_1_;
  assign outputArea_flow_valid = (outputArea_target != outputArea_hit);
  assign outputArea_flow_payload_last = inputArea_data_last;
  assign outputArea_flow_payload_fragment = inputArea_data_fragment;
  assign io_output_valid = outputArea_flow_m2sPipe_valid;
  assign io_output_payload_last = outputArea_flow_m2sPipe_payload_last;
  assign io_output_payload_fragment = outputArea_flow_m2sPipe_payload_fragment;
  always @ (posedge io_jtag_tck) begin
    if(io_input_valid)begin
      inputArea_target <= (! inputArea_target);
      inputArea_data_last <= io_input_payload_last;
      inputArea_data_fragment <= io_input_payload_fragment;
    end
  end

  always @ (posedge clk) begin
    outputArea_hit <= outputArea_target;
    if(outputArea_flow_valid)begin
      outputArea_flow_m2sPipe_payload_last <= outputArea_flow_payload_last;
      outputArea_flow_m2sPipe_payload_fragment <= outputArea_flow_payload_fragment;
    end
  end

  always @ (posedge clk or posedge reset) begin
    if (reset) begin
      outputArea_flow_m2sPipe_valid <= 1'b0;
    end else begin
      outputArea_flow_m2sPipe_valid <= outputArea_flow_valid;
    end
  end

endmodule

module InstructionCache (
      input   io_flush_cmd_valid,
      output  io_flush_cmd_ready,
      output  io_flush_rsp,
      input   io_cpu_prefetch_isValid,
      output reg  io_cpu_prefetch_haltIt,
      input  [31:0] io_cpu_prefetch_pc,
      input   io_cpu_fetch_isValid,
      input   io_cpu_fetch_isStuck,
      input   io_cpu_fetch_isRemoved,
      input  [31:0] io_cpu_fetch_pc,
      output [31:0] io_cpu_fetch_data,
      output  io_cpu_fetch_mmuBus_cmd_isValid,
      output [31:0] io_cpu_fetch_mmuBus_cmd_virtualAddress,
      output  io_cpu_fetch_mmuBus_cmd_bypassTranslation,
      input  [31:0] io_cpu_fetch_mmuBus_rsp_physicalAddress,
      input   io_cpu_fetch_mmuBus_rsp_isIoAccess,
      input   io_cpu_fetch_mmuBus_rsp_allowRead,
      input   io_cpu_fetch_mmuBus_rsp_allowWrite,
      input   io_cpu_fetch_mmuBus_rsp_allowExecute,
      input   io_cpu_fetch_mmuBus_rsp_allowUser,
      input   io_cpu_fetch_mmuBus_rsp_miss,
      input   io_cpu_fetch_mmuBus_rsp_hit,
      output  io_cpu_fetch_mmuBus_end,
      output [31:0] io_cpu_fetch_physicalAddress,
      input   io_cpu_decode_isValid,
      input   io_cpu_decode_isStuck,
      input  [31:0] io_cpu_decode_pc,
      output [31:0] io_cpu_decode_physicalAddress,
      output [31:0] io_cpu_decode_data,
      output  io_cpu_decode_cacheMiss,
      output  io_cpu_decode_error,
      output  io_cpu_decode_mmuMiss,
      output  io_cpu_decode_illegalAccess,
      input   io_cpu_decode_isUser,
      input   io_cpu_fill_valid,
      input  [31:0] io_cpu_fill_payload,
      output  io_mem_cmd_valid,
      input   io_mem_cmd_ready,
      output [31:0] io_mem_cmd_payload_address,
      output [2:0] io_mem_cmd_payload_size,
      input   io_mem_rsp_valid,
      input  [31:0] io_mem_rsp_payload_data,
      input   io_mem_rsp_payload_error,
      input   clk,
      input   reset);
  reg [21:0] _zz_12_;
  reg [31:0] _zz_13_;
  wire  _zz_14_;
  wire [0:0] _zz_15_;
  wire [0:0] _zz_16_;
  wire [21:0] _zz_17_;
  reg  _zz_1_;
  reg  _zz_2_;
  reg  lineLoader_fire;
  reg  lineLoader_valid;
  reg [31:0] lineLoader_address;
  reg  lineLoader_hadError;
  reg [7:0] lineLoader_flushCounter;
  reg  _zz_3_;
  reg  lineLoader_flushFromInterface;
  wire  _zz_4_;
  reg  _zz_4__regNext;
  reg  lineLoader_cmdSent;
  reg  lineLoader_wayToAllocate_willIncrement;
  wire  lineLoader_wayToAllocate_willClear;
  wire  lineLoader_wayToAllocate_willOverflowIfInc;
  wire  lineLoader_wayToAllocate_willOverflow;
  reg [2:0] lineLoader_wordIndex;
  wire  lineLoader_write_tag_0_valid;
  wire [6:0] lineLoader_write_tag_0_payload_address;
  wire  lineLoader_write_tag_0_payload_data_valid;
  wire  lineLoader_write_tag_0_payload_data_error;
  wire [19:0] lineLoader_write_tag_0_payload_data_address;
  wire  lineLoader_write_data_0_valid;
  wire [9:0] lineLoader_write_data_0_payload_address;
  wire [31:0] lineLoader_write_data_0_payload_data;
  wire  _zz_5_;
  wire [6:0] _zz_6_;
  wire  _zz_7_;
  wire  fetchStage_read_waysValues_0_tag_valid;
  wire  fetchStage_read_waysValues_0_tag_error;
  wire [19:0] fetchStage_read_waysValues_0_tag_address;
  wire [21:0] _zz_8_;
  wire [9:0] _zz_9_;
  wire  _zz_10_;
  wire [31:0] fetchStage_read_waysValues_0_data;
  reg [31:0] decodeStage_mmuRsp_physicalAddress;
  reg  decodeStage_mmuRsp_isIoAccess;
  reg  decodeStage_mmuRsp_allowRead;
  reg  decodeStage_mmuRsp_allowWrite;
  reg  decodeStage_mmuRsp_allowExecute;
  reg  decodeStage_mmuRsp_allowUser;
  reg  decodeStage_mmuRsp_miss;
  reg  decodeStage_mmuRsp_hit;
  reg  decodeStage_hit_0_valid;
  reg  decodeStage_hit_0_error;
  reg [19:0] decodeStage_hit_0_address;
  wire  decodeStage_hit_hits_0;
  wire  decodeStage_hit_valid;
  wire  decodeStage_hit_error;
  reg [31:0] _zz_11_;
  wire [31:0] decodeStage_hit_data;
  wire [31:0] decodeStage_hit_word;
  reg [21:0] ways_0_tags [0:127];
  reg [31:0] ways_0_datas [0:1023];
  assign _zz_14_ = (! lineLoader_flushCounter[7]);
  assign _zz_15_ = _zz_8_[0 : 0];
  assign _zz_16_ = _zz_8_[1 : 1];
  assign _zz_17_ = {lineLoader_write_tag_0_payload_data_address,{lineLoader_write_tag_0_payload_data_error,lineLoader_write_tag_0_payload_data_valid}};
  always @ (posedge clk) begin
    if(_zz_2_) begin
      ways_0_tags[lineLoader_write_tag_0_payload_address] <= _zz_17_;
    end
  end

  always @ (posedge clk) begin
    if(_zz_7_) begin
      _zz_12_ <= ways_0_tags[_zz_6_];
    end
  end

  always @ (posedge clk) begin
    if(_zz_1_) begin
      ways_0_datas[lineLoader_write_data_0_payload_address] <= lineLoader_write_data_0_payload_data;
    end
  end

  always @ (posedge clk) begin
    if(_zz_10_) begin
      _zz_13_ <= ways_0_datas[_zz_9_];
    end
  end

  always @ (*) begin
    _zz_1_ = 1'b0;
    if(lineLoader_write_data_0_valid)begin
      _zz_1_ = 1'b1;
    end
  end

  always @ (*) begin
    _zz_2_ = 1'b0;
    if(lineLoader_write_tag_0_valid)begin
      _zz_2_ = 1'b1;
    end
  end

  always @ (*) begin
    io_cpu_prefetch_haltIt = 1'b0;
    if(lineLoader_valid)begin
      io_cpu_prefetch_haltIt = 1'b1;
    end
    if(_zz_14_)begin
      io_cpu_prefetch_haltIt = 1'b1;
    end
    if((! _zz_3_))begin
      io_cpu_prefetch_haltIt = 1'b1;
    end
    if(io_flush_cmd_valid)begin
      io_cpu_prefetch_haltIt = 1'b1;
    end
  end

  always @ (*) begin
    lineLoader_fire = 1'b0;
    if(io_mem_rsp_valid)begin
      if((lineLoader_wordIndex == (3'b111)))begin
        lineLoader_fire = 1'b1;
      end
    end
  end

  assign io_flush_cmd_ready = (! (lineLoader_valid || io_cpu_fetch_isValid));
  assign _zz_4_ = lineLoader_flushCounter[7];
  assign io_flush_rsp = ((_zz_4_ && (! _zz_4__regNext)) && lineLoader_flushFromInterface);
  assign io_mem_cmd_valid = (lineLoader_valid && (! lineLoader_cmdSent));
  assign io_mem_cmd_payload_address = {lineLoader_address[31 : 5],(5'b00000)};
  assign io_mem_cmd_payload_size = (3'b101);
  always @ (*) begin
    lineLoader_wayToAllocate_willIncrement = 1'b0;
    if(lineLoader_fire)begin
      lineLoader_wayToAllocate_willIncrement = 1'b1;
    end
  end

  assign lineLoader_wayToAllocate_willClear = 1'b0;
  assign lineLoader_wayToAllocate_willOverflowIfInc = 1'b1;
  assign lineLoader_wayToAllocate_willOverflow = (lineLoader_wayToAllocate_willOverflowIfInc && lineLoader_wayToAllocate_willIncrement);
  assign _zz_5_ = 1'b1;
  assign lineLoader_write_tag_0_valid = ((_zz_5_ && lineLoader_fire) || (! lineLoader_flushCounter[7]));
  assign lineLoader_write_tag_0_payload_address = (lineLoader_flushCounter[7] ? lineLoader_address[11 : 5] : lineLoader_flushCounter[6 : 0]);
  assign lineLoader_write_tag_0_payload_data_valid = lineLoader_flushCounter[7];
  assign lineLoader_write_tag_0_payload_data_error = (lineLoader_hadError || io_mem_rsp_payload_error);
  assign lineLoader_write_tag_0_payload_data_address = lineLoader_address[31 : 12];
  assign lineLoader_write_data_0_valid = (io_mem_rsp_valid && _zz_5_);
  assign lineLoader_write_data_0_payload_address = {lineLoader_address[11 : 5],lineLoader_wordIndex};
  assign lineLoader_write_data_0_payload_data = io_mem_rsp_payload_data;
  assign _zz_6_ = io_cpu_prefetch_pc[11 : 5];
  assign _zz_7_ = (! io_cpu_fetch_isStuck);
  assign _zz_8_ = _zz_12_;
  assign fetchStage_read_waysValues_0_tag_valid = _zz_15_[0];
  assign fetchStage_read_waysValues_0_tag_error = _zz_16_[0];
  assign fetchStage_read_waysValues_0_tag_address = _zz_8_[21 : 2];
  assign _zz_9_ = io_cpu_prefetch_pc[11 : 2];
  assign _zz_10_ = (! io_cpu_fetch_isStuck);
  assign fetchStage_read_waysValues_0_data = _zz_13_;
  assign io_cpu_fetch_data = fetchStage_read_waysValues_0_data[31 : 0];
  assign io_cpu_fetch_mmuBus_cmd_isValid = io_cpu_fetch_isValid;
  assign io_cpu_fetch_mmuBus_cmd_virtualAddress = io_cpu_fetch_pc;
  assign io_cpu_fetch_mmuBus_cmd_bypassTranslation = 1'b0;
  assign io_cpu_fetch_mmuBus_end = ((! io_cpu_fetch_isStuck) || io_cpu_fetch_isRemoved);
  assign io_cpu_fetch_physicalAddress = io_cpu_fetch_mmuBus_rsp_physicalAddress;
  assign decodeStage_hit_hits_0 = (decodeStage_hit_0_valid && (decodeStage_hit_0_address == decodeStage_mmuRsp_physicalAddress[31 : 12]));
  assign decodeStage_hit_valid = (decodeStage_hit_hits_0 != (1'b0));
  assign decodeStage_hit_error = decodeStage_hit_0_error;
  assign decodeStage_hit_data = _zz_11_;
  assign decodeStage_hit_word = decodeStage_hit_data[31 : 0];
  assign io_cpu_decode_data = decodeStage_hit_word;
  assign io_cpu_decode_cacheMiss = (! decodeStage_hit_valid);
  assign io_cpu_decode_error = decodeStage_hit_error;
  assign io_cpu_decode_mmuMiss = decodeStage_mmuRsp_miss;
  assign io_cpu_decode_illegalAccess = ((! decodeStage_mmuRsp_allowExecute) || (io_cpu_decode_isUser && (! decodeStage_mmuRsp_allowUser)));
  assign io_cpu_decode_physicalAddress = decodeStage_mmuRsp_physicalAddress;
  always @ (posedge clk or posedge reset) begin
    if (reset) begin
      lineLoader_valid <= 1'b0;
      lineLoader_hadError <= 1'b0;
      lineLoader_flushCounter <= (8'b00000000);
      lineLoader_flushFromInterface <= 1'b0;
      lineLoader_cmdSent <= 1'b0;
      lineLoader_wordIndex <= (3'b000);
    end else begin
      if(lineLoader_fire)begin
        lineLoader_valid <= 1'b0;
      end
      if(lineLoader_fire)begin
        lineLoader_hadError <= 1'b0;
      end
      if(io_cpu_fill_valid)begin
        lineLoader_valid <= 1'b1;
      end
      if(_zz_14_)begin
        lineLoader_flushCounter <= (lineLoader_flushCounter + (8'b00000001));
      end
      if(io_flush_cmd_valid)begin
        if(io_flush_cmd_ready)begin
          lineLoader_flushCounter <= (8'b00000000);
          lineLoader_flushFromInterface <= 1'b1;
        end
      end
      if((io_mem_cmd_valid && io_mem_cmd_ready))begin
        lineLoader_cmdSent <= 1'b1;
      end
      if(lineLoader_fire)begin
        lineLoader_cmdSent <= 1'b0;
      end
      if(io_mem_rsp_valid)begin
        lineLoader_wordIndex <= (lineLoader_wordIndex + (3'b001));
        if(io_mem_rsp_payload_error)begin
          lineLoader_hadError <= 1'b1;
        end
      end
    end
  end

  always @ (posedge clk) begin
    if(io_cpu_fill_valid)begin
      lineLoader_address <= io_cpu_fill_payload;
    end
    _zz_3_ <= lineLoader_flushCounter[7];
    _zz_4__regNext <= _zz_4_;
    if((! io_cpu_decode_isStuck))begin
      decodeStage_mmuRsp_physicalAddress <= io_cpu_fetch_mmuBus_rsp_physicalAddress;
      decodeStage_mmuRsp_isIoAccess <= io_cpu_fetch_mmuBus_rsp_isIoAccess;
      decodeStage_mmuRsp_allowRead <= io_cpu_fetch_mmuBus_rsp_allowRead;
      decodeStage_mmuRsp_allowWrite <= io_cpu_fetch_mmuBus_rsp_allowWrite;
      decodeStage_mmuRsp_allowExecute <= io_cpu_fetch_mmuBus_rsp_allowExecute;
      decodeStage_mmuRsp_allowUser <= io_cpu_fetch_mmuBus_rsp_allowUser;
      decodeStage_mmuRsp_miss <= io_cpu_fetch_mmuBus_rsp_miss;
      decodeStage_mmuRsp_hit <= io_cpu_fetch_mmuBus_rsp_hit;
    end
    if((! io_cpu_decode_isStuck))begin
      decodeStage_hit_0_valid <= fetchStage_read_waysValues_0_tag_valid;
      decodeStage_hit_0_error <= fetchStage_read_waysValues_0_tag_error;
      decodeStage_hit_0_address <= fetchStage_read_waysValues_0_tag_address;
    end
    if((! io_cpu_decode_isStuck))begin
      _zz_11_ <= fetchStage_read_waysValues_0_data;
    end
  end

endmodule

module DataCache (
      input   io_cpu_execute_isValid,
      input   io_cpu_execute_isStuck,
      input  `DataCacheCpuCmdKind_defaultEncoding_type io_cpu_execute_args_kind,
      input   io_cpu_execute_args_wr,
      input  [31:0] io_cpu_execute_args_address,
      input  [31:0] io_cpu_execute_args_data,
      input  [1:0] io_cpu_execute_args_size,
      input   io_cpu_execute_args_forceUncachedAccess,
      input   io_cpu_execute_args_clean,
      input   io_cpu_execute_args_invalidate,
      input   io_cpu_execute_args_way,
      input   io_cpu_memory_isValid,
      input   io_cpu_memory_isStuck,
      input   io_cpu_memory_isRemoved,
      output  io_cpu_memory_haltIt,
      output  io_cpu_memory_mmuBus_cmd_isValid,
      output [31:0] io_cpu_memory_mmuBus_cmd_virtualAddress,
      output  io_cpu_memory_mmuBus_cmd_bypassTranslation,
      input  [31:0] io_cpu_memory_mmuBus_rsp_physicalAddress,
      input   io_cpu_memory_mmuBus_rsp_isIoAccess,
      input   io_cpu_memory_mmuBus_rsp_allowRead,
      input   io_cpu_memory_mmuBus_rsp_allowWrite,
      input   io_cpu_memory_mmuBus_rsp_allowExecute,
      input   io_cpu_memory_mmuBus_rsp_allowUser,
      input   io_cpu_memory_mmuBus_rsp_miss,
      input   io_cpu_memory_mmuBus_rsp_hit,
      output  io_cpu_memory_mmuBus_end,
      input   io_cpu_writeBack_isValid,
      input   io_cpu_writeBack_isStuck,
      input   io_cpu_writeBack_isUser,
      output reg  io_cpu_writeBack_haltIt,
      output [31:0] io_cpu_writeBack_data,
      output reg  io_cpu_writeBack_mmuMiss,
      output reg  io_cpu_writeBack_illegalAccess,
      output reg  io_cpu_writeBack_unalignedAccess,
      output  io_cpu_writeBack_accessError,
      output [31:0] io_cpu_writeBack_badAddr,
      output reg  io_mem_cmd_valid,
      input   io_mem_cmd_ready,
      output reg  io_mem_cmd_payload_wr,
      output reg [31:0] io_mem_cmd_payload_address,
      output reg [31:0] io_mem_cmd_payload_data,
      output reg [3:0] io_mem_cmd_payload_mask,
      output reg [2:0] io_mem_cmd_payload_length,
      output reg  io_mem_cmd_payload_last,
      input   io_mem_rsp_valid,
      input  [31:0] io_mem_rsp_payload_data,
      input   io_mem_rsp_payload_error,
      input   clk,
      input   reset);
  reg [21:0] _zz_35_;
  reg [31:0] _zz_36_;
  reg [31:0] _zz_37_;
  wire  _zz_38_;
  wire  _zz_39_;
  wire  _zz_40_;
  wire  _zz_41_;
  wire  _zz_42_;
  wire  _zz_43_;
  wire  _zz_44_;
  wire [0:0] _zz_45_;
  wire [0:0] _zz_46_;
  wire [2:0] _zz_47_;
  wire [0:0] _zz_48_;
  wire [2:0] _zz_49_;
  wire [0:0] _zz_50_;
  wire [2:0] _zz_51_;
  wire [21:0] _zz_52_;
  reg  _zz_1_;
  reg  _zz_2_;
  reg  _zz_3_;
  wire  haltCpu;
  reg  tagsReadCmd_valid;
  reg [6:0] tagsReadCmd_payload;
  reg  tagsWriteCmd_valid;
  reg [6:0] tagsWriteCmd_payload_address;
  reg  tagsWriteCmd_payload_data_used;
  reg  tagsWriteCmd_payload_data_dirty;
  reg [19:0] tagsWriteCmd_payload_data_address;
  reg  tagsWriteLastCmd_valid;
  reg [6:0] tagsWriteLastCmd_payload_address;
  reg  tagsWriteLastCmd_payload_data_used;
  reg  tagsWriteLastCmd_payload_data_dirty;
  reg [19:0] tagsWriteLastCmd_payload_data_address;
  reg  dataReadCmd_valid;
  reg [9:0] dataReadCmd_payload;
  reg  dataWriteCmd_valid;
  reg [9:0] dataWriteCmd_payload_address;
  reg [31:0] dataWriteCmd_payload_data;
  reg [3:0] dataWriteCmd_payload_mask;
  reg [6:0] way_tagReadRspOneAddress;
  wire [21:0] _zz_4_;
  wire  _zz_5_;
  reg  tagsWriteCmd_valid_regNextWhen;
  reg [6:0] tagsWriteCmd_payload_address_regNextWhen;
  reg  tagsWriteCmd_payload_data_regNextWhen_used;
  reg  tagsWriteCmd_payload_data_regNextWhen_dirty;
  reg [19:0] tagsWriteCmd_payload_data_regNextWhen_address;
  wire  _zz_6_;
  wire  way_tagReadRspOne_used;
  wire  way_tagReadRspOne_dirty;
  wire [19:0] way_tagReadRspOne_address;
  reg  way_dataReadRspOneKeepAddress;
  reg [9:0] way_dataReadRspOneAddress;
  wire [31:0] way_dataReadRspOneWithoutBypass;
  wire  _zz_7_;
  wire  _zz_8_;
  reg  dataWriteCmd_valid_regNextWhen;
  reg [9:0] dataWriteCmd_payload_address_regNextWhen;
  reg [31:0] _zz_9_;
  reg [3:0] _zz_10_;
  reg [31:0] way_dataReadRspOne;
  wire  _zz_11_;
  wire  way_tagReadRspTwoEnable;
  wire  _zz_12_;
  wire  way_tagReadRspTwoRegIn_used;
  wire  way_tagReadRspTwoRegIn_dirty;
  wire [19:0] way_tagReadRspTwoRegIn_address;
  reg  way_tagReadRspTwo_used;
  reg  way_tagReadRspTwo_dirty;
  reg [19:0] way_tagReadRspTwo_address;
  wire  way_dataReadRspTwoEnable;
  reg [9:0] way_dataReadRspOneAddress_regNextWhen;
  wire  _zz_13_;
  wire  _zz_14_;
  reg [7:0] _zz_15_;
  reg [7:0] _zz_16_;
  reg [7:0] _zz_17_;
  reg [7:0] _zz_18_;
  wire [31:0] way_dataReadRspTwo;
  wire  cpuMemoryStageNeedReadData;
  reg  victim_requestIn_valid;
  wire  victim_requestIn_ready;
  reg [31:0] victim_requestIn_payload_address;
  wire  victim_requestIn_halfPipe_valid;
  reg  victim_requestIn_halfPipe_ready;
  wire [31:0] victim_requestIn_halfPipe_payload_address;
  reg  _zz_19_;
  reg  _zz_20_;
  reg [31:0] _zz_21_;
  reg [3:0] victim_readLineCmdCounter;
  reg  victim_dataReadCmdOccure;
  reg  victim_dataReadRestored;
  reg [3:0] victim_readLineRspCounter;
  reg  victim_dataReadCmdOccure_delay_1;
  reg [3:0] victim_bufferReadCounter;
  wire  victim_bufferReadStream_valid;
  wire  victim_bufferReadStream_ready;
  wire [2:0] victim_bufferReadStream_payload;
  wire  _zz_22_;
  wire  _zz_23_;
  reg  _zz_24_;
  wire  _zz_25_;
  reg  _zz_26_;
  reg  _zz_27_;
  reg [31:0] _zz_28_;
  reg [2:0] victim_bufferReadedCounter;
  reg  victim_memCmdAlreadyUsed;
  wire  victim_counter_willIncrement;
  wire  victim_counter_willClear;
  reg [2:0] victim_counter_valueNext;
  reg [2:0] victim_counter_value;
  wire  victim_counter_willOverflowIfInc;
  wire  victim_counter_willOverflow;
  reg `DataCacheCpuCmdKind_defaultEncoding_type stageA_request_kind;
  reg  stageA_request_wr;
  reg [31:0] stageA_request_address;
  reg [31:0] stageA_request_data;
  reg [1:0] stageA_request_size;
  reg  stageA_request_forceUncachedAccess;
  reg  stageA_request_clean;
  reg  stageA_request_invalidate;
  reg  stageA_request_way;
  reg `DataCacheCpuCmdKind_defaultEncoding_type stageB_request_kind;
  reg  stageB_request_wr;
  reg [31:0] stageB_request_address;
  reg [31:0] stageB_request_data;
  reg [1:0] stageB_request_size;
  reg  stageB_request_forceUncachedAccess;
  reg  stageB_request_clean;
  reg  stageB_request_invalidate;
  reg  stageB_request_way;
  reg [31:0] stageB_mmuRsp_baseAddress;
  reg  stageB_mmuRsp_isIoAccess;
  reg  stageB_mmuRsp_allowRead;
  reg  stageB_mmuRsp_allowWrite;
  reg  stageB_mmuRsp_allowExecute;
  reg  stageB_mmuRsp_allowUser;
  reg  stageB_mmuRsp_miss;
  reg  stageB_mmuRsp_hit;
  reg  stageB_waysHit;
  reg  stageB_loaderValid;
  reg  stageB_loaderReady;
  reg  stageB_loadingDone;
  reg  stageB_delayedIsStuck;
  reg  stageB_delayedWaysHitValid;
  reg  stageB_victimNotSent;
  reg  stageB_loadingNotDone;
  reg [3:0] _zz_29_;
  wire [3:0] stageB_writeMask;
  reg  stageB_hadMemRspErrorReg;
  wire  stageB_hadMemRspError;
  reg  stageB_bootEvicts_valid;
  wire [4:0] _zz_30_;
  wire  _zz_31_;
  wire  _zz_32_;
  reg  _zz_33_;
  wire [4:0] _zz_34_;
  reg  loader_valid;
  reg  loader_memCmdSent;
  reg  loader_counter_willIncrement;
  wire  loader_counter_willClear;
  reg [2:0] loader_counter_valueNext;
  reg [2:0] loader_counter_value;
  wire  loader_counter_willOverflowIfInc;
  wire  loader_counter_willOverflow;
  reg [21:0] way_tags [0:127];
  reg [7:0] way_data_symbol0 [0:1023];
  reg [7:0] way_data_symbol1 [0:1023];
  reg [7:0] way_data_symbol2 [0:1023];
  reg [7:0] way_data_symbol3 [0:1023];
  reg [7:0] _zz_53_;
  reg [7:0] _zz_54_;
  reg [7:0] _zz_55_;
  reg [7:0] _zz_56_;
  reg [31:0] victim_buffer [0:7];
  assign _zz_38_ = (! victim_readLineCmdCounter[3]);
  assign _zz_39_ = ((! victim_memCmdAlreadyUsed) && io_mem_cmd_ready);
  assign _zz_40_ = (stageB_mmuRsp_baseAddress[11 : 5] != (7'b1111111));
  assign _zz_41_ = (! victim_requestIn_halfPipe_valid);
  assign _zz_42_ = (! _zz_33_);
  assign _zz_43_ = (! _zz_19_);
  assign _zz_44_ = (! io_cpu_writeBack_isStuck);
  assign _zz_45_ = _zz_4_[0 : 0];
  assign _zz_46_ = _zz_4_[1 : 1];
  assign _zz_47_ = victim_readLineRspCounter[2:0];
  assign _zz_48_ = victim_counter_willIncrement;
  assign _zz_49_ = {2'd0, _zz_48_};
  assign _zz_50_ = loader_counter_willIncrement;
  assign _zz_51_ = {2'd0, _zz_50_};
  assign _zz_52_ = {tagsWriteCmd_payload_data_address,{tagsWriteCmd_payload_data_dirty,tagsWriteCmd_payload_data_used}};
  always @ (posedge clk) begin
    if(_zz_3_) begin
      way_tags[tagsWriteCmd_payload_address] <= _zz_52_;
    end
  end

  always @ (posedge clk) begin
    if(tagsReadCmd_valid) begin
      _zz_35_ <= way_tags[tagsReadCmd_payload];
    end
  end

  always @ (*) begin
    _zz_36_ = {_zz_56_, _zz_55_, _zz_54_, _zz_53_};
  end
  always @ (posedge clk) begin
    if(dataWriteCmd_payload_mask[0] && _zz_2_) begin
      way_data_symbol0[dataWriteCmd_payload_address] <= dataWriteCmd_payload_data[7 : 0];
    end
    if(dataWriteCmd_payload_mask[1] && _zz_2_) begin
      way_data_symbol1[dataWriteCmd_payload_address] <= dataWriteCmd_payload_data[15 : 8];
    end
    if(dataWriteCmd_payload_mask[2] && _zz_2_) begin
      way_data_symbol2[dataWriteCmd_payload_address] <= dataWriteCmd_payload_data[23 : 16];
    end
    if(dataWriteCmd_payload_mask[3] && _zz_2_) begin
      way_data_symbol3[dataWriteCmd_payload_address] <= dataWriteCmd_payload_data[31 : 24];
    end
  end

  always @ (posedge clk) begin
    if(dataReadCmd_valid) begin
      _zz_53_ <= way_data_symbol0[dataReadCmd_payload];
      _zz_54_ <= way_data_symbol1[dataReadCmd_payload];
      _zz_55_ <= way_data_symbol2[dataReadCmd_payload];
      _zz_56_ <= way_data_symbol3[dataReadCmd_payload];
    end
  end

  always @ (posedge clk) begin
    if(_zz_1_) begin
      victim_buffer[_zz_47_] <= way_dataReadRspOneWithoutBypass;
    end
  end

  always @ (posedge clk) begin
    if(victim_bufferReadStream_ready) begin
      _zz_37_ <= victim_buffer[victim_bufferReadStream_payload];
    end
  end

  always @ (*) begin
    _zz_1_ = 1'b0;
    if(victim_dataReadCmdOccure_delay_1)begin
      _zz_1_ = 1'b1;
    end
  end

  always @ (*) begin
    _zz_2_ = 1'b0;
    if(dataWriteCmd_valid)begin
      _zz_2_ = 1'b1;
    end
  end

  always @ (*) begin
    _zz_3_ = 1'b0;
    if(tagsWriteCmd_valid)begin
      _zz_3_ = 1'b1;
    end
  end

  assign haltCpu = 1'b0;
  always @ (*) begin
    tagsReadCmd_valid = 1'b0;
    tagsReadCmd_payload = (7'bxxxxxxx);
    dataReadCmd_valid = 1'b0;
    dataReadCmd_payload = (10'bxxxxxxxxxx);
    way_dataReadRspOneKeepAddress = 1'b0;
    if((io_cpu_execute_isValid && (! io_cpu_execute_isStuck)))begin
      tagsReadCmd_valid = 1'b1;
      tagsReadCmd_payload = io_cpu_execute_args_address[11 : 5];
      dataReadCmd_valid = 1'b1;
      dataReadCmd_payload = io_cpu_execute_args_address[11 : 2];
    end
    victim_dataReadCmdOccure = 1'b0;
    if(victim_requestIn_halfPipe_valid)begin
      if(_zz_38_)begin
        victim_dataReadCmdOccure = 1'b1;
        dataReadCmd_valid = 1'b1;
        dataReadCmd_payload = {victim_requestIn_halfPipe_payload_address[11 : 5],victim_readLineCmdCounter[2 : 0]};
        way_dataReadRspOneKeepAddress = 1'b1;
      end else begin
        if(((! victim_dataReadRestored) && cpuMemoryStageNeedReadData))begin
          dataReadCmd_valid = 1'b1;
          dataReadCmd_payload = way_dataReadRspOneAddress;
        end
      end
    end
  end

  always @ (*) begin
    tagsWriteCmd_valid = 1'b0;
    tagsWriteCmd_payload_address = (7'bxxxxxxx);
    tagsWriteCmd_payload_data_used = 1'bx;
    tagsWriteCmd_payload_data_dirty = 1'bx;
    tagsWriteCmd_payload_data_address = (20'bxxxxxxxxxxxxxxxxxxxx);
    dataWriteCmd_valid = 1'b0;
    dataWriteCmd_payload_address = (10'bxxxxxxxxxx);
    dataWriteCmd_payload_data = (32'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx);
    dataWriteCmd_payload_mask = (4'bxxxx);
    io_mem_cmd_valid = 1'b0;
    io_mem_cmd_payload_wr = 1'bx;
    io_mem_cmd_payload_address = (32'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx);
    io_mem_cmd_payload_data = (32'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx);
    io_mem_cmd_payload_mask = (4'bxxxx);
    io_mem_cmd_payload_length = (3'bxxx);
    io_mem_cmd_payload_last = 1'bx;
    victim_requestIn_valid = 1'b0;
    victim_requestIn_payload_address = (32'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx);
    victim_requestIn_halfPipe_ready = 1'b0;
    _zz_26_ = 1'b0;
    if(_zz_25_)begin
      io_mem_cmd_valid = 1'b1;
      io_mem_cmd_payload_wr = 1'b1;
      io_mem_cmd_payload_address = {victim_requestIn_halfPipe_payload_address[31 : 5],(5'b00000)};
      io_mem_cmd_payload_length = (3'b111);
      io_mem_cmd_payload_data = _zz_28_;
      io_mem_cmd_payload_mask = (4'b1111);
      io_mem_cmd_payload_last = (victim_bufferReadedCounter == (3'b111));
      if(_zz_39_)begin
        _zz_26_ = 1'b1;
        if((victim_bufferReadedCounter == (3'b111)))begin
          victim_requestIn_halfPipe_ready = 1'b1;
        end
      end
    end
    stageB_loaderValid = 1'b0;
    io_cpu_writeBack_haltIt = io_cpu_writeBack_isValid;
    io_cpu_writeBack_mmuMiss = 1'b0;
    io_cpu_writeBack_illegalAccess = 1'b0;
    io_cpu_writeBack_unalignedAccess = 1'b0;
    if(stageB_bootEvicts_valid)begin
      tagsWriteCmd_valid = stageB_bootEvicts_valid;
      tagsWriteCmd_payload_address = stageB_mmuRsp_baseAddress[11 : 5];
      tagsWriteCmd_payload_data_used = 1'b0;
      if(_zz_40_)begin
        io_cpu_writeBack_haltIt = 1'b1;
      end
    end
    if(io_cpu_writeBack_isValid)begin
      io_cpu_writeBack_mmuMiss = stageB_mmuRsp_miss;
      case(stageB_request_kind)
        `DataCacheCpuCmdKind_defaultEncoding_MANAGMENT : begin
          if((stageB_delayedIsStuck && (! stageB_mmuRsp_miss)))begin
            if((stageB_delayedWaysHitValid || (stageB_request_way && way_tagReadRspTwo_used)))begin
              if((! (victim_requestIn_valid && (! victim_requestIn_ready))))begin
                io_cpu_writeBack_haltIt = 1'b0;
              end
              victim_requestIn_valid = (stageB_request_clean && way_tagReadRspTwo_dirty);
              tagsWriteCmd_valid = victim_requestIn_ready;
            end else begin
              io_cpu_writeBack_haltIt = 1'b0;
            end
          end
          victim_requestIn_payload_address = {{way_tagReadRspTwo_address,stageB_mmuRsp_baseAddress[11 : 5]},_zz_30_};
          tagsWriteCmd_payload_address = stageB_mmuRsp_baseAddress[11 : 5];
          tagsWriteCmd_payload_data_used = (! stageB_request_invalidate);
          tagsWriteCmd_payload_data_dirty = (! stageB_request_clean);
        end
        default : begin
          io_cpu_writeBack_illegalAccess = _zz_31_;
          io_cpu_writeBack_unalignedAccess = _zz_32_;
          if((((1'b0 || (! stageB_mmuRsp_miss)) && (! _zz_31_)) && (! _zz_32_)))begin
            if((stageB_request_forceUncachedAccess || stageB_mmuRsp_isIoAccess))begin
              if(_zz_41_)begin
                io_mem_cmd_payload_wr = stageB_request_wr;
                io_mem_cmd_payload_address = {stageB_mmuRsp_baseAddress[31 : 2],(2'b00)};
                io_mem_cmd_payload_mask = stageB_writeMask;
                io_mem_cmd_payload_data = stageB_request_data;
                io_mem_cmd_payload_length = (3'b000);
                io_mem_cmd_payload_last = 1'b1;
                if(_zz_42_)begin
                  io_mem_cmd_valid = 1'b1;
                end
                if((_zz_33_ && (io_mem_rsp_valid || stageB_request_wr)))begin
                  io_cpu_writeBack_haltIt = 1'b0;
                end
              end
            end else begin
              if((stageB_waysHit || (! stageB_loadingNotDone)))begin
                io_cpu_writeBack_haltIt = 1'b0;
                dataWriteCmd_valid = stageB_request_wr;
                dataWriteCmd_payload_address = stageB_mmuRsp_baseAddress[11 : 2];
                dataWriteCmd_payload_data = stageB_request_data;
                dataWriteCmd_payload_mask = stageB_writeMask;
                tagsWriteCmd_valid = ((! stageB_loadingNotDone) || stageB_request_wr);
                tagsWriteCmd_payload_address = stageB_mmuRsp_baseAddress[11 : 5];
                tagsWriteCmd_payload_data_used = 1'b1;
                tagsWriteCmd_payload_data_dirty = stageB_request_wr;
                tagsWriteCmd_payload_data_address = stageB_mmuRsp_baseAddress[31 : 12];
              end else begin
                stageB_loaderValid = (stageB_loadingNotDone && (! (stageB_victimNotSent && (victim_requestIn_halfPipe_valid && (! victim_requestIn_halfPipe_ready)))));
                victim_requestIn_valid = ((way_tagReadRspTwo_used && way_tagReadRspTwo_dirty) && stageB_victimNotSent);
                victim_requestIn_payload_address = {{way_tagReadRspTwo_address,stageB_mmuRsp_baseAddress[11 : 5]},_zz_34_};
              end
            end
          end
        end
      endcase
    end
    if((loader_valid && (! loader_memCmdSent)))begin
      io_mem_cmd_valid = 1'b1;
      io_mem_cmd_payload_wr = 1'b0;
      io_mem_cmd_payload_address = {stageB_mmuRsp_baseAddress[31 : 5],(5'b00000)};
      io_mem_cmd_payload_length = (3'b111);
      io_mem_cmd_payload_last = 1'b1;
    end
    loader_counter_willIncrement = 1'b0;
    if((loader_valid && io_mem_rsp_valid))begin
      dataWriteCmd_valid = 1'b1;
      dataWriteCmd_payload_address = {stageB_mmuRsp_baseAddress[11 : 5],loader_counter_value};
      dataWriteCmd_payload_data = io_mem_rsp_payload_data;
      dataWriteCmd_payload_mask = (4'b1111);
      loader_counter_willIncrement = 1'b1;
    end
  end

  assign _zz_4_ = _zz_35_;
  assign _zz_5_ = (tagsReadCmd_valid || (tagsWriteCmd_valid && (tagsWriteCmd_payload_address == way_tagReadRspOneAddress)));
  assign _zz_6_ = (tagsWriteCmd_valid_regNextWhen && (tagsWriteCmd_payload_address_regNextWhen == way_tagReadRspOneAddress));
  assign way_tagReadRspOne_used = (_zz_6_ ? tagsWriteCmd_payload_data_regNextWhen_used : _zz_45_[0]);
  assign way_tagReadRspOne_dirty = (_zz_6_ ? tagsWriteCmd_payload_data_regNextWhen_dirty : _zz_46_[0]);
  assign way_tagReadRspOne_address = (_zz_6_ ? tagsWriteCmd_payload_data_regNextWhen_address : _zz_4_[21 : 2]);
  assign way_dataReadRspOneWithoutBypass = _zz_36_;
  assign _zz_7_ = (dataWriteCmd_valid && (dataWriteCmd_payload_address == way_dataReadRspOneAddress));
  assign _zz_8_ = (dataReadCmd_valid || _zz_7_);
  assign _zz_11_ = (dataWriteCmd_valid_regNextWhen && (dataWriteCmd_payload_address_regNextWhen == way_dataReadRspOneAddress));
  always @ (*) begin
    way_dataReadRspOne[7 : 0] = ((_zz_11_ && _zz_10_[0]) ? _zz_9_[7 : 0] : way_dataReadRspOneWithoutBypass[7 : 0]);
    way_dataReadRspOne[15 : 8] = ((_zz_11_ && _zz_10_[1]) ? _zz_9_[15 : 8] : way_dataReadRspOneWithoutBypass[15 : 8]);
    way_dataReadRspOne[23 : 16] = ((_zz_11_ && _zz_10_[2]) ? _zz_9_[23 : 16] : way_dataReadRspOneWithoutBypass[23 : 16]);
    way_dataReadRspOne[31 : 24] = ((_zz_11_ && _zz_10_[3]) ? _zz_9_[31 : 24] : way_dataReadRspOneWithoutBypass[31 : 24]);
  end

  assign way_tagReadRspTwoEnable = (! io_cpu_writeBack_isStuck);
  assign _zz_12_ = (tagsWriteCmd_valid && (tagsWriteCmd_payload_address == way_tagReadRspOneAddress));
  assign way_tagReadRspTwoRegIn_used = (_zz_12_ ? tagsWriteCmd_payload_data_used : way_tagReadRspOne_used);
  assign way_tagReadRspTwoRegIn_dirty = (_zz_12_ ? tagsWriteCmd_payload_data_dirty : way_tagReadRspOne_dirty);
  assign way_tagReadRspTwoRegIn_address = (_zz_12_ ? tagsWriteCmd_payload_data_address : way_tagReadRspOne_address);
  assign way_dataReadRspTwoEnable = (! io_cpu_writeBack_isStuck);
  assign _zz_13_ = (dataWriteCmd_valid && (way_dataReadRspOneAddress == dataWriteCmd_payload_address));
  assign _zz_14_ = (dataWriteCmd_valid && (way_dataReadRspOneAddress_regNextWhen == dataWriteCmd_payload_address));
  assign way_dataReadRspTwo = {_zz_18_,{_zz_17_,{_zz_16_,_zz_15_}}};
  assign victim_requestIn_halfPipe_valid = _zz_19_;
  assign victim_requestIn_halfPipe_payload_address = _zz_21_;
  assign victim_requestIn_ready = _zz_20_;
  assign io_cpu_memory_haltIt = ((cpuMemoryStageNeedReadData && victim_requestIn_halfPipe_valid) && (! victim_dataReadRestored));
  assign victim_bufferReadStream_valid = (victim_bufferReadCounter < victim_readLineRspCounter);
  assign victim_bufferReadStream_payload = victim_bufferReadCounter[2:0];
  assign victim_bufferReadStream_ready = ((! _zz_22_) || _zz_23_);
  assign _zz_22_ = _zz_24_;
  assign _zz_23_ = ((1'b1 && (! _zz_25_)) || _zz_26_);
  assign _zz_25_ = _zz_27_;
  always @ (*) begin
    victim_memCmdAlreadyUsed = 1'b0;
    if((loader_valid && (! loader_memCmdSent)))begin
      victim_memCmdAlreadyUsed = 1'b1;
    end
  end

  assign victim_counter_willIncrement = 1'b0;
  assign victim_counter_willClear = 1'b0;
  assign victim_counter_willOverflowIfInc = (victim_counter_value == (3'b111));
  assign victim_counter_willOverflow = (victim_counter_willOverflowIfInc && victim_counter_willIncrement);
  always @ (*) begin
    victim_counter_valueNext = (victim_counter_value + _zz_49_);
    if(victim_counter_willClear)begin
      victim_counter_valueNext = (3'b000);
    end
  end

  assign io_cpu_memory_mmuBus_cmd_isValid = (io_cpu_memory_isValid && (stageA_request_kind == `DataCacheCpuCmdKind_defaultEncoding_MEMORY));
  assign io_cpu_memory_mmuBus_cmd_virtualAddress = stageA_request_address;
  assign io_cpu_memory_mmuBus_cmd_bypassTranslation = stageA_request_way;
  assign io_cpu_memory_mmuBus_end = ((! io_cpu_memory_isStuck) || io_cpu_memory_isRemoved);
  assign cpuMemoryStageNeedReadData = ((io_cpu_memory_isValid && (stageA_request_kind == `DataCacheCpuCmdKind_defaultEncoding_MEMORY)) && (! stageA_request_wr));
  always @ (*) begin
    stageB_loaderReady = 1'b0;
    if(loader_counter_willOverflow)begin
      stageB_loaderReady = 1'b1;
    end
  end

  always @ (*) begin
    case(stageB_request_size)
      2'b00 : begin
        _zz_29_ = (4'b0001);
      end
      2'b01 : begin
        _zz_29_ = (4'b0011);
      end
      default : begin
        _zz_29_ = (4'b1111);
      end
    endcase
  end

  assign stageB_writeMask = (_zz_29_ <<< stageB_mmuRsp_baseAddress[1 : 0]);
  assign stageB_hadMemRspError = ((io_mem_rsp_valid && io_mem_rsp_payload_error) || stageB_hadMemRspErrorReg);
  assign io_cpu_writeBack_accessError = (stageB_hadMemRspError && (! io_cpu_writeBack_haltIt));
  assign io_cpu_writeBack_badAddr = stageB_request_address;
  assign _zz_30_[4 : 0] = (5'b00000);
  assign _zz_31_ = (((stageB_request_wr && (! stageB_mmuRsp_allowWrite)) || ((! stageB_request_wr) && (! stageB_mmuRsp_allowRead))) || (io_cpu_writeBack_isUser && (! stageB_mmuRsp_allowUser)));
  assign _zz_32_ = (((stageB_request_size == (2'b10)) && (stageB_mmuRsp_baseAddress[1 : 0] != (2'b00))) || ((stageB_request_size == (2'b01)) && (stageB_mmuRsp_baseAddress[0 : 0] != (1'b0))));
  assign _zz_34_[4 : 0] = (5'b00000);
  assign io_cpu_writeBack_data = ((stageB_request_forceUncachedAccess || stageB_mmuRsp_isIoAccess) ? io_mem_rsp_payload_data : way_dataReadRspTwo);
  assign loader_counter_willClear = 1'b0;
  assign loader_counter_willOverflowIfInc = (loader_counter_value == (3'b111));
  assign loader_counter_willOverflow = (loader_counter_willOverflowIfInc && loader_counter_willIncrement);
  always @ (*) begin
    loader_counter_valueNext = (loader_counter_value + _zz_51_);
    if(loader_counter_willClear)begin
      loader_counter_valueNext = (3'b000);
    end
  end

  always @ (posedge clk) begin
    tagsWriteLastCmd_valid <= tagsWriteCmd_valid;
    tagsWriteLastCmd_payload_address <= tagsWriteCmd_payload_address;
    tagsWriteLastCmd_payload_data_used <= tagsWriteCmd_payload_data_used;
    tagsWriteLastCmd_payload_data_dirty <= tagsWriteCmd_payload_data_dirty;
    tagsWriteLastCmd_payload_data_address <= tagsWriteCmd_payload_data_address;
    if(tagsReadCmd_valid)begin
      way_tagReadRspOneAddress <= tagsReadCmd_payload;
    end
    if(_zz_5_)begin
      tagsWriteCmd_valid_regNextWhen <= tagsWriteCmd_valid;
    end
    if(_zz_5_)begin
      tagsWriteCmd_payload_address_regNextWhen <= tagsWriteCmd_payload_address;
    end
    if(_zz_5_)begin
      tagsWriteCmd_payload_data_regNextWhen_used <= tagsWriteCmd_payload_data_used;
      tagsWriteCmd_payload_data_regNextWhen_dirty <= tagsWriteCmd_payload_data_dirty;
      tagsWriteCmd_payload_data_regNextWhen_address <= tagsWriteCmd_payload_data_address;
    end
    if((dataReadCmd_valid && (! way_dataReadRspOneKeepAddress)))begin
      way_dataReadRspOneAddress <= dataReadCmd_payload;
    end
    if(_zz_8_)begin
      dataWriteCmd_valid_regNextWhen <= dataWriteCmd_valid;
    end
    if(_zz_8_)begin
      dataWriteCmd_payload_address_regNextWhen <= dataWriteCmd_payload_address;
    end
    if((_zz_7_ && dataWriteCmd_payload_mask[0]))begin
      _zz_10_[0] <= 1'b1;
    end
    if(dataReadCmd_valid)begin
      _zz_10_[0] <= dataWriteCmd_payload_mask[0];
    end
    if((dataReadCmd_valid || (_zz_7_ && dataWriteCmd_payload_mask[0])))begin
      _zz_9_[7 : 0] <= dataWriteCmd_payload_data[7 : 0];
    end
    if((_zz_7_ && dataWriteCmd_payload_mask[1]))begin
      _zz_10_[1] <= 1'b1;
    end
    if(dataReadCmd_valid)begin
      _zz_10_[1] <= dataWriteCmd_payload_mask[1];
    end
    if((dataReadCmd_valid || (_zz_7_ && dataWriteCmd_payload_mask[1])))begin
      _zz_9_[15 : 8] <= dataWriteCmd_payload_data[15 : 8];
    end
    if((_zz_7_ && dataWriteCmd_payload_mask[2]))begin
      _zz_10_[2] <= 1'b1;
    end
    if(dataReadCmd_valid)begin
      _zz_10_[2] <= dataWriteCmd_payload_mask[2];
    end
    if((dataReadCmd_valid || (_zz_7_ && dataWriteCmd_payload_mask[2])))begin
      _zz_9_[23 : 16] <= dataWriteCmd_payload_data[23 : 16];
    end
    if((_zz_7_ && dataWriteCmd_payload_mask[3]))begin
      _zz_10_[3] <= 1'b1;
    end
    if(dataReadCmd_valid)begin
      _zz_10_[3] <= dataWriteCmd_payload_mask[3];
    end
    if((dataReadCmd_valid || (_zz_7_ && dataWriteCmd_payload_mask[3])))begin
      _zz_9_[31 : 24] <= dataWriteCmd_payload_data[31 : 24];
    end
    if(way_tagReadRspTwoEnable)begin
      way_tagReadRspTwo_used <= way_tagReadRspTwoRegIn_used;
      way_tagReadRspTwo_dirty <= way_tagReadRspTwoRegIn_dirty;
      way_tagReadRspTwo_address <= way_tagReadRspTwoRegIn_address;
    end
    if(way_dataReadRspTwoEnable)begin
      way_dataReadRspOneAddress_regNextWhen <= way_dataReadRspOneAddress;
    end
    if((way_dataReadRspTwoEnable || (_zz_14_ && dataWriteCmd_payload_mask[0])))begin
      _zz_15_ <= (((! way_dataReadRspTwoEnable) || (_zz_13_ && dataWriteCmd_payload_mask[0])) ? dataWriteCmd_payload_data[7 : 0] : way_dataReadRspOne[7 : 0]);
    end
    if((way_dataReadRspTwoEnable || (_zz_14_ && dataWriteCmd_payload_mask[1])))begin
      _zz_16_ <= (((! way_dataReadRspTwoEnable) || (_zz_13_ && dataWriteCmd_payload_mask[1])) ? dataWriteCmd_payload_data[15 : 8] : way_dataReadRspOne[15 : 8]);
    end
    if((way_dataReadRspTwoEnable || (_zz_14_ && dataWriteCmd_payload_mask[2])))begin
      _zz_17_ <= (((! way_dataReadRspTwoEnable) || (_zz_13_ && dataWriteCmd_payload_mask[2])) ? dataWriteCmd_payload_data[23 : 16] : way_dataReadRspOne[23 : 16]);
    end
    if((way_dataReadRspTwoEnable || (_zz_14_ && dataWriteCmd_payload_mask[3])))begin
      _zz_18_ <= (((! way_dataReadRspTwoEnable) || (_zz_13_ && dataWriteCmd_payload_mask[3])) ? dataWriteCmd_payload_data[31 : 24] : way_dataReadRspOne[31 : 24]);
    end
    if(_zz_43_)begin
      _zz_21_ <= victim_requestIn_payload_address;
    end
    if(_zz_23_)begin
      _zz_28_ <= _zz_37_;
    end
    if((! io_cpu_memory_isStuck))begin
      stageA_request_kind <= io_cpu_execute_args_kind;
      stageA_request_wr <= io_cpu_execute_args_wr;
      stageA_request_address <= io_cpu_execute_args_address;
      stageA_request_data <= io_cpu_execute_args_data;
      stageA_request_size <= io_cpu_execute_args_size;
      stageA_request_forceUncachedAccess <= io_cpu_execute_args_forceUncachedAccess;
      stageA_request_clean <= io_cpu_execute_args_clean;
      stageA_request_invalidate <= io_cpu_execute_args_invalidate;
      stageA_request_way <= io_cpu_execute_args_way;
    end
    if((! io_cpu_writeBack_isStuck))begin
      stageB_request_kind <= stageA_request_kind;
      stageB_request_wr <= stageA_request_wr;
      stageB_request_address <= stageA_request_address;
      stageB_request_data <= stageA_request_data;
      stageB_request_size <= stageA_request_size;
      stageB_request_forceUncachedAccess <= stageA_request_forceUncachedAccess;
      stageB_request_clean <= stageA_request_clean;
      stageB_request_invalidate <= stageA_request_invalidate;
      stageB_request_way <= stageA_request_way;
    end
    if(_zz_44_)begin
      stageB_mmuRsp_isIoAccess <= io_cpu_memory_mmuBus_rsp_isIoAccess;
      stageB_mmuRsp_allowRead <= io_cpu_memory_mmuBus_rsp_allowRead;
      stageB_mmuRsp_allowWrite <= io_cpu_memory_mmuBus_rsp_allowWrite;
      stageB_mmuRsp_allowExecute <= io_cpu_memory_mmuBus_rsp_allowExecute;
      stageB_mmuRsp_allowUser <= io_cpu_memory_mmuBus_rsp_allowUser;
      stageB_mmuRsp_miss <= io_cpu_memory_mmuBus_rsp_miss;
      stageB_mmuRsp_hit <= io_cpu_memory_mmuBus_rsp_hit;
    end
    if((! io_cpu_writeBack_isStuck))begin
      stageB_waysHit <= (way_tagReadRspTwoRegIn_used && (io_cpu_memory_mmuBus_rsp_physicalAddress[31 : 12] == way_tagReadRspTwoRegIn_address));
    end
    stageB_delayedIsStuck <= io_cpu_writeBack_isStuck;
    stageB_delayedWaysHitValid <= stageB_waysHit;
    if(!(! ((io_cpu_writeBack_isValid && (! io_cpu_writeBack_haltIt)) && io_cpu_writeBack_isStuck))) begin
      $display("ERROR writeBack stuck by another plugin is not allowed");
    end
  end

  always @ (posedge clk or posedge reset) begin
    if (reset) begin
      _zz_19_ <= 1'b0;
      _zz_20_ <= 1'b1;
      victim_readLineCmdCounter <= (4'b0000);
      victim_dataReadRestored <= 1'b0;
      victim_readLineRspCounter <= (4'b0000);
      victim_dataReadCmdOccure_delay_1 <= 1'b0;
      victim_bufferReadCounter <= (4'b0000);
      _zz_24_ <= 1'b0;
      _zz_27_ <= 1'b0;
      victim_bufferReadedCounter <= (3'b000);
      victim_counter_value <= (3'b000);
      stageB_loadingDone <= 1'b0;
      stageB_victimNotSent <= 1'b0;
      stageB_loadingNotDone <= 1'b0;
      stageB_hadMemRspErrorReg <= 1'b0;
      stageB_bootEvicts_valid <= 1'b1;
      stageB_mmuRsp_baseAddress <= (32'b00000000000000000000000000000000);
      loader_valid <= 1'b0;
      loader_memCmdSent <= 1'b0;
      loader_counter_value <= (3'b000);
    end else begin
      if(_zz_43_)begin
        _zz_19_ <= victim_requestIn_valid;
        _zz_20_ <= (! victim_requestIn_valid);
      end else begin
        _zz_19_ <= (! victim_requestIn_halfPipe_ready);
        _zz_20_ <= victim_requestIn_halfPipe_ready;
      end
      if(victim_requestIn_halfPipe_valid)begin
        if(_zz_38_)begin
          victim_readLineCmdCounter <= (victim_readLineCmdCounter + (4'b0001));
        end else begin
          victim_dataReadRestored <= 1'b1;
        end
      end
      if(victim_requestIn_halfPipe_ready)begin
        victim_dataReadRestored <= 1'b0;
      end
      victim_dataReadCmdOccure_delay_1 <= victim_dataReadCmdOccure;
      if(victim_dataReadCmdOccure_delay_1)begin
        victim_readLineRspCounter <= (victim_readLineRspCounter + (4'b0001));
      end
      if((victim_bufferReadStream_valid && victim_bufferReadStream_ready))begin
        victim_bufferReadCounter <= (victim_bufferReadCounter + (4'b0001));
      end
      if(_zz_23_)begin
        _zz_24_ <= 1'b0;
      end
      if(victim_bufferReadStream_ready)begin
        _zz_24_ <= victim_bufferReadStream_valid;
      end
      if(_zz_23_)begin
        _zz_27_ <= _zz_22_;
      end
      if(_zz_25_)begin
        if(_zz_39_)begin
          victim_bufferReadedCounter <= (victim_bufferReadedCounter + (3'b001));
        end
      end
      victim_counter_value <= victim_counter_valueNext;
      if(victim_requestIn_halfPipe_ready)begin
        victim_readLineCmdCounter[3] <= 1'b0;
        victim_readLineRspCounter[3] <= 1'b0;
        victim_bufferReadCounter[3] <= 1'b0;
      end
      if(_zz_44_)begin
        stageB_mmuRsp_baseAddress <= io_cpu_memory_mmuBus_rsp_physicalAddress;
      end
      stageB_loadingDone <= (stageB_loaderValid && stageB_loaderReady);
      if(victim_requestIn_ready)begin
        stageB_victimNotSent <= 1'b0;
      end
      if((! io_cpu_memory_isStuck))begin
        stageB_victimNotSent <= 1'b1;
      end
      if(stageB_loaderReady)begin
        stageB_loadingNotDone <= 1'b0;
      end
      if((! io_cpu_memory_isStuck))begin
        stageB_loadingNotDone <= 1'b1;
      end
      stageB_hadMemRspErrorReg <= (stageB_hadMemRspError && io_cpu_writeBack_haltIt);
      if(stageB_bootEvicts_valid)begin
        if(_zz_40_)begin
          stageB_mmuRsp_baseAddress[11 : 5] <= (stageB_mmuRsp_baseAddress[11 : 5] + (7'b0000001));
        end else begin
          stageB_bootEvicts_valid <= 1'b0;
        end
      end
      loader_valid <= stageB_loaderValid;
      if((loader_valid && io_mem_cmd_ready))begin
        loader_memCmdSent <= 1'b1;
      end
      loader_counter_value <= loader_counter_valueNext;
      if(loader_counter_willOverflow)begin
        loader_memCmdSent <= 1'b0;
        loader_valid <= 1'b0;
      end
    end
  end

  always @ (posedge clk or posedge reset) begin
    if (reset) begin
      _zz_33_ <= 1'b0;
    end else begin
      if(_zz_41_)begin
        if(_zz_42_)begin
          if(io_mem_cmd_ready)begin
            _zz_33_ <= 1'b1;
          end
        end
      end
      if((! io_cpu_writeBack_isStuck))begin
        _zz_33_ <= 1'b0;
      end
    end
  end

endmodule

module StreamFork (
      input   io_input_valid,
      output reg  io_input_ready,
      input   io_input_payload_wr,
      input  [31:0] io_input_payload_address,
      input  [31:0] io_input_payload_data,
      input  [3:0] io_input_payload_mask,
      input  [2:0] io_input_payload_length,
      input   io_input_payload_last,
      output  io_outputs_0_valid,
      input   io_outputs_0_ready,
      output  io_outputs_0_payload_wr,
      output [31:0] io_outputs_0_payload_address,
      output [31:0] io_outputs_0_payload_data,
      output [3:0] io_outputs_0_payload_mask,
      output [2:0] io_outputs_0_payload_length,
      output  io_outputs_0_payload_last,
      output  io_outputs_1_valid,
      input   io_outputs_1_ready,
      output  io_outputs_1_payload_wr,
      output [31:0] io_outputs_1_payload_address,
      output [31:0] io_outputs_1_payload_data,
      output [3:0] io_outputs_1_payload_mask,
      output [2:0] io_outputs_1_payload_length,
      output  io_outputs_1_payload_last,
      input   clk,
      input   reset);
  reg  linkEnable_0;
  reg  linkEnable_1;
  always @ (*) begin
    io_input_ready = 1'b1;
    if(((! io_outputs_0_ready) && linkEnable_0))begin
      io_input_ready = 1'b0;
    end
    if(((! io_outputs_1_ready) && linkEnable_1))begin
      io_input_ready = 1'b0;
    end
  end

  assign io_outputs_0_valid = (io_input_valid && linkEnable_0);
  assign io_outputs_0_payload_wr = io_input_payload_wr;
  assign io_outputs_0_payload_address = io_input_payload_address;
  assign io_outputs_0_payload_data = io_input_payload_data;
  assign io_outputs_0_payload_mask = io_input_payload_mask;
  assign io_outputs_0_payload_length = io_input_payload_length;
  assign io_outputs_0_payload_last = io_input_payload_last;
  assign io_outputs_1_valid = (io_input_valid && linkEnable_1);
  assign io_outputs_1_payload_wr = io_input_payload_wr;
  assign io_outputs_1_payload_address = io_input_payload_address;
  assign io_outputs_1_payload_data = io_input_payload_data;
  assign io_outputs_1_payload_mask = io_input_payload_mask;
  assign io_outputs_1_payload_length = io_input_payload_length;
  assign io_outputs_1_payload_last = io_input_payload_last;
  always @ (posedge clk or posedge reset) begin
    if (reset) begin
      linkEnable_0 <= 1'b1;
      linkEnable_1 <= 1'b1;
    end else begin
      if((io_outputs_0_valid && io_outputs_0_ready))begin
        linkEnable_0 <= 1'b0;
      end
      if((io_outputs_1_valid && io_outputs_1_ready))begin
        linkEnable_1 <= 1'b0;
      end
      if(io_input_ready)begin
        linkEnable_0 <= 1'b1;
        linkEnable_1 <= 1'b1;
      end
    end
  end

endmodule

module JtagBridge (
      input   io_jtag_tms,
      input   io_jtag_tdi,
      output reg  io_jtag_tdo,
      input   io_jtag_tck,
      output  io_remote_cmd_valid,
      input   io_remote_cmd_ready,
      output  io_remote_cmd_payload_last,
      output [0:0] io_remote_cmd_payload_fragment,
      input   io_remote_rsp_valid,
      output  io_remote_rsp_ready,
      input   io_remote_rsp_payload_error,
      input  [31:0] io_remote_rsp_payload_data,
      input   clk,
      input   reset);
  wire  _zz_2_;
  wire  _zz_3_;
  wire [0:0] _zz_4_;
  wire  _zz_5_;
  wire  _zz_6_;
  wire [3:0] _zz_7_;
  wire [3:0] _zz_8_;
  wire [3:0] _zz_9_;
  wire  system_cmd_valid;
  wire  system_cmd_payload_last;
  wire [0:0] system_cmd_payload_fragment;
  reg  system_rsp_valid;
  reg  system_rsp_payload_error;
  reg [31:0] system_rsp_payload_data;
  wire `JtagState_defaultEncoding_type jtag_tap_fsm_stateNext;
  reg `JtagState_defaultEncoding_type jtag_tap_fsm_state = `JtagState_defaultEncoding_RESET;
  reg `JtagState_defaultEncoding_type _zz_1_;
  reg [3:0] jtag_tap_instruction;
  reg [3:0] jtag_tap_instructionShift;
  reg  jtag_tap_bypass;
  wire [0:0] jtag_idcodeArea_instructionId;
  wire  jtag_idcodeArea_instructionHit;
  reg [31:0] jtag_idcodeArea_shifter;
  wire [1:0] jtag_writeArea_instructionId;
  wire  jtag_writeArea_instructionHit;
  reg  jtag_writeArea_source_valid;
  wire  jtag_writeArea_source_payload_last;
  wire [0:0] jtag_writeArea_source_payload_fragment;
  wire [1:0] jtag_readArea_instructionId;
  wire  jtag_readArea_instructionHit;
  reg [33:0] jtag_readArea_shifter;
  assign _zz_5_ = (jtag_tap_fsm_state == `JtagState_defaultEncoding_DR_SHIFT);
  assign _zz_6_ = (jtag_tap_fsm_state == `JtagState_defaultEncoding_DR_SHIFT);
  assign _zz_7_ = {3'd0, jtag_idcodeArea_instructionId};
  assign _zz_8_ = {2'd0, jtag_writeArea_instructionId};
  assign _zz_9_ = {2'd0, jtag_readArea_instructionId};
  FlowCCByToggle flowCCByToggle_1_ ( 
    .io_input_valid(jtag_writeArea_source_valid),
    .io_input_payload_last(jtag_writeArea_source_payload_last),
    .io_input_payload_fragment(jtag_writeArea_source_payload_fragment),
    .io_output_valid(_zz_2_),
    .io_output_payload_last(_zz_3_),
    .io_output_payload_fragment(_zz_4_),
    .io_jtag_tck(io_jtag_tck),
    .clk(clk),
    .reset(reset) 
  );
  assign io_remote_cmd_valid = system_cmd_valid;
  assign io_remote_cmd_payload_last = system_cmd_payload_last;
  assign io_remote_cmd_payload_fragment = system_cmd_payload_fragment;
  assign io_remote_rsp_ready = 1'b1;
  always @ (*) begin
    case(jtag_tap_fsm_state)
      `JtagState_defaultEncoding_IDLE : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_DR_SELECT : `JtagState_defaultEncoding_IDLE);
      end
      `JtagState_defaultEncoding_IR_SELECT : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_RESET : `JtagState_defaultEncoding_IR_CAPTURE);
      end
      `JtagState_defaultEncoding_IR_CAPTURE : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_IR_EXIT1 : `JtagState_defaultEncoding_IR_SHIFT);
      end
      `JtagState_defaultEncoding_IR_SHIFT : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_IR_EXIT1 : `JtagState_defaultEncoding_IR_SHIFT);
      end
      `JtagState_defaultEncoding_IR_EXIT1 : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_IR_UPDATE : `JtagState_defaultEncoding_IR_PAUSE);
      end
      `JtagState_defaultEncoding_IR_PAUSE : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_IR_EXIT2 : `JtagState_defaultEncoding_IR_PAUSE);
      end
      `JtagState_defaultEncoding_IR_EXIT2 : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_IR_UPDATE : `JtagState_defaultEncoding_IR_SHIFT);
      end
      `JtagState_defaultEncoding_IR_UPDATE : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_DR_SELECT : `JtagState_defaultEncoding_IDLE);
      end
      `JtagState_defaultEncoding_DR_SELECT : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_IR_SELECT : `JtagState_defaultEncoding_DR_CAPTURE);
      end
      `JtagState_defaultEncoding_DR_CAPTURE : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_DR_EXIT1 : `JtagState_defaultEncoding_DR_SHIFT);
      end
      `JtagState_defaultEncoding_DR_SHIFT : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_DR_EXIT1 : `JtagState_defaultEncoding_DR_SHIFT);
      end
      `JtagState_defaultEncoding_DR_EXIT1 : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_DR_UPDATE : `JtagState_defaultEncoding_DR_PAUSE);
      end
      `JtagState_defaultEncoding_DR_PAUSE : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_DR_EXIT2 : `JtagState_defaultEncoding_DR_PAUSE);
      end
      `JtagState_defaultEncoding_DR_EXIT2 : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_DR_UPDATE : `JtagState_defaultEncoding_DR_SHIFT);
      end
      `JtagState_defaultEncoding_DR_UPDATE : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_DR_SELECT : `JtagState_defaultEncoding_IDLE);
      end
      default : begin
        _zz_1_ = (io_jtag_tms ? `JtagState_defaultEncoding_RESET : `JtagState_defaultEncoding_IDLE);
      end
    endcase
  end

  assign jtag_tap_fsm_stateNext = _zz_1_;
  always @ (*) begin
    io_jtag_tdo = jtag_tap_bypass;
    case(jtag_tap_fsm_state)
      `JtagState_defaultEncoding_IR_CAPTURE : begin
      end
      `JtagState_defaultEncoding_IR_SHIFT : begin
        io_jtag_tdo = jtag_tap_instructionShift[0];
      end
      `JtagState_defaultEncoding_IR_UPDATE : begin
      end
      `JtagState_defaultEncoding_DR_SHIFT : begin
      end
      default : begin
      end
    endcase
    if(jtag_idcodeArea_instructionHit)begin
      if(_zz_5_)begin
        io_jtag_tdo = jtag_idcodeArea_shifter[0];
      end
    end
    if(jtag_readArea_instructionHit)begin
      if(_zz_6_)begin
        io_jtag_tdo = jtag_readArea_shifter[0];
      end
    end
  end

  assign jtag_idcodeArea_instructionId = (1'b1);
  assign jtag_idcodeArea_instructionHit = (jtag_tap_instruction == _zz_7_);
  assign jtag_writeArea_instructionId = (2'b10);
  assign jtag_writeArea_instructionHit = (jtag_tap_instruction == _zz_8_);
  always @ (*) begin
    jtag_writeArea_source_valid = 1'b0;
    if(jtag_writeArea_instructionHit)begin
      if((jtag_tap_fsm_state == `JtagState_defaultEncoding_DR_SHIFT))begin
        jtag_writeArea_source_valid = 1'b1;
      end
    end
  end

  assign jtag_writeArea_source_payload_last = io_jtag_tms;
  assign jtag_writeArea_source_payload_fragment[0] = io_jtag_tdi;
  assign system_cmd_valid = _zz_2_;
  assign system_cmd_payload_last = _zz_3_;
  assign system_cmd_payload_fragment = _zz_4_;
  assign jtag_readArea_instructionId = (2'b11);
  assign jtag_readArea_instructionHit = (jtag_tap_instruction == _zz_9_);
  always @ (posedge clk) begin
    if(io_remote_cmd_valid)begin
      system_rsp_valid <= 1'b0;
    end
    if((io_remote_rsp_valid && io_remote_rsp_ready))begin
      system_rsp_valid <= 1'b1;
      system_rsp_payload_error <= io_remote_rsp_payload_error;
      system_rsp_payload_data <= io_remote_rsp_payload_data;
    end
  end

  always @ (posedge io_jtag_tck) begin
    jtag_tap_fsm_state <= jtag_tap_fsm_stateNext;
    case(jtag_tap_fsm_state)
      `JtagState_defaultEncoding_IR_CAPTURE : begin
        jtag_tap_instructionShift <= jtag_tap_instruction;
      end
      `JtagState_defaultEncoding_IR_SHIFT : begin
        jtag_tap_instructionShift <= ({io_jtag_tdi,jtag_tap_instructionShift} >>> 1);
      end
      `JtagState_defaultEncoding_IR_UPDATE : begin
        jtag_tap_instruction <= jtag_tap_instructionShift;
      end
      `JtagState_defaultEncoding_DR_SHIFT : begin
        jtag_tap_bypass <= io_jtag_tdi;
      end
      default : begin
      end
    endcase
    if(jtag_idcodeArea_instructionHit)begin
      if(_zz_5_)begin
        jtag_idcodeArea_shifter <= ({io_jtag_tdi,jtag_idcodeArea_shifter} >>> 1);
      end
    end
    if((jtag_tap_fsm_state == `JtagState_defaultEncoding_RESET))begin
      jtag_idcodeArea_shifter <= (32'b00010000000000000001111111111111);
      jtag_tap_instruction <= {3'd0, jtag_idcodeArea_instructionId};
    end
    if(jtag_readArea_instructionHit)begin
      if((jtag_tap_fsm_state == `JtagState_defaultEncoding_DR_CAPTURE))begin
        jtag_readArea_shifter <= {{system_rsp_payload_data,system_rsp_payload_error},system_rsp_valid};
      end
      if(_zz_6_)begin
        jtag_readArea_shifter <= ({io_jtag_tdi,jtag_readArea_shifter} >>> 1);
      end
    end
  end

endmodule

module SystemDebugger (
      input   io_remote_cmd_valid,
      output  io_remote_cmd_ready,
      input   io_remote_cmd_payload_last,
      input  [0:0] io_remote_cmd_payload_fragment,
      output  io_remote_rsp_valid,
      input   io_remote_rsp_ready,
      output  io_remote_rsp_payload_error,
      output [31:0] io_remote_rsp_payload_data,
      output  io_mem_cmd_valid,
      input   io_mem_cmd_ready,
      output [31:0] io_mem_cmd_payload_address,
      output [31:0] io_mem_cmd_payload_data,
      output  io_mem_cmd_payload_wr,
      output [1:0] io_mem_cmd_payload_size,
      input   io_mem_rsp_valid,
      input  [31:0] io_mem_rsp_payload,
      input   clk,
      input   reset);
  wire  _zz_2_;
  wire [0:0] _zz_3_;
  reg [66:0] dispatcher_dataShifter;
  reg  dispatcher_dataLoaded;
  reg [7:0] dispatcher_headerShifter;
  wire [7:0] dispatcher_header;
  reg  dispatcher_headerLoaded;
  reg [2:0] dispatcher_counter;
  wire [66:0] _zz_1_;
  assign _zz_2_ = (dispatcher_headerLoaded == 1'b0);
  assign _zz_3_ = _zz_1_[64 : 64];
  assign dispatcher_header = dispatcher_headerShifter[7 : 0];
  assign io_remote_cmd_ready = (! dispatcher_dataLoaded);
  assign _zz_1_ = dispatcher_dataShifter[66 : 0];
  assign io_mem_cmd_payload_address = _zz_1_[31 : 0];
  assign io_mem_cmd_payload_data = _zz_1_[63 : 32];
  assign io_mem_cmd_payload_wr = _zz_3_[0];
  assign io_mem_cmd_payload_size = _zz_1_[66 : 65];
  assign io_mem_cmd_valid = (dispatcher_dataLoaded && (dispatcher_header == (8'b00000000)));
  assign io_remote_rsp_valid = io_mem_rsp_valid;
  assign io_remote_rsp_payload_error = 1'b0;
  assign io_remote_rsp_payload_data = io_mem_rsp_payload;
  always @ (posedge clk or posedge reset) begin
    if (reset) begin
      dispatcher_dataLoaded <= 1'b0;
      dispatcher_headerLoaded <= 1'b0;
      dispatcher_counter <= (3'b000);
    end else begin
      if(io_remote_cmd_valid)begin
        if(_zz_2_)begin
          dispatcher_counter <= (dispatcher_counter + (3'b001));
          if((dispatcher_counter == (3'b111)))begin
            dispatcher_headerLoaded <= 1'b1;
          end
        end
        if(io_remote_cmd_payload_last)begin
          dispatcher_headerLoaded <= 1'b1;
          dispatcher_dataLoaded <= 1'b1;
          dispatcher_counter <= (3'b000);
        end
      end
      if((io_mem_cmd_valid && io_mem_cmd_ready))begin
        dispatcher_headerLoaded <= 1'b0;
        dispatcher_dataLoaded <= 1'b0;
      end
    end
  end

  always @ (posedge clk) begin
    if(io_remote_cmd_valid)begin
      if(_zz_2_)begin
        dispatcher_headerShifter <= ({io_remote_cmd_payload_fragment,dispatcher_headerShifter} >>> 1);
      end else begin
        dispatcher_dataShifter <= ({io_remote_cmd_payload_fragment,dispatcher_dataShifter} >>> 1);
      end
    end
  end

endmodule

module VexRiscvAxi4 (
      output  debug_resetOut,
      input   timerInterrupt,
      input   externalInterrupt,
      output  iBusAxi_ar_valid,
      input   iBusAxi_ar_ready,
      output [31:0] iBusAxi_ar_payload_addr,
      output [0:0] iBusAxi_ar_payload_id,
      output [3:0] iBusAxi_ar_payload_region,
      output [7:0] iBusAxi_ar_payload_len,
      output [2:0] iBusAxi_ar_payload_size,
      output [1:0] iBusAxi_ar_payload_burst,
      output [0:0] iBusAxi_ar_payload_lock,
      output [3:0] iBusAxi_ar_payload_cache,
      output [3:0] iBusAxi_ar_payload_qos,
      output [2:0] iBusAxi_ar_payload_prot,
      input   iBusAxi_r_valid,
      output  iBusAxi_r_ready,
      input  [31:0] iBusAxi_r_payload_data,
      input  [0:0] iBusAxi_r_payload_id,
      input  [1:0] iBusAxi_r_payload_resp,
      input   iBusAxi_r_payload_last,
      output  dBusAxi_aw_valid,
      input   dBusAxi_aw_ready,
      output [31:0] dBusAxi_aw_payload_addr,
      output [0:0] dBusAxi_aw_payload_id,
      output [3:0] dBusAxi_aw_payload_region,
      output [7:0] dBusAxi_aw_payload_len,
      output [2:0] dBusAxi_aw_payload_size,
      output [1:0] dBusAxi_aw_payload_burst,
      output [0:0] dBusAxi_aw_payload_lock,
      output [3:0] dBusAxi_aw_payload_cache,
      output [3:0] dBusAxi_aw_payload_qos,
      output [2:0] dBusAxi_aw_payload_prot,
      output  dBusAxi_w_valid,
      input   dBusAxi_w_ready,
      output [31:0] dBusAxi_w_payload_data,
      output [3:0] dBusAxi_w_payload_strb,
      output  dBusAxi_w_payload_last,
      input   dBusAxi_b_valid,
      output  dBusAxi_b_ready,
      input  [0:0] dBusAxi_b_payload_id,
      input  [1:0] dBusAxi_b_payload_resp,
      output  dBusAxi_ar_valid,
      input   dBusAxi_ar_ready,
      output [31:0] dBusAxi_ar_payload_addr,
      output [0:0] dBusAxi_ar_payload_id,
      output [3:0] dBusAxi_ar_payload_region,
      output [7:0] dBusAxi_ar_payload_len,
      output [2:0] dBusAxi_ar_payload_size,
      output [1:0] dBusAxi_ar_payload_burst,
      output [0:0] dBusAxi_ar_payload_lock,
      output [3:0] dBusAxi_ar_payload_cache,
      output [3:0] dBusAxi_ar_payload_qos,
      output [2:0] dBusAxi_ar_payload_prot,
      input   dBusAxi_r_valid,
      output  dBusAxi_r_ready,
      input  [31:0] dBusAxi_r_payload_data,
      input  [0:0] dBusAxi_r_payload_id,
      input  [1:0] dBusAxi_r_payload_resp,
      input   dBusAxi_r_payload_last,
      input   jtag_tms,
      input   jtag_tdi,
      output  jtag_tdo,
      input   jtag_tck,
      input   clk,
      input   reset,
      input   debugReset);
  reg  _zz_243_;
  wire  _zz_244_;
  wire  _zz_245_;
  wire  _zz_246_;
  wire  _zz_247_;
  wire  _zz_248_;
  wire  _zz_249_;
  wire  _zz_250_;
  wire  _zz_251_;
  wire  _zz_252_;
  wire  _zz_253_;
  wire  _zz_254_;
  wire  _zz_255_;
  wire `DataCacheCpuCmdKind_defaultEncoding_type _zz_256_;
  wire [31:0] _zz_257_;
  wire  _zz_258_;
  wire  _zz_259_;
  wire  _zz_260_;
  wire  _zz_261_;
  wire  _zz_262_;
  wire  _zz_263_;
  wire  _zz_264_;
  wire  _zz_265_;
  wire  _zz_266_;
  wire  _zz_267_;
  wire  _zz_268_;
  wire  _zz_269_;
  wire  _zz_270_;
  wire  _zz_271_;
  wire  _zz_272_;
  reg  _zz_273_;
  reg  _zz_274_;
  reg [31:0] _zz_275_;
  reg [31:0] _zz_276_;
  reg [31:0] _zz_277_;
  wire  _zz_278_;
  wire  _zz_279_;
  wire  _zz_280_;
  wire [31:0] _zz_281_;
  wire [31:0] _zz_282_;
  wire  _zz_283_;
  wire [31:0] _zz_284_;
  wire  _zz_285_;
  wire  _zz_286_;
  wire  _zz_287_;
  wire  _zz_288_;
  wire  _zz_289_;
  wire [31:0] _zz_290_;
  wire  _zz_291_;
  wire [31:0] _zz_292_;
  wire  _zz_293_;
  wire [31:0] _zz_294_;
  wire [2:0] _zz_295_;
  wire  _zz_296_;
  wire  _zz_297_;
  wire [31:0] _zz_298_;
  wire  _zz_299_;
  wire  _zz_300_;
  wire  _zz_301_;
  wire [31:0] _zz_302_;
  wire  _zz_303_;
  wire  _zz_304_;
  wire  _zz_305_;
  wire  _zz_306_;
  wire [31:0] _zz_307_;
  wire  _zz_308_;
  wire  _zz_309_;
  wire [31:0] _zz_310_;
  wire [31:0] _zz_311_;
  wire [3:0] _zz_312_;
  wire [2:0] _zz_313_;
  wire  _zz_314_;
  wire  _zz_315_;
  wire  _zz_316_;
  wire  _zz_317_;
  wire [31:0] _zz_318_;
  wire [31:0] _zz_319_;
  wire [3:0] _zz_320_;
  wire [2:0] _zz_321_;
  wire  _zz_322_;
  wire  _zz_323_;
  wire  _zz_324_;
  wire [31:0] _zz_325_;
  wire [31:0] _zz_326_;
  wire [3:0] _zz_327_;
  wire [2:0] _zz_328_;
  wire  _zz_329_;
  wire  _zz_330_;
  wire  _zz_331_;
  wire  _zz_332_;
  wire [0:0] _zz_333_;
  wire  _zz_334_;
  wire  _zz_335_;
  wire  _zz_336_;
  wire  _zz_337_;
  wire [31:0] _zz_338_;
  wire  _zz_339_;
  wire [31:0] _zz_340_;
  wire [31:0] _zz_341_;
  wire  _zz_342_;
  wire [1:0] _zz_343_;
  wire  _zz_344_;
  wire  _zz_345_;
  wire  _zz_346_;
  wire  _zz_347_;
  wire  _zz_348_;
  wire  _zz_349_;
  wire  _zz_350_;
  wire  _zz_351_;
  wire  _zz_352_;
  wire [5:0] _zz_353_;
  wire [1:0] _zz_354_;
  wire [1:0] _zz_355_;
  wire [1:0] _zz_356_;
  wire [1:0] _zz_357_;
  wire  _zz_358_;
  wire [3:0] _zz_359_;
  wire [2:0] _zz_360_;
  wire [31:0] _zz_361_;
  wire [11:0] _zz_362_;
  wire [31:0] _zz_363_;
  wire [19:0] _zz_364_;
  wire [11:0] _zz_365_;
  wire [2:0] _zz_366_;
  wire [2:0] _zz_367_;
  wire [0:0] _zz_368_;
  wire [0:0] _zz_369_;
  wire [0:0] _zz_370_;
  wire [0:0] _zz_371_;
  wire [0:0] _zz_372_;
  wire [0:0] _zz_373_;
  wire [0:0] _zz_374_;
  wire [0:0] _zz_375_;
  wire [0:0] _zz_376_;
  wire [0:0] _zz_377_;
  wire [0:0] _zz_378_;
  wire [0:0] _zz_379_;
  wire [0:0] _zz_380_;
  wire [0:0] _zz_381_;
  wire [0:0] _zz_382_;
  wire [0:0] _zz_383_;
  wire [0:0] _zz_384_;
  wire [0:0] _zz_385_;
  wire [2:0] _zz_386_;
  wire [4:0] _zz_387_;
  wire [11:0] _zz_388_;
  wire [11:0] _zz_389_;
  wire [31:0] _zz_390_;
  wire [31:0] _zz_391_;
  wire [31:0] _zz_392_;
  wire [31:0] _zz_393_;
  wire [1:0] _zz_394_;
  wire [31:0] _zz_395_;
  wire [1:0] _zz_396_;
  wire [1:0] _zz_397_;
  wire [32:0] _zz_398_;
  wire [31:0] _zz_399_;
  wire [32:0] _zz_400_;
  wire [51:0] _zz_401_;
  wire [51:0] _zz_402_;
  wire [51:0] _zz_403_;
  wire [32:0] _zz_404_;
  wire [51:0] _zz_405_;
  wire [49:0] _zz_406_;
  wire [51:0] _zz_407_;
  wire [49:0] _zz_408_;
  wire [51:0] _zz_409_;
  wire [65:0] _zz_410_;
  wire [65:0] _zz_411_;
  wire [31:0] _zz_412_;
  wire [31:0] _zz_413_;
  wire [0:0] _zz_414_;
  wire [5:0] _zz_415_;
  wire [32:0] _zz_416_;
  wire [32:0] _zz_417_;
  wire [31:0] _zz_418_;
  wire [31:0] _zz_419_;
  wire [32:0] _zz_420_;
  wire [32:0] _zz_421_;
  wire [32:0] _zz_422_;
  wire [0:0] _zz_423_;
  wire [32:0] _zz_424_;
  wire [0:0] _zz_425_;
  wire [32:0] _zz_426_;
  wire [0:0] _zz_427_;
  wire [31:0] _zz_428_;
  wire [11:0] _zz_429_;
  wire [19:0] _zz_430_;
  wire [11:0] _zz_431_;
  wire [31:0] _zz_432_;
  wire [31:0] _zz_433_;
  wire [31:0] _zz_434_;
  wire [11:0] _zz_435_;
  wire [19:0] _zz_436_;
  wire [11:0] _zz_437_;
  wire [2:0] _zz_438_;
  wire [1:0] _zz_439_;
  wire [1:0] _zz_440_;
  wire [0:0] _zz_441_;
  wire [0:0] _zz_442_;
  wire [0:0] _zz_443_;
  wire [0:0] _zz_444_;
  wire [0:0] _zz_445_;
  wire [0:0] _zz_446_;
  wire  _zz_447_;
  wire  _zz_448_;
  wire [1:0] _zz_449_;
  wire [0:0] _zz_450_;
  wire [7:0] _zz_451_;
  wire  _zz_452_;
  wire [0:0] _zz_453_;
  wire [0:0] _zz_454_;
  wire [31:0] _zz_455_;
  wire  _zz_456_;
  wire [0:0] _zz_457_;
  wire [3:0] _zz_458_;
  wire [0:0] _zz_459_;
  wire [0:0] _zz_460_;
  wire  _zz_461_;
  wire [0:0] _zz_462_;
  wire [24:0] _zz_463_;
  wire [31:0] _zz_464_;
  wire  _zz_465_;
  wire [0:0] _zz_466_;
  wire [0:0] _zz_467_;
  wire [31:0] _zz_468_;
  wire [0:0] _zz_469_;
  wire [1:0] _zz_470_;
  wire [2:0] _zz_471_;
  wire [2:0] _zz_472_;
  wire  _zz_473_;
  wire [0:0] _zz_474_;
  wire [21:0] _zz_475_;
  wire [31:0] _zz_476_;
  wire [31:0] _zz_477_;
  wire [31:0] _zz_478_;
  wire [31:0] _zz_479_;
  wire [31:0] _zz_480_;
  wire [31:0] _zz_481_;
  wire [31:0] _zz_482_;
  wire  _zz_483_;
  wire  _zz_484_;
  wire [0:0] _zz_485_;
  wire [0:0] _zz_486_;
  wire [0:0] _zz_487_;
  wire [0:0] _zz_488_;
  wire [1:0] _zz_489_;
  wire [1:0] _zz_490_;
  wire  _zz_491_;
  wire [0:0] _zz_492_;
  wire [19:0] _zz_493_;
  wire [31:0] _zz_494_;
  wire [31:0] _zz_495_;
  wire [31:0] _zz_496_;
  wire [31:0] _zz_497_;
  wire [31:0] _zz_498_;
  wire [31:0] _zz_499_;
  wire [31:0] _zz_500_;
  wire [0:0] _zz_501_;
  wire [3:0] _zz_502_;
  wire [1:0] _zz_503_;
  wire [1:0] _zz_504_;
  wire  _zz_505_;
  wire [0:0] _zz_506_;
  wire [16:0] _zz_507_;
  wire [31:0] _zz_508_;
  wire [31:0] _zz_509_;
  wire [31:0] _zz_510_;
  wire [0:0] _zz_511_;
  wire [0:0] _zz_512_;
  wire [31:0] _zz_513_;
  wire [31:0] _zz_514_;
  wire [31:0] _zz_515_;
  wire [31:0] _zz_516_;
  wire [0:0] _zz_517_;
  wire [0:0] _zz_518_;
  wire [0:0] _zz_519_;
  wire [1:0] _zz_520_;
  wire [1:0] _zz_521_;
  wire [1:0] _zz_522_;
  wire  _zz_523_;
  wire [0:0] _zz_524_;
  wire [13:0] _zz_525_;
  wire [31:0] _zz_526_;
  wire [31:0] _zz_527_;
  wire [31:0] _zz_528_;
  wire [31:0] _zz_529_;
  wire [31:0] _zz_530_;
  wire [31:0] _zz_531_;
  wire [31:0] _zz_532_;
  wire [31:0] _zz_533_;
  wire  _zz_534_;
  wire  _zz_535_;
  wire [0:0] _zz_536_;
  wire [1:0] _zz_537_;
  wire [0:0] _zz_538_;
  wire [0:0] _zz_539_;
  wire  _zz_540_;
  wire [0:0] _zz_541_;
  wire [11:0] _zz_542_;
  wire [31:0] _zz_543_;
  wire [31:0] _zz_544_;
  wire [31:0] _zz_545_;
  wire [31:0] _zz_546_;
  wire [31:0] _zz_547_;
  wire [31:0] _zz_548_;
  wire [31:0] _zz_549_;
  wire [31:0] _zz_550_;
  wire [0:0] _zz_551_;
  wire [0:0] _zz_552_;
  wire [1:0] _zz_553_;
  wire [1:0] _zz_554_;
  wire  _zz_555_;
  wire [0:0] _zz_556_;
  wire [8:0] _zz_557_;
  wire [31:0] _zz_558_;
  wire [31:0] _zz_559_;
  wire [31:0] _zz_560_;
  wire [0:0] _zz_561_;
  wire [2:0] _zz_562_;
  wire [0:0] _zz_563_;
  wire [0:0] _zz_564_;
  wire [0:0] _zz_565_;
  wire [0:0] _zz_566_;
  wire  _zz_567_;
  wire [0:0] _zz_568_;
  wire [5:0] _zz_569_;
  wire [31:0] _zz_570_;
  wire [31:0] _zz_571_;
  wire [31:0] _zz_572_;
  wire  _zz_573_;
  wire  _zz_574_;
  wire [31:0] _zz_575_;
  wire [31:0] _zz_576_;
  wire [31:0] _zz_577_;
  wire  _zz_578_;
  wire [0:0] _zz_579_;
  wire [0:0] _zz_580_;
  wire [0:0] _zz_581_;
  wire [4:0] _zz_582_;
  wire [0:0] _zz_583_;
  wire [0:0] _zz_584_;
  wire  _zz_585_;
  wire [0:0] _zz_586_;
  wire [2:0] _zz_587_;
  wire [31:0] _zz_588_;
  wire [31:0] _zz_589_;
  wire [31:0] _zz_590_;
  wire [31:0] _zz_591_;
  wire [31:0] _zz_592_;
  wire [31:0] _zz_593_;
  wire [31:0] _zz_594_;
  wire  _zz_595_;
  wire [0:0] _zz_596_;
  wire [2:0] _zz_597_;
  wire [31:0] _zz_598_;
  wire [31:0] _zz_599_;
  wire  _zz_600_;
  wire [1:0] _zz_601_;
  wire [1:0] _zz_602_;
  wire  _zz_603_;
  wire [0:0] _zz_604_;
  wire [0:0] _zz_605_;
  wire [31:0] _zz_606_;
  wire [31:0] _zz_607_;
  wire [31:0] _zz_608_;
  wire [31:0] _zz_609_;
  wire [31:0] _zz_610_;
  wire [0:0] _zz_611_;
  wire [1:0] _zz_612_;
  wire [31:0] _zz_613_;
  wire [31:0] _zz_614_;
  wire [31:0] _zz_615_;
  wire  _zz_616_;
  wire [0:0] _zz_617_;
  wire [12:0] _zz_618_;
  wire [31:0] _zz_619_;
  wire [31:0] _zz_620_;
  wire [31:0] _zz_621_;
  wire  _zz_622_;
  wire [0:0] _zz_623_;
  wire [6:0] _zz_624_;
  wire [31:0] _zz_625_;
  wire [31:0] _zz_626_;
  wire [31:0] _zz_627_;
  wire  _zz_628_;
  wire [0:0] _zz_629_;
  wire [0:0] _zz_630_;
  wire  _zz_631_;
  wire  _zz_632_;
  wire  _zz_633_;
  wire `Src2CtrlEnum_defaultEncoding_type decode_SRC2_CTRL;
  wire `Src2CtrlEnum_defaultEncoding_type _zz_1_;
  wire `Src2CtrlEnum_defaultEncoding_type _zz_2_;
  wire `Src2CtrlEnum_defaultEncoding_type _zz_3_;
  wire [31:0] execute_BRANCH_CALC;
  wire [31:0] execute_MUL_LL;
  wire [31:0] writeBack_FORMAL_PC_NEXT;
  wire [31:0] memory_FORMAL_PC_NEXT;
  wire [31:0] execute_FORMAL_PC_NEXT;
  wire [31:0] decode_FORMAL_PC_NEXT;
  wire [31:0] execute_SHIFT_RIGHT;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_4_;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_5_;
  wire `ShiftCtrlEnum_defaultEncoding_type decode_SHIFT_CTRL;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_6_;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_7_;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_8_;
  wire  decode_SRC_USE_SUB_LESS;
  wire  decode_CSR_WRITE_OPCODE;
  wire  memory_IS_MUL;
  wire  execute_IS_MUL;
  wire  decode_IS_MUL;
  wire [33:0] execute_MUL_HL;
  wire  decode_IS_CSR;
  wire  execute_FLUSH_ALL;
  wire  decode_FLUSH_ALL;
  wire `BranchCtrlEnum_defaultEncoding_type _zz_9_;
  wire `BranchCtrlEnum_defaultEncoding_type _zz_10_;
  wire  decode_IS_RS1_SIGNED;
  wire [31:0] writeBack_REGFILE_WRITE_DATA;
  wire [31:0] memory_REGFILE_WRITE_DATA;
  wire [31:0] execute_REGFILE_WRITE_DATA;
  wire  execute_BYPASSABLE_MEMORY_STAGE;
  wire  decode_BYPASSABLE_MEMORY_STAGE;
  wire  decode_SRC_LESS_UNSIGNED;
  wire  decode_MEMORY_MANAGMENT;
  wire [51:0] memory_MUL_LOW;
  wire  decode_IS_DIV;
  wire  memory_MEMORY_WR;
  wire  decode_MEMORY_WR;
  wire  execute_BRANCH_DO;
  wire  decode_DO_EBREAK;
  wire  decode_MEMORY_ENABLE;
  wire  decode_CSR_READ_OPCODE;
  wire  decode_BYPASSABLE_EXECUTE_STAGE;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type decode_ALU_BITWISE_CTRL;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type _zz_11_;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type _zz_12_;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type _zz_13_;
  wire [33:0] execute_MUL_LH;
  wire [33:0] memory_MUL_HH;
  wire [33:0] execute_MUL_HH;
  wire `AluCtrlEnum_defaultEncoding_type decode_ALU_CTRL;
  wire `AluCtrlEnum_defaultEncoding_type _zz_14_;
  wire `AluCtrlEnum_defaultEncoding_type _zz_15_;
  wire `AluCtrlEnum_defaultEncoding_type _zz_16_;
  wire  decode_IS_RS2_SIGNED;
  wire [1:0] memory_MEMORY_ADDRESS_LOW;
  wire [1:0] execute_MEMORY_ADDRESS_LOW;
  wire  decode_PREDICTION_HAD_BRANCHED2;
  wire [31:0] memory_PC;
  wire `Src1CtrlEnum_defaultEncoding_type decode_SRC1_CTRL;
  wire `Src1CtrlEnum_defaultEncoding_type _zz_17_;
  wire `Src1CtrlEnum_defaultEncoding_type _zz_18_;
  wire `Src1CtrlEnum_defaultEncoding_type _zz_19_;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_20_;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_21_;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_22_;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_23_;
  wire `EnvCtrlEnum_defaultEncoding_type decode_ENV_CTRL;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_24_;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_25_;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_26_;
  wire  execute_CSR_READ_OPCODE;
  wire  execute_CSR_WRITE_OPCODE;
  wire  execute_IS_CSR;
  wire `EnvCtrlEnum_defaultEncoding_type memory_ENV_CTRL;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_27_;
  wire `EnvCtrlEnum_defaultEncoding_type execute_ENV_CTRL;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_28_;
  wire  _zz_29_;
  wire  _zz_30_;
  wire `EnvCtrlEnum_defaultEncoding_type writeBack_ENV_CTRL;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_31_;
  wire [31:0] memory_BRANCH_CALC;
  wire  memory_BRANCH_DO;
  wire [31:0] _zz_32_;
  wire  execute_PREDICTION_HAD_BRANCHED2;
  wire  _zz_33_;
  wire  execute_BRANCH_COND_RESULT;
  wire `BranchCtrlEnum_defaultEncoding_type execute_BRANCH_CTRL;
  wire `BranchCtrlEnum_defaultEncoding_type _zz_34_;
  wire  _zz_35_;
  wire  _zz_36_;
  wire [31:0] execute_PC;
  wire  execute_DO_EBREAK;
  wire  decode_IS_EBREAK;
  wire  _zz_37_;
  wire  decode_RS2_USE;
  wire  decode_RS1_USE;
  reg [31:0] _zz_38_;
  wire  execute_REGFILE_WRITE_VALID;
  wire  execute_BYPASSABLE_EXECUTE_STAGE;
  wire  memory_REGFILE_WRITE_VALID;
  wire  memory_BYPASSABLE_MEMORY_STAGE;
  wire  writeBack_REGFILE_WRITE_VALID;
  reg [31:0] decode_RS2;
  reg [31:0] decode_RS1;
  wire  execute_IS_RS1_SIGNED;
  wire [31:0] execute_RS1;
  wire  execute_IS_DIV;
  wire  execute_IS_RS2_SIGNED;
  wire [31:0] memory_INSTRUCTION;
  wire  memory_IS_DIV;
  wire  writeBack_IS_MUL;
  wire [33:0] writeBack_MUL_HH;
  wire [51:0] writeBack_MUL_LOW;
  wire [33:0] memory_MUL_HL;
  wire [33:0] memory_MUL_LH;
  wire [31:0] memory_MUL_LL;
  wire [51:0] _zz_39_;
  wire [33:0] _zz_40_;
  wire [33:0] _zz_41_;
  wire [33:0] _zz_42_;
  wire [31:0] _zz_43_;
  wire [31:0] memory_SHIFT_RIGHT;
  reg [31:0] _zz_44_;
  wire `ShiftCtrlEnum_defaultEncoding_type memory_SHIFT_CTRL;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_45_;
  wire [31:0] _zz_46_;
  wire `ShiftCtrlEnum_defaultEncoding_type execute_SHIFT_CTRL;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_47_;
  wire  _zz_48_;
  wire [31:0] _zz_49_;
  wire [31:0] _zz_50_;
  wire  execute_SRC_LESS_UNSIGNED;
  wire  execute_SRC_USE_SUB_LESS;
  wire [31:0] _zz_51_;
  wire `Src2CtrlEnum_defaultEncoding_type execute_SRC2_CTRL;
  wire `Src2CtrlEnum_defaultEncoding_type _zz_52_;
  wire [31:0] _zz_53_;
  wire `Src1CtrlEnum_defaultEncoding_type execute_SRC1_CTRL;
  wire `Src1CtrlEnum_defaultEncoding_type _zz_54_;
  wire [31:0] _zz_55_;
  wire [31:0] execute_SRC_ADD_SUB;
  wire  execute_SRC_LESS;
  wire `AluCtrlEnum_defaultEncoding_type execute_ALU_CTRL;
  wire `AluCtrlEnum_defaultEncoding_type _zz_56_;
  wire [31:0] _zz_57_;
  wire [31:0] execute_SRC2;
  wire [31:0] execute_SRC1;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type execute_ALU_BITWISE_CTRL;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type _zz_58_;
  wire [31:0] _zz_59_;
  wire  _zz_60_;
  reg  _zz_61_;
  wire [31:0] _zz_62_;
  wire [31:0] _zz_63_;
  wire [31:0] decode_INSTRUCTION_ANTICIPATED;
  reg  decode_REGFILE_WRITE_VALID;
  wire  decode_LEGAL_INSTRUCTION;
  wire  decode_INSTRUCTION_READY;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_64_;
  wire  _zz_65_;
  wire  _zz_66_;
  wire  _zz_67_;
  wire  _zz_68_;
  wire  _zz_69_;
  wire `Src1CtrlEnum_defaultEncoding_type _zz_70_;
  wire `AluCtrlEnum_defaultEncoding_type _zz_71_;
  wire  _zz_72_;
  wire  _zz_73_;
  wire `Src2CtrlEnum_defaultEncoding_type _zz_74_;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_75_;
  wire  _zz_76_;
  wire  _zz_77_;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type _zz_78_;
  wire  _zz_79_;
  wire  _zz_80_;
  wire  _zz_81_;
  wire  _zz_82_;
  wire  _zz_83_;
  wire  _zz_84_;
  wire  _zz_85_;
  wire `BranchCtrlEnum_defaultEncoding_type _zz_86_;
  wire  _zz_87_;
  wire  _zz_88_;
  reg [31:0] _zz_89_;
  wire [1:0] writeBack_MEMORY_ADDRESS_LOW;
  wire  writeBack_MEMORY_WR;
  wire  writeBack_MEMORY_ENABLE;
  wire  memory_MEMORY_ENABLE;
  wire [1:0] _zz_90_;
  wire  execute_MEMORY_MANAGMENT;
  wire [31:0] execute_RS2;
  wire [31:0] execute_SRC_ADD;
  wire  execute_MEMORY_WR;
  wire  execute_MEMORY_ENABLE;
  wire [31:0] execute_INSTRUCTION;
  wire  memory_FLUSH_ALL;
  reg  IBusCachedPlugin_issueDetected;
  reg  _zz_91_;
  wire [31:0] _zz_92_;
  wire `BranchCtrlEnum_defaultEncoding_type decode_BRANCH_CTRL;
  wire `BranchCtrlEnum_defaultEncoding_type _zz_93_;
  reg [31:0] _zz_94_;
  reg [31:0] _zz_95_;
  wire [31:0] _zz_96_;
  wire [31:0] _zz_97_;
  wire [31:0] _zz_98_;
  wire [31:0] writeBack_PC /* verilator public */ ;
  wire [31:0] writeBack_INSTRUCTION /* verilator public */ ;
  wire [31:0] decode_PC /* verilator public */ ;
  reg [31:0] decode_INSTRUCTION /* verilator public */ ;
  reg  decode_arbitration_haltItself /* verilator public */ ;
  reg  decode_arbitration_haltByOther;
  reg  decode_arbitration_removeIt;
  wire  decode_arbitration_flushAll /* verilator public */ ;
  wire  decode_arbitration_redoIt;
  reg  decode_arbitration_isValid /* verilator public */ ;
  wire  decode_arbitration_isStuck;
  wire  decode_arbitration_isStuckByOthers;
  wire  decode_arbitration_isFlushed;
  wire  decode_arbitration_isMoving;
  wire  decode_arbitration_isFiring;
  reg  execute_arbitration_haltItself;
  reg  execute_arbitration_haltByOther;
  reg  execute_arbitration_removeIt;
  reg  execute_arbitration_flushAll;
  wire  execute_arbitration_redoIt;
  reg  execute_arbitration_isValid;
  wire  execute_arbitration_isStuck;
  wire  execute_arbitration_isStuckByOthers;
  wire  execute_arbitration_isFlushed;
  wire  execute_arbitration_isMoving;
  wire  execute_arbitration_isFiring;
  reg  memory_arbitration_haltItself;
  wire  memory_arbitration_haltByOther;
  reg  memory_arbitration_removeIt;
  reg  memory_arbitration_flushAll;
  wire  memory_arbitration_redoIt;
  reg  memory_arbitration_isValid;
  wire  memory_arbitration_isStuck;
  wire  memory_arbitration_isStuckByOthers;
  wire  memory_arbitration_isFlushed;
  wire  memory_arbitration_isMoving;
  wire  memory_arbitration_isFiring;
  reg  writeBack_arbitration_haltItself;
  wire  writeBack_arbitration_haltByOther;
  reg  writeBack_arbitration_removeIt;
  wire  writeBack_arbitration_flushAll;
  wire  writeBack_arbitration_redoIt;
  reg  writeBack_arbitration_isValid /* verilator public */ ;
  wire  writeBack_arbitration_isStuck;
  wire  writeBack_arbitration_isStuckByOthers;
  wire  writeBack_arbitration_isFlushed;
  wire  writeBack_arbitration_isMoving;
  wire  writeBack_arbitration_isFiring /* verilator public */ ;
  reg  _zz_99_;
  reg  _zz_100_;
  reg  _zz_101_;
  wire  _zz_102_;
  wire [31:0] _zz_103_;
  wire  _zz_104_;
  wire  _zz_105_;
  wire [31:0] _zz_106_;
  reg  _zz_107_;
  wire [31:0] _zz_108_;
  wire [31:0] _zz_109_;
  wire  writeBack_exception_agregat_valid;
  reg [3:0] writeBack_exception_agregat_payload_code;
  wire [31:0] writeBack_exception_agregat_payload_badAddr;
  wire  decodeExceptionPort_valid;
  wire [3:0] decodeExceptionPort_1_code;
  wire [31:0] decodeExceptionPort_1_badAddr;
  wire  debug_bus_cmd_valid;
  reg  debug_bus_cmd_ready;
  wire  debug_bus_cmd_payload_wr;
  wire [7:0] debug_bus_cmd_payload_address;
  wire [31:0] debug_bus_cmd_payload_data;
  reg [31:0] debug_bus_rsp_data;
  reg  _zz_110_;
  reg  _zz_111_;
  wire  _zz_112_;
  wire [31:0] _zz_113_;
  wire  memory_exception_agregat_valid;
  wire [3:0] memory_exception_agregat_payload_code;
  wire [31:0] memory_exception_agregat_payload_badAddr;
  reg  _zz_114_;
  reg [31:0] _zz_115_;
  wire  contextSwitching;
  reg [1:0] CsrPlugin_privilege;
  reg  _zz_116_;
  reg  _zz_117_;
  wire  IBusCachedPlugin_jump_pcLoad_valid;
  wire [31:0] IBusCachedPlugin_jump_pcLoad_payload;
  wire [3:0] _zz_118_;
  wire [3:0] _zz_119_;
  wire  _zz_120_;
  wire  _zz_121_;
  wire  _zz_122_;
  wire  IBusCachedPlugin_fetchPc_preOutput_valid;
  wire  IBusCachedPlugin_fetchPc_preOutput_ready;
  wire [31:0] IBusCachedPlugin_fetchPc_preOutput_payload;
  wire  _zz_123_;
  wire  IBusCachedPlugin_fetchPc_output_valid;
  wire  IBusCachedPlugin_fetchPc_output_ready;
  wire [31:0] IBusCachedPlugin_fetchPc_output_payload;
  reg [31:0] IBusCachedPlugin_fetchPc_pcReg /* verilator public */ ;
  reg  IBusCachedPlugin_fetchPc_inc;
  reg  IBusCachedPlugin_fetchPc_propagatePc;
  reg [31:0] IBusCachedPlugin_fetchPc_pc;
  reg  IBusCachedPlugin_fetchPc_samplePcNext;
  reg  _zz_124_;
  wire  IBusCachedPlugin_iBusRsp_stages_0_input_valid;
  wire  IBusCachedPlugin_iBusRsp_stages_0_input_ready;
  wire [31:0] IBusCachedPlugin_iBusRsp_stages_0_input_payload;
  wire  IBusCachedPlugin_iBusRsp_stages_0_output_valid;
  wire  IBusCachedPlugin_iBusRsp_stages_0_output_ready;
  wire [31:0] IBusCachedPlugin_iBusRsp_stages_0_output_payload;
  reg  IBusCachedPlugin_iBusRsp_stages_0_halt;
  wire  IBusCachedPlugin_iBusRsp_stages_0_inputSample;
  wire  IBusCachedPlugin_iBusRsp_stages_1_input_valid;
  wire  IBusCachedPlugin_iBusRsp_stages_1_input_ready;
  wire [31:0] IBusCachedPlugin_iBusRsp_stages_1_input_payload;
  wire  IBusCachedPlugin_iBusRsp_stages_1_output_valid;
  wire  IBusCachedPlugin_iBusRsp_stages_1_output_ready;
  wire [31:0] IBusCachedPlugin_iBusRsp_stages_1_output_payload;
  reg  IBusCachedPlugin_iBusRsp_stages_1_halt;
  wire  IBusCachedPlugin_iBusRsp_stages_1_inputSample;
  wire  IBusCachedPlugin_stages_2_input_valid;
  wire  IBusCachedPlugin_stages_2_input_ready;
  wire [31:0] IBusCachedPlugin_stages_2_input_payload;
  wire  IBusCachedPlugin_stages_2_output_valid;
  wire  IBusCachedPlugin_stages_2_output_ready;
  wire [31:0] IBusCachedPlugin_stages_2_output_payload;
  reg  IBusCachedPlugin_stages_2_halt;
  wire  IBusCachedPlugin_stages_2_inputSample;
  wire  _zz_125_;
  wire  _zz_126_;
  wire  _zz_127_;
  wire  _zz_128_;
  wire  _zz_129_;
  reg  _zz_130_;
  wire  _zz_131_;
  reg  _zz_132_;
  reg [31:0] _zz_133_;
  wire  IBusCachedPlugin_iBusRsp_readyForError;
  wire  IBusCachedPlugin_iBusRsp_decodeInput_valid;
  wire  IBusCachedPlugin_iBusRsp_decodeInput_ready;
  wire [31:0] IBusCachedPlugin_iBusRsp_decodeInput_payload_pc;
  wire  IBusCachedPlugin_iBusRsp_decodeInput_payload_rsp_error;
  wire [31:0] IBusCachedPlugin_iBusRsp_decodeInput_payload_rsp_rawInDecode;
  wire  IBusCachedPlugin_iBusRsp_decodeInput_payload_isRvc;
  reg  IBusCachedPlugin_injector_nextPcCalc_valids_0;
  reg  IBusCachedPlugin_injector_nextPcCalc_0;
  reg  IBusCachedPlugin_injector_nextPcCalc_1;
  reg  IBusCachedPlugin_injector_nextPcCalc_2;
  reg  IBusCachedPlugin_injector_nextPcCalc_3;
  reg  IBusCachedPlugin_injector_decodeRemoved;
  wire  _zz_134_;
  reg [18:0] _zz_135_;
  wire  _zz_136_;
  reg [10:0] _zz_137_;
  wire  _zz_138_;
  reg [18:0] _zz_139_;
  wire  iBus_cmd_valid;
  wire  iBus_cmd_ready;
  reg [31:0] iBus_cmd_payload_address;
  wire [2:0] iBus_cmd_payload_size;
  wire  iBus_rsp_valid;
  wire [31:0] iBus_rsp_payload_data;
  wire  iBus_rsp_payload_error;
  wire  IBusCachedPlugin_iBusRspOutputHalt;
  reg  IBusCachedPlugin_redoFetch;
  wire  dBus_cmd_valid;
  wire  dBus_cmd_ready;
  wire  dBus_cmd_payload_wr;
  wire [31:0] dBus_cmd_payload_address;
  wire [31:0] dBus_cmd_payload_data;
  wire [3:0] dBus_cmd_payload_mask;
  wire [2:0] dBus_cmd_payload_length;
  wire  dBus_cmd_payload_last;
  wire  dBus_rsp_valid;
  wire [31:0] dBus_rsp_payload_data;
  wire  dBus_rsp_payload_error;
  wire [1:0] execute_DBusCachedPlugin_size;
  reg [31:0] _zz_140_;
  reg [31:0] writeBack_DBusCachedPlugin_rspShifted;
  wire  _zz_141_;
  reg [31:0] _zz_142_;
  wire  _zz_143_;
  reg [31:0] _zz_144_;
  reg [31:0] writeBack_DBusCachedPlugin_rspFormated;
  wire [30:0] _zz_145_;
  wire  _zz_146_;
  wire  _zz_147_;
  wire  _zz_148_;
  wire  _zz_149_;
  wire  _zz_150_;
  wire  _zz_151_;
  wire  _zz_152_;
  wire  _zz_153_;
  wire `BranchCtrlEnum_defaultEncoding_type _zz_154_;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type _zz_155_;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_156_;
  wire `Src2CtrlEnum_defaultEncoding_type _zz_157_;
  wire `AluCtrlEnum_defaultEncoding_type _zz_158_;
  wire `Src1CtrlEnum_defaultEncoding_type _zz_159_;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_160_;
  wire [4:0] decode_RegFilePlugin_regFileReadAddress1;
  wire [4:0] decode_RegFilePlugin_regFileReadAddress2;
  wire [31:0] decode_RegFilePlugin_rs1Data;
  wire [31:0] decode_RegFilePlugin_rs2Data;
  reg  writeBack_RegFilePlugin_regFileWrite_valid /* verilator public */ ;
  wire [4:0] writeBack_RegFilePlugin_regFileWrite_payload_address /* verilator public */ ;
  wire [31:0] writeBack_RegFilePlugin_regFileWrite_payload_data /* verilator public */ ;
  reg  _zz_161_;
  reg [31:0] execute_IntAluPlugin_bitwise;
  reg [31:0] _zz_162_;
  reg [31:0] _zz_163_;
  wire  _zz_164_;
  reg [19:0] _zz_165_;
  wire  _zz_166_;
  reg [19:0] _zz_167_;
  reg [31:0] _zz_168_;
  wire [31:0] execute_SrcPlugin_addSub;
  wire  execute_SrcPlugin_less;
  wire [4:0] execute_FullBarrelShifterPlugin_amplitude;
  reg [31:0] _zz_169_;
  wire [31:0] execute_FullBarrelShifterPlugin_reversed;
  reg [31:0] _zz_170_;
  reg  execute_MulPlugin_aSigned;
  reg  execute_MulPlugin_bSigned;
  wire [31:0] execute_MulPlugin_a;
  wire [31:0] execute_MulPlugin_b;
  wire [15:0] execute_MulPlugin_aULow;
  wire [15:0] execute_MulPlugin_bULow;
  wire [16:0] execute_MulPlugin_aSLow;
  wire [16:0] execute_MulPlugin_bSLow;
  wire [16:0] execute_MulPlugin_aHigh;
  wire [16:0] execute_MulPlugin_bHigh;
  wire [65:0] writeBack_MulPlugin_result;
  reg [32:0] memory_DivPlugin_rs1;
  reg [31:0] memory_DivPlugin_rs2;
  reg [64:0] memory_DivPlugin_accumulator;
  reg  memory_DivPlugin_div_needRevert;
  reg  memory_DivPlugin_div_counter_willIncrement;
  reg  memory_DivPlugin_div_counter_willClear;
  reg [5:0] memory_DivPlugin_div_counter_valueNext;
  reg [5:0] memory_DivPlugin_div_counter_value;
  wire  memory_DivPlugin_div_counter_willOverflowIfInc;
  wire  memory_DivPlugin_div_counter_willOverflow;
  reg  memory_DivPlugin_div_done;
  reg [31:0] memory_DivPlugin_div_result;
  wire [31:0] _zz_171_;
  wire [32:0] _zz_172_;
  wire [32:0] _zz_173_;
  wire [31:0] _zz_174_;
  wire  _zz_175_;
  wire  _zz_176_;
  reg [32:0] _zz_177_;
  reg  _zz_178_;
  reg  _zz_179_;
  wire  _zz_180_;
  reg  _zz_181_;
  reg [4:0] _zz_182_;
  reg [31:0] _zz_183_;
  wire  _zz_184_;
  wire  _zz_185_;
  wire  _zz_186_;
  wire  _zz_187_;
  wire  _zz_188_;
  wire  _zz_189_;
  reg  DebugPlugin_firstCycle;
  reg  DebugPlugin_secondCycle;
  reg  DebugPlugin_resetIt;
  reg  DebugPlugin_haltIt;
  reg  DebugPlugin_stepIt;
  reg  DebugPlugin_isPipActive;
  reg  DebugPlugin_isPipActive_regNext;
  wire  DebugPlugin_isPipBusy;
  reg  DebugPlugin_haltedByBreak;
  reg [31:0] DebugPlugin_busReadDataReg;
  reg  _zz_190_;
  reg  DebugPlugin_resetIt_regNext;
  wire  execute_BranchPlugin_eq;
  wire [2:0] _zz_191_;
  reg  _zz_192_;
  reg  _zz_193_;
  wire  _zz_194_;
  reg [19:0] _zz_195_;
  wire  _zz_196_;
  reg [10:0] _zz_197_;
  wire  _zz_198_;
  reg [18:0] _zz_199_;
  reg  _zz_200_;
  wire  execute_BranchPlugin_missAlignedTarget;
  reg [31:0] execute_BranchPlugin_branch_src1;
  reg [31:0] execute_BranchPlugin_branch_src2;
  wire  _zz_201_;
  reg [19:0] _zz_202_;
  wire  _zz_203_;
  reg [10:0] _zz_204_;
  wire  _zz_205_;
  reg [18:0] _zz_206_;
  wire [31:0] execute_BranchPlugin_branchAdder;
  wire [1:0] CsrPlugin_misa_base;
  wire [25:0] CsrPlugin_misa_extensions;
  wire [1:0] CsrPlugin_mtvec_mode;
  reg  [29:0] CsrPlugin_mtvec_base = 30'h00000008;   // bard0: made writable (was wire); power-on init = 0x20 via base<<2
  reg [31:0] CsrPlugin_mepc;
  reg  CsrPlugin_mstatus_MIE;
  reg  CsrPlugin_mstatus_MPIE;
  reg [1:0] CsrPlugin_mstatus_MPP;
  reg  CsrPlugin_mip_MEIP;
  reg  CsrPlugin_mip_MTIP;
  reg  CsrPlugin_mip_MSIP;
  reg  CsrPlugin_mie_MEIE;
  reg  CsrPlugin_mie_MTIE;
  reg  CsrPlugin_mie_MSIE;
  reg  CsrPlugin_mcause_interrupt;
  reg [3:0] CsrPlugin_mcause_exceptionCode;
  reg [31:0] CsrPlugin_mtval;
  reg [63:0] CsrPlugin_mcycle = 64'b0000000000000000000000000000000000000000000000000000000000000000;
  reg [63:0] CsrPlugin_minstret = 64'b0000000000000000000000000000000000000000000000000000000000000000;
  wire [31:0] CsrPlugin_medeleg;
  wire [31:0] CsrPlugin_mideleg;
  wire  _zz_207_;
  wire  _zz_208_;
  wire  _zz_209_;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValids_decode;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValids_execute;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValids_memory;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValids_writeBack;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_decode;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack;
  reg [3:0] CsrPlugin_exceptionPortCtrl_exceptionContext_code;
  reg [31:0] CsrPlugin_exceptionPortCtrl_exceptionContext_badAddr;
  wire [1:0] CsrPlugin_exceptionPortCtrl_exceptionTargetPrivilege;
  wire  decode_exception_agregat_valid;
  wire [3:0] decode_exception_agregat_payload_code;
  wire [31:0] decode_exception_agregat_payload_badAddr;
  wire [1:0] _zz_210_;
  wire  _zz_211_;
  reg  CsrPlugin_interrupt;
  reg [3:0] CsrPlugin_interruptCode /* verilator public */ ;
  reg [1:0] CsrPlugin_interruptTargetPrivilege;
  wire  CsrPlugin_exception;
  wire  CsrPlugin_lastStageWasWfi;
  reg  CsrPlugin_pipelineLiberator_done;
  wire  CsrPlugin_interruptJump /* verilator public */ ;
  reg  CsrPlugin_hadException;
  reg [1:0] CsrPlugin_targetPrivilege;
  reg [3:0] CsrPlugin_trapCause;
  wire  execute_CsrPlugin_blockedBySideEffects;
  reg  execute_CsrPlugin_illegalAccess;
  reg  execute_CsrPlugin_illegalInstruction;
  reg [31:0] execute_CsrPlugin_readData;
  wire  execute_CsrPlugin_writeInstruction;
  wire  execute_CsrPlugin_readInstruction;
  wire  execute_CsrPlugin_writeEnable;
  wire  execute_CsrPlugin_readEnable;
  reg [31:0] execute_CsrPlugin_writeData;
  wire [11:0] execute_CsrPlugin_csrAddress;
  reg `EnvCtrlEnum_defaultEncoding_type decode_to_execute_ENV_CTRL;
  reg `EnvCtrlEnum_defaultEncoding_type execute_to_memory_ENV_CTRL;
  reg `EnvCtrlEnum_defaultEncoding_type memory_to_writeBack_ENV_CTRL;
  reg `Src1CtrlEnum_defaultEncoding_type decode_to_execute_SRC1_CTRL;
  reg [31:0] decode_to_execute_PC;
  reg [31:0] execute_to_memory_PC;
  reg [31:0] memory_to_writeBack_PC;
  reg [31:0] decode_to_execute_INSTRUCTION;
  reg [31:0] execute_to_memory_INSTRUCTION;
  reg [31:0] memory_to_writeBack_INSTRUCTION;
  reg  decode_to_execute_PREDICTION_HAD_BRANCHED2;
  reg [1:0] execute_to_memory_MEMORY_ADDRESS_LOW;
  reg [1:0] memory_to_writeBack_MEMORY_ADDRESS_LOW;
  reg  decode_to_execute_IS_RS2_SIGNED;
  reg `AluCtrlEnum_defaultEncoding_type decode_to_execute_ALU_CTRL;
  reg [33:0] execute_to_memory_MUL_HH;
  reg [33:0] memory_to_writeBack_MUL_HH;
  reg [33:0] execute_to_memory_MUL_LH;
  reg `AluBitwiseCtrlEnum_defaultEncoding_type decode_to_execute_ALU_BITWISE_CTRL;
  reg  decode_to_execute_BYPASSABLE_EXECUTE_STAGE;
  reg  decode_to_execute_CSR_READ_OPCODE;
  reg  decode_to_execute_MEMORY_ENABLE;
  reg  execute_to_memory_MEMORY_ENABLE;
  reg  memory_to_writeBack_MEMORY_ENABLE;
  reg  decode_to_execute_DO_EBREAK;
  reg  execute_to_memory_BRANCH_DO;
  reg  decode_to_execute_MEMORY_WR;
  reg  execute_to_memory_MEMORY_WR;
  reg  memory_to_writeBack_MEMORY_WR;
  reg  decode_to_execute_IS_DIV;
  reg  execute_to_memory_IS_DIV;
  reg [51:0] memory_to_writeBack_MUL_LOW;
  reg  decode_to_execute_MEMORY_MANAGMENT;
  reg  decode_to_execute_SRC_LESS_UNSIGNED;
  reg  decode_to_execute_BYPASSABLE_MEMORY_STAGE;
  reg  execute_to_memory_BYPASSABLE_MEMORY_STAGE;
  reg [31:0] execute_to_memory_REGFILE_WRITE_DATA;
  reg [31:0] memory_to_writeBack_REGFILE_WRITE_DATA;
  reg  decode_to_execute_IS_RS1_SIGNED;
  reg `BranchCtrlEnum_defaultEncoding_type decode_to_execute_BRANCH_CTRL;
  reg  decode_to_execute_FLUSH_ALL;
  reg  execute_to_memory_FLUSH_ALL;
  reg  decode_to_execute_IS_CSR;
  reg [33:0] execute_to_memory_MUL_HL;
  reg  decode_to_execute_IS_MUL;
  reg  execute_to_memory_IS_MUL;
  reg  memory_to_writeBack_IS_MUL;
  reg  decode_to_execute_CSR_WRITE_OPCODE;
  reg  decode_to_execute_SRC_USE_SUB_LESS;
  reg `ShiftCtrlEnum_defaultEncoding_type decode_to_execute_SHIFT_CTRL;
  reg `ShiftCtrlEnum_defaultEncoding_type execute_to_memory_SHIFT_CTRL;
  reg [31:0] execute_to_memory_SHIFT_RIGHT;
  reg  decode_to_execute_REGFILE_WRITE_VALID;
  reg  execute_to_memory_REGFILE_WRITE_VALID;
  reg  memory_to_writeBack_REGFILE_WRITE_VALID;
  reg [31:0] decode_to_execute_RS1;
  reg [31:0] decode_to_execute_RS2;
  reg [31:0] decode_to_execute_FORMAL_PC_NEXT;
  reg [31:0] execute_to_memory_FORMAL_PC_NEXT;
  reg [31:0] memory_to_writeBack_FORMAL_PC_NEXT;
  reg [31:0] execute_to_memory_MUL_LL;
  reg [31:0] execute_to_memory_BRANCH_CALC;
  reg `Src2CtrlEnum_defaultEncoding_type decode_to_execute_SRC2_CTRL;
  reg [2:0] _zz_212_;
  reg [31:0] _zz_213_;
  wire [0:0] _zz_214_;
  wire [3:0] _zz_215_;
  wire  _zz_216_;
  wire  _zz_217_;
  wire  _zz_218_;
  wire  _zz_219_;
  reg  _zz_220_;
  reg  _zz_221_;
  reg [2:0] _zz_222_;
  reg [2:0] _zz_223_;
  wire [2:0] _zz_224_;
  wire  _zz_225_;
  reg  _zz_226_;
  reg  _zz_227_;
  reg  _zz_228_;
  wire  _zz_229_;
  wire [31:0] _zz_230_;
  wire [7:0] _zz_231_;
  wire  _zz_232_;
  wire  _zz_233_;
  wire  _zz_234_;
  wire [31:0] _zz_235_;
  wire [1:0] _zz_236_;
  wire  _zz_237_;
  wire [0:0] _zz_238_;
  wire [3:0] _zz_239_;
  wire [0:0] _zz_240_;
  wire [3:0] _zz_241_;
  reg  _zz_242_;
  reg [31:0] RegFilePlugin_regFile [0:31] /* verilator public */ ;
  assign _zz_344_ = (memory_arbitration_isValid && memory_IS_DIV);
  assign _zz_345_ = (! memory_DivPlugin_div_done);
  assign _zz_346_ = (execute_arbitration_isValid && execute_DO_EBREAK);
  assign _zz_347_ = ((memory_arbitration_isValid || writeBack_arbitration_isValid) == 1'b0);
  assign _zz_348_ = (DebugPlugin_stepIt && _zz_101_);
  assign _zz_349_ = (CsrPlugin_hadException || CsrPlugin_interruptJump);
  assign _zz_350_ = (writeBack_arbitration_isValid && (writeBack_ENV_CTRL == `EnvCtrlEnum_defaultEncoding_XRET));
  assign _zz_351_ = (IBusCachedPlugin_fetchPc_preOutput_valid && IBusCachedPlugin_fetchPc_preOutput_ready);
  assign _zz_352_ = (! memory_arbitration_isStuck);
  assign _zz_353_ = debug_bus_cmd_payload_address[7 : 2];
  assign _zz_354_ = writeBack_INSTRUCTION[13 : 12];
  assign _zz_355_ = execute_INSTRUCTION[13 : 12];
  assign _zz_356_ = writeBack_INSTRUCTION[13 : 12];
  assign _zz_357_ = writeBack_INSTRUCTION[29 : 28];
  assign _zz_358_ = execute_INSTRUCTION[13];
  assign _zz_359_ = (_zz_118_ - (4'b0001));
  assign _zz_360_ = {IBusCachedPlugin_fetchPc_inc,(2'b00)};
  assign _zz_361_ = {29'd0, _zz_360_};
  assign _zz_362_ = {{{decode_INSTRUCTION[31],decode_INSTRUCTION[7]},decode_INSTRUCTION[30 : 25]},decode_INSTRUCTION[11 : 8]};
  assign _zz_363_ = {{_zz_135_,{{{decode_INSTRUCTION[31],decode_INSTRUCTION[7]},decode_INSTRUCTION[30 : 25]},decode_INSTRUCTION[11 : 8]}},1'b0};
  assign _zz_364_ = {{{decode_INSTRUCTION[31],decode_INSTRUCTION[19 : 12]},decode_INSTRUCTION[20]},decode_INSTRUCTION[30 : 21]};
  assign _zz_365_ = {{{decode_INSTRUCTION[31],decode_INSTRUCTION[7]},decode_INSTRUCTION[30 : 25]},decode_INSTRUCTION[11 : 8]};
  assign _zz_366_ = (writeBack_MEMORY_WR ? (3'b111) : (3'b101));
  assign _zz_367_ = (writeBack_MEMORY_WR ? (3'b110) : (3'b100));
  assign _zz_368_ = _zz_145_[0 : 0];
  assign _zz_369_ = _zz_145_[4 : 4];
  assign _zz_370_ = _zz_145_[5 : 5];
  assign _zz_371_ = _zz_145_[6 : 6];
  assign _zz_372_ = _zz_145_[7 : 7];
  assign _zz_373_ = _zz_145_[8 : 8];
  assign _zz_374_ = _zz_145_[9 : 9];
  assign _zz_375_ = _zz_145_[10 : 10];
  assign _zz_376_ = _zz_145_[13 : 13];
  assign _zz_377_ = _zz_145_[14 : 14];
  assign _zz_378_ = _zz_145_[19 : 19];
  assign _zz_379_ = _zz_145_[20 : 20];
  assign _zz_380_ = _zz_145_[25 : 25];
  assign _zz_381_ = _zz_145_[26 : 26];
  assign _zz_382_ = _zz_145_[27 : 27];
  assign _zz_383_ = _zz_145_[28 : 28];
  assign _zz_384_ = _zz_145_[29 : 29];
  assign _zz_385_ = execute_SRC_LESS;
  assign _zz_386_ = (3'b100);
  assign _zz_387_ = execute_INSTRUCTION[19 : 15];
  assign _zz_388_ = execute_INSTRUCTION[31 : 20];
  assign _zz_389_ = {execute_INSTRUCTION[31 : 25],execute_INSTRUCTION[11 : 7]};
  assign _zz_390_ = ($signed(_zz_391_) + $signed(_zz_395_));
  assign _zz_391_ = ($signed(_zz_392_) + $signed(_zz_393_));
  assign _zz_392_ = execute_SRC1;
  assign _zz_393_ = (execute_SRC_USE_SUB_LESS ? (~ execute_SRC2) : execute_SRC2);
  assign _zz_394_ = (execute_SRC_USE_SUB_LESS ? _zz_396_ : _zz_397_);
  assign _zz_395_ = {{30{_zz_394_[1]}}, _zz_394_};
  assign _zz_396_ = (2'b01);
  assign _zz_397_ = (2'b00);
  assign _zz_398_ = ($signed(_zz_400_) >>> execute_FullBarrelShifterPlugin_amplitude);
  assign _zz_399_ = _zz_398_[31 : 0];
  assign _zz_400_ = {((execute_SHIFT_CTRL == `ShiftCtrlEnum_defaultEncoding_SRA_1) && execute_FullBarrelShifterPlugin_reversed[31]),execute_FullBarrelShifterPlugin_reversed};
  assign _zz_401_ = ($signed(_zz_402_) + $signed(_zz_407_));
  assign _zz_402_ = ($signed(_zz_403_) + $signed(_zz_405_));
  assign _zz_403_ = (52'b0000000000000000000000000000000000000000000000000000);
  assign _zz_404_ = {1'b0,memory_MUL_LL};
  assign _zz_405_ = {{19{_zz_404_[32]}}, _zz_404_};
  assign _zz_406_ = ({16'd0,memory_MUL_LH} <<< 16);
  assign _zz_407_ = {{2{_zz_406_[49]}}, _zz_406_};
  assign _zz_408_ = ({16'd0,memory_MUL_HL} <<< 16);
  assign _zz_409_ = {{2{_zz_408_[49]}}, _zz_408_};
  assign _zz_410_ = {{14{writeBack_MUL_LOW[51]}}, writeBack_MUL_LOW};
  assign _zz_411_ = ({32'd0,writeBack_MUL_HH} <<< 32);
  assign _zz_412_ = writeBack_MUL_LOW[31 : 0];
  assign _zz_413_ = writeBack_MulPlugin_result[63 : 32];
  assign _zz_414_ = memory_DivPlugin_div_counter_willIncrement;
  assign _zz_415_ = {5'd0, _zz_414_};
  assign _zz_416_ = {1'd0, memory_DivPlugin_rs2};
  assign _zz_417_ = {_zz_171_,(! _zz_173_[32])};
  assign _zz_418_ = _zz_173_[31:0];
  assign _zz_419_ = _zz_172_[31:0];
  assign _zz_420_ = _zz_421_;
  assign _zz_421_ = _zz_422_;
  assign _zz_422_ = ({1'b0,(memory_DivPlugin_div_needRevert ? (~ _zz_174_) : _zz_174_)} + _zz_424_);
  assign _zz_423_ = memory_DivPlugin_div_needRevert;
  assign _zz_424_ = {32'd0, _zz_423_};
  assign _zz_425_ = _zz_176_;
  assign _zz_426_ = {32'd0, _zz_425_};
  assign _zz_427_ = _zz_175_;
  assign _zz_428_ = {31'd0, _zz_427_};
  assign _zz_429_ = execute_INSTRUCTION[31 : 20];
  assign _zz_430_ = {{{execute_INSTRUCTION[31],execute_INSTRUCTION[19 : 12]},execute_INSTRUCTION[20]},execute_INSTRUCTION[30 : 21]};
  assign _zz_431_ = {{{execute_INSTRUCTION[31],execute_INSTRUCTION[7]},execute_INSTRUCTION[30 : 25]},execute_INSTRUCTION[11 : 8]};
  assign _zz_432_ = {_zz_195_,execute_INSTRUCTION[31 : 20]};
  assign _zz_433_ = {{_zz_197_,{{{execute_INSTRUCTION[31],execute_INSTRUCTION[19 : 12]},execute_INSTRUCTION[20]},execute_INSTRUCTION[30 : 21]}},1'b0};
  assign _zz_434_ = {{_zz_199_,{{{execute_INSTRUCTION[31],execute_INSTRUCTION[7]},execute_INSTRUCTION[30 : 25]},execute_INSTRUCTION[11 : 8]}},1'b0};
  assign _zz_435_ = execute_INSTRUCTION[31 : 20];
  assign _zz_436_ = {{{execute_INSTRUCTION[31],execute_INSTRUCTION[19 : 12]},execute_INSTRUCTION[20]},execute_INSTRUCTION[30 : 21]};
  assign _zz_437_ = {{{execute_INSTRUCTION[31],execute_INSTRUCTION[7]},execute_INSTRUCTION[30 : 25]},execute_INSTRUCTION[11 : 8]};
  assign _zz_438_ = (3'b100);
  assign _zz_439_ = (_zz_210_ & (~ _zz_440_));
  assign _zz_440_ = (_zz_210_ - (2'b01));
  assign _zz_441_ = execute_CsrPlugin_writeData[7 : 7];
  assign _zz_442_ = execute_CsrPlugin_writeData[3 : 3];
  assign _zz_443_ = execute_CsrPlugin_writeData[3 : 3];
  assign _zz_444_ = execute_CsrPlugin_writeData[11 : 11];
  assign _zz_445_ = execute_CsrPlugin_writeData[7 : 7];
  assign _zz_446_ = execute_CsrPlugin_writeData[3 : 3];
  assign _zz_447_ = 1'b1;
  assign _zz_448_ = 1'b1;
  assign _zz_449_ = {_zz_122_,_zz_121_};
  assign _zz_450_ = decode_INSTRUCTION[31];
  assign _zz_451_ = decode_INSTRUCTION[19 : 12];
  assign _zz_452_ = decode_INSTRUCTION[20];
  assign _zz_453_ = decode_INSTRUCTION[31];
  assign _zz_454_ = decode_INSTRUCTION[7];
  assign _zz_455_ = (32'b00000000000100000011000001010000);
  assign _zz_456_ = ((decode_INSTRUCTION & (32'b00000000000000000000000001011000)) == (32'b00000000000000000000000000000000));
  assign _zz_457_ = ((decode_INSTRUCTION & _zz_464_) == (32'b00000000000000000000000001000000));
  assign _zz_458_ = {_zz_151_,{_zz_465_,{_zz_466_,_zz_467_}}};
  assign _zz_459_ = ((decode_INSTRUCTION & _zz_468_) == (32'b00000010000000000000000000110000));
  assign _zz_460_ = (1'b0);
  assign _zz_461_ = (_zz_146_ != (1'b0));
  assign _zz_462_ = ({_zz_469_,_zz_470_} != (3'b000));
  assign _zz_463_ = {(_zz_471_ != _zz_472_),{_zz_473_,{_zz_474_,_zz_475_}}};
  assign _zz_464_ = (32'b00000000000000000000000001000000);
  assign _zz_465_ = ((decode_INSTRUCTION & _zz_476_) == (32'b00000000000000000100000000100000));
  assign _zz_466_ = (_zz_477_ == _zz_478_);
  assign _zz_467_ = (_zz_479_ == _zz_480_);
  assign _zz_468_ = (32'b00000010000000000100000001110100);
  assign _zz_469_ = (_zz_481_ == _zz_482_);
  assign _zz_470_ = {_zz_483_,_zz_484_};
  assign _zz_471_ = {_zz_148_,{_zz_485_,_zz_486_}};
  assign _zz_472_ = (3'b000);
  assign _zz_473_ = ({_zz_487_,_zz_488_} != (2'b00));
  assign _zz_474_ = (_zz_489_ != _zz_490_);
  assign _zz_475_ = {_zz_491_,{_zz_492_,_zz_493_}};
  assign _zz_476_ = (32'b00000000000000000100000000100000);
  assign _zz_477_ = (decode_INSTRUCTION & (32'b00000000000000000000000000110000));
  assign _zz_478_ = (32'b00000000000000000000000000010000);
  assign _zz_479_ = (decode_INSTRUCTION & (32'b00000010000000000000000000100000));
  assign _zz_480_ = (32'b00000000000000000000000000100000);
  assign _zz_481_ = (decode_INSTRUCTION & (32'b00000000000000000001000001001000));
  assign _zz_482_ = (32'b00000000000000000001000000001000);
  assign _zz_483_ = ((decode_INSTRUCTION & (32'b00000000000000000000000000110100)) == (32'b00000000000000000000000000100000));
  assign _zz_484_ = ((decode_INSTRUCTION & (32'b00000000000000000000000001100100)) == (32'b00000000000000000000000000100000));
  assign _zz_485_ = _zz_153_;
  assign _zz_486_ = _zz_147_;
  assign _zz_487_ = _zz_153_;
  assign _zz_488_ = ((decode_INSTRUCTION & _zz_494_) == (32'b00000000000000000000000000000100));
  assign _zz_489_ = {(_zz_495_ == _zz_496_),(_zz_497_ == _zz_498_)};
  assign _zz_490_ = (2'b00);
  assign _zz_491_ = ((_zz_499_ == _zz_500_) != (1'b0));
  assign _zz_492_ = ({_zz_501_,_zz_502_} != (5'b00000));
  assign _zz_493_ = {(_zz_503_ != _zz_504_),{_zz_505_,{_zz_506_,_zz_507_}}};
  assign _zz_494_ = (32'b00000000000000000000000001001100);
  assign _zz_495_ = (decode_INSTRUCTION & (32'b00000000000000000000000001100100));
  assign _zz_496_ = (32'b00000000000000000000000000100100);
  assign _zz_497_ = (decode_INSTRUCTION & (32'b00000000000000000100000000010100));
  assign _zz_498_ = (32'b00000000000000000100000000010000);
  assign _zz_499_ = (decode_INSTRUCTION & (32'b00000000000000000110000000010100));
  assign _zz_500_ = (32'b00000000000000000010000000010000);
  assign _zz_501_ = ((decode_INSTRUCTION & _zz_508_) == (32'b00000000000000000000000000000000));
  assign _zz_502_ = {(_zz_509_ == _zz_510_),{_zz_152_,{_zz_511_,_zz_512_}}};
  assign _zz_503_ = {(_zz_513_ == _zz_514_),(_zz_515_ == _zz_516_)};
  assign _zz_504_ = (2'b00);
  assign _zz_505_ = ({_zz_148_,{_zz_517_,_zz_518_}} != (3'b000));
  assign _zz_506_ = ({_zz_519_,_zz_520_} != (3'b000));
  assign _zz_507_ = {(_zz_521_ != _zz_522_),{_zz_523_,{_zz_524_,_zz_525_}}};
  assign _zz_508_ = (32'b00000000000000000000000001000100);
  assign _zz_509_ = (decode_INSTRUCTION & (32'b00000000000000000000000000011000));
  assign _zz_510_ = (32'b00000000000000000000000000000000);
  assign _zz_511_ = (_zz_526_ == _zz_527_);
  assign _zz_512_ = (_zz_528_ == _zz_529_);
  assign _zz_513_ = (decode_INSTRUCTION & (32'b00000000000000000001000001010000));
  assign _zz_514_ = (32'b00000000000000000001000001010000);
  assign _zz_515_ = (decode_INSTRUCTION & (32'b00000000000000000010000001010000));
  assign _zz_516_ = (32'b00000000000000000010000001010000);
  assign _zz_517_ = (_zz_530_ == _zz_531_);
  assign _zz_518_ = (_zz_532_ == _zz_533_);
  assign _zz_519_ = _zz_148_;
  assign _zz_520_ = {_zz_150_,_zz_149_};
  assign _zz_521_ = {_zz_534_,_zz_535_};
  assign _zz_522_ = (2'b00);
  assign _zz_523_ = ({_zz_536_,_zz_537_} != (3'b000));
  assign _zz_524_ = (_zz_538_ != _zz_539_);
  assign _zz_525_ = {_zz_540_,{_zz_541_,_zz_542_}};
  assign _zz_526_ = (decode_INSTRUCTION & (32'b00000000000000000110000000000100));
  assign _zz_527_ = (32'b00000000000000000010000000000000);
  assign _zz_528_ = (decode_INSTRUCTION & (32'b00000000000000000101000000000100));
  assign _zz_529_ = (32'b00000000000000000001000000000000);
  assign _zz_530_ = (decode_INSTRUCTION & (32'b00000000000000000000000000001100));
  assign _zz_531_ = (32'b00000000000000000000000000000100);
  assign _zz_532_ = (decode_INSTRUCTION & (32'b00000000000000000000000001110000));
  assign _zz_533_ = (32'b00000000000000000000000000100000);
  assign _zz_534_ = ((decode_INSTRUCTION & (32'b00000000000000000111000000110100)) == (32'b00000000000000000101000000010000));
  assign _zz_535_ = ((decode_INSTRUCTION & (32'b00000010000000000111000001100100)) == (32'b00000000000000000101000000100000));
  assign _zz_536_ = ((decode_INSTRUCTION & _zz_543_) == (32'b01000000000000000001000000010000));
  assign _zz_537_ = {(_zz_544_ == _zz_545_),(_zz_546_ == _zz_547_)};
  assign _zz_538_ = ((decode_INSTRUCTION & _zz_548_) == (32'b00000000000000000000000000100000));
  assign _zz_539_ = (1'b0);
  assign _zz_540_ = ((_zz_549_ == _zz_550_) != (1'b0));
  assign _zz_541_ = ({_zz_551_,_zz_552_} != (2'b00));
  assign _zz_542_ = {(_zz_553_ != _zz_554_),{_zz_555_,{_zz_556_,_zz_557_}}};
  assign _zz_543_ = (32'b01000000000000000011000001010100);
  assign _zz_544_ = (decode_INSTRUCTION & (32'b00000000000000000111000000110100));
  assign _zz_545_ = (32'b00000000000000000001000000010000);
  assign _zz_546_ = (decode_INSTRUCTION & (32'b00000010000000000111000001010100));
  assign _zz_547_ = (32'b00000000000000000001000000010000);
  assign _zz_548_ = (32'b00000000000000000000000000100000);
  assign _zz_549_ = (decode_INSTRUCTION & (32'b00000000000000000000000000001000));
  assign _zz_550_ = (32'b00000000000000000000000000001000);
  assign _zz_551_ = ((decode_INSTRUCTION & _zz_558_) == (32'b00000000000000000001000000000000));
  assign _zz_552_ = _zz_151_;
  assign _zz_553_ = {_zz_151_,(_zz_559_ == _zz_560_)};
  assign _zz_554_ = (2'b00);
  assign _zz_555_ = ({_zz_151_,{_zz_561_,_zz_562_}} != (5'b00000));
  assign _zz_556_ = ({_zz_563_,_zz_564_} != (2'b00));
  assign _zz_557_ = {(_zz_565_ != _zz_566_),{_zz_567_,{_zz_568_,_zz_569_}}};
  assign _zz_558_ = (32'b00000000000000000001000000000000);
  assign _zz_559_ = (decode_INSTRUCTION & (32'b00000000000000000011000000000000));
  assign _zz_560_ = (32'b00000000000000000010000000000000);
  assign _zz_561_ = ((decode_INSTRUCTION & _zz_570_) == (32'b00000000000000000010000000010000));
  assign _zz_562_ = {(_zz_571_ == _zz_572_),{_zz_573_,_zz_574_}};
  assign _zz_563_ = ((decode_INSTRUCTION & _zz_575_) == (32'b00000000000000000010000000000000));
  assign _zz_564_ = ((decode_INSTRUCTION & _zz_576_) == (32'b00000000000000000001000000000000));
  assign _zz_565_ = ((decode_INSTRUCTION & _zz_577_) == (32'b00000000000000000000000001010000));
  assign _zz_566_ = (1'b0);
  assign _zz_567_ = ({_zz_578_,{_zz_579_,_zz_580_}} != (3'b000));
  assign _zz_568_ = ({_zz_581_,_zz_582_} != (6'b000000));
  assign _zz_569_ = {(_zz_583_ != _zz_584_),{_zz_585_,{_zz_586_,_zz_587_}}};
  assign _zz_570_ = (32'b00000000000000000010000000110000);
  assign _zz_571_ = (decode_INSTRUCTION & (32'b00000000000000000001000000110000));
  assign _zz_572_ = (32'b00000000000000000000000000010000);
  assign _zz_573_ = ((decode_INSTRUCTION & _zz_588_) == (32'b00000000000000000010000000100000));
  assign _zz_574_ = ((decode_INSTRUCTION & _zz_589_) == (32'b00000000000000000000000000100000));
  assign _zz_575_ = (32'b00000000000000000010000000010000);
  assign _zz_576_ = (32'b00000000000000000101000000000000);
  assign _zz_577_ = (32'b00010000000000000011000001010000);
  assign _zz_578_ = ((decode_INSTRUCTION & _zz_590_) == (32'b00000000000000000000000001000000));
  assign _zz_579_ = (_zz_591_ == _zz_592_);
  assign _zz_580_ = (_zz_593_ == _zz_594_);
  assign _zz_581_ = _zz_148_;
  assign _zz_582_ = {_zz_595_,{_zz_596_,_zz_597_}};
  assign _zz_583_ = (_zz_598_ == _zz_599_);
  assign _zz_584_ = (1'b0);
  assign _zz_585_ = (_zz_600_ != (1'b0));
  assign _zz_586_ = (_zz_601_ != _zz_602_);
  assign _zz_587_ = {_zz_603_,{_zz_604_,_zz_605_}};
  assign _zz_588_ = (32'b00000010000000000010000001100000);
  assign _zz_589_ = (32'b00000010000000000011000000100000);
  assign _zz_590_ = (32'b00000000000000000000000001000100);
  assign _zz_591_ = (decode_INSTRUCTION & (32'b01000000000000000000000000110000));
  assign _zz_592_ = (32'b01000000000000000000000000110000);
  assign _zz_593_ = (decode_INSTRUCTION & (32'b00000000000000000010000000010100));
  assign _zz_594_ = (32'b00000000000000000010000000010000);
  assign _zz_595_ = ((decode_INSTRUCTION & (32'b00000000000000000001000000010000)) == (32'b00000000000000000001000000010000));
  assign _zz_596_ = ((decode_INSTRUCTION & _zz_606_) == (32'b00000000000000000010000000010000));
  assign _zz_597_ = {(_zz_607_ == _zz_608_),{_zz_150_,_zz_149_}};
  assign _zz_598_ = (decode_INSTRUCTION & (32'b00000010000000000100000001100100));
  assign _zz_599_ = (32'b00000010000000000100000000100000);
  assign _zz_600_ = ((decode_INSTRUCTION & (32'b00000000000000000001000001001000)) == (32'b00000000000000000000000000001000));
  assign _zz_601_ = {_zz_148_,_zz_147_};
  assign _zz_602_ = (2'b00);
  assign _zz_603_ = ((_zz_609_ == _zz_610_) != (1'b0));
  assign _zz_604_ = ({_zz_611_,_zz_612_} != (3'b000));
  assign _zz_605_ = (_zz_146_ != (1'b0));
  assign _zz_606_ = (32'b00000000000000000010000000010000);
  assign _zz_607_ = (decode_INSTRUCTION & (32'b00000000000000000000000001010000));
  assign _zz_608_ = (32'b00000000000000000000000000010000);
  assign _zz_609_ = (decode_INSTRUCTION & (32'b00000000000000000000000001011000));
  assign _zz_610_ = (32'b00000000000000000000000001000000);
  assign _zz_611_ = ((decode_INSTRUCTION & (32'b00000000000000000000000001010000)) == (32'b00000000000000000000000001000000));
  assign _zz_612_ = {((decode_INSTRUCTION & (32'b00000000000000000000000000111000)) == (32'b00000000000000000000000000000000)),((decode_INSTRUCTION & (32'b00000000000100000011000001000000)) == (32'b00000000000000000000000001000000))};
  assign _zz_613_ = (32'b00000000000000000001000001111111);
  assign _zz_614_ = (decode_INSTRUCTION & (32'b00000000000000000010000001111111));
  assign _zz_615_ = (32'b00000000000000000010000001110011);
  assign _zz_616_ = ((decode_INSTRUCTION & (32'b00000000000000000100000001111111)) == (32'b00000000000000000100000001100011));
  assign _zz_617_ = ((decode_INSTRUCTION & (32'b00000000000000000010000001111111)) == (32'b00000000000000000010000000010011));
  assign _zz_618_ = {((decode_INSTRUCTION & (32'b00000000000000000110000000111111)) == (32'b00000000000000000000000000100011)),{((decode_INSTRUCTION & (32'b00000000000000000010000001111111)) == (32'b00000000000000000000000000000011)),{((decode_INSTRUCTION & _zz_619_) == (32'b00000000000000000000000000000011)),{(_zz_620_ == _zz_621_),{_zz_622_,{_zz_623_,_zz_624_}}}}}};
  assign _zz_619_ = (32'b00000000000000000101000001011111);
  assign _zz_620_ = (decode_INSTRUCTION & (32'b00000000000000000111000001111011));
  assign _zz_621_ = (32'b00000000000000000000000001100011);
  assign _zz_622_ = ((decode_INSTRUCTION & (32'b00000000000000000111000001111111)) == (32'b00000000000000000100000000001111));
  assign _zz_623_ = ((decode_INSTRUCTION & (32'b11111100000000000000000001111111)) == (32'b00000000000000000000000000110011));
  assign _zz_624_ = {((decode_INSTRUCTION & (32'b00000001111100000111000001111111)) == (32'b00000000000000000101000000001111)),{((decode_INSTRUCTION & (32'b10111100000000000111000001111111)) == (32'b00000000000000000101000000010011)),{((decode_INSTRUCTION & _zz_625_) == (32'b00000000000000000001000000010011)),{(_zz_626_ == _zz_627_),{_zz_628_,{_zz_629_,_zz_630_}}}}}};
  assign _zz_625_ = (32'b11111100000000000011000001111111);
  assign _zz_626_ = (decode_INSTRUCTION & (32'b10111110000000000111000001111111));
  assign _zz_627_ = (32'b00000000000000000101000000110011);
  assign _zz_628_ = ((decode_INSTRUCTION & (32'b10111110000000000111000001111111)) == (32'b00000000000000000000000000110011));
  assign _zz_629_ = ((decode_INSTRUCTION & (32'b11011111111111111111111111111111)) == (32'b00010000001000000000000001110011));
  assign _zz_630_ = ((decode_INSTRUCTION & (32'b11111111111111111111111111111111)) == (32'b00000000000100000000000001110011));
  assign _zz_631_ = execute_INSTRUCTION[31];
  assign _zz_632_ = execute_INSTRUCTION[31];
  assign _zz_633_ = execute_INSTRUCTION[7];
  always @ (posedge clk) begin
    if(_zz_61_) begin
      RegFilePlugin_regFile[writeBack_RegFilePlugin_regFileWrite_payload_address] <= writeBack_RegFilePlugin_regFileWrite_payload_data;
    end
  end

  always @ (posedge clk) begin
    if(_zz_447_) begin
      _zz_275_ <= RegFilePlugin_regFile[decode_RegFilePlugin_regFileReadAddress1];
    end
  end

  always @ (posedge clk) begin
    if(_zz_448_) begin
      _zz_276_ <= RegFilePlugin_regFile[decode_RegFilePlugin_regFileReadAddress2];
    end
  end

  InstructionCache IBusCachedPlugin_cache ( 
    .io_flush_cmd_valid(_zz_243_),
    .io_flush_cmd_ready(_zz_278_),
    .io_flush_rsp(_zz_279_),
    .io_cpu_prefetch_isValid(IBusCachedPlugin_iBusRsp_stages_0_input_valid),
    .io_cpu_prefetch_haltIt(_zz_280_),
    .io_cpu_prefetch_pc(IBusCachedPlugin_iBusRsp_stages_0_input_payload),
    .io_cpu_fetch_isValid(IBusCachedPlugin_iBusRsp_stages_1_input_valid),
    .io_cpu_fetch_isStuck(_zz_244_),
    .io_cpu_fetch_isRemoved(_zz_245_),
    .io_cpu_fetch_pc(IBusCachedPlugin_iBusRsp_stages_1_input_payload),
    .io_cpu_fetch_data(_zz_281_),
    .io_cpu_fetch_mmuBus_cmd_isValid(_zz_283_),
    .io_cpu_fetch_mmuBus_cmd_virtualAddress(_zz_284_),
    .io_cpu_fetch_mmuBus_cmd_bypassTranslation(_zz_285_),
    .io_cpu_fetch_mmuBus_rsp_physicalAddress(_zz_108_),
    .io_cpu_fetch_mmuBus_rsp_isIoAccess(_zz_246_),
    .io_cpu_fetch_mmuBus_rsp_allowRead(_zz_247_),
    .io_cpu_fetch_mmuBus_rsp_allowWrite(_zz_248_),
    .io_cpu_fetch_mmuBus_rsp_allowExecute(_zz_249_),
    .io_cpu_fetch_mmuBus_rsp_allowUser(_zz_250_),
    .io_cpu_fetch_mmuBus_rsp_miss(_zz_251_),
    .io_cpu_fetch_mmuBus_rsp_hit(_zz_252_),
    .io_cpu_fetch_mmuBus_end(_zz_286_),
    .io_cpu_fetch_physicalAddress(_zz_282_),
    .io_cpu_decode_isValid(IBusCachedPlugin_stages_2_input_valid),
    .io_cpu_decode_isStuck(_zz_253_),
    .io_cpu_decode_pc(IBusCachedPlugin_stages_2_input_payload),
    .io_cpu_decode_physicalAddress(_zz_292_),
    .io_cpu_decode_data(_zz_290_),
    .io_cpu_decode_cacheMiss(_zz_291_),
    .io_cpu_decode_error(_zz_287_),
    .io_cpu_decode_mmuMiss(_zz_288_),
    .io_cpu_decode_illegalAccess(_zz_289_),
    .io_cpu_decode_isUser(_zz_254_),
    .io_cpu_fill_valid(IBusCachedPlugin_redoFetch),
    .io_cpu_fill_payload(_zz_292_),
    .io_mem_cmd_valid(_zz_293_),
    .io_mem_cmd_ready(iBus_cmd_ready),
    .io_mem_cmd_payload_address(_zz_294_),
    .io_mem_cmd_payload_size(_zz_295_),
    .io_mem_rsp_valid(iBus_rsp_valid),
    .io_mem_rsp_payload_data(iBus_rsp_payload_data),
    .io_mem_rsp_payload_error(iBus_rsp_payload_error),
    .clk(clk),
    .reset(reset) 
  );
  DataCache dataCache_1_ ( 
    .io_cpu_execute_isValid(_zz_255_),
    .io_cpu_execute_isStuck(execute_arbitration_isStuck),
    .io_cpu_execute_args_kind(_zz_256_),
    .io_cpu_execute_args_wr(execute_MEMORY_WR),
    .io_cpu_execute_args_address(_zz_257_),
    .io_cpu_execute_args_data(_zz_140_),
    .io_cpu_execute_args_size(execute_DBusCachedPlugin_size),
    .io_cpu_execute_args_forceUncachedAccess(_zz_258_),
    .io_cpu_execute_args_clean(_zz_259_),
    .io_cpu_execute_args_invalidate(_zz_260_),
    .io_cpu_execute_args_way(_zz_261_),
    .io_cpu_memory_isValid(_zz_262_),
    .io_cpu_memory_isStuck(memory_arbitration_isStuck),
    .io_cpu_memory_isRemoved(memory_arbitration_removeIt),
    .io_cpu_memory_haltIt(_zz_296_),
    .io_cpu_memory_mmuBus_cmd_isValid(_zz_297_),
    .io_cpu_memory_mmuBus_cmd_virtualAddress(_zz_298_),
    .io_cpu_memory_mmuBus_cmd_bypassTranslation(_zz_299_),
    .io_cpu_memory_mmuBus_rsp_physicalAddress(_zz_109_),
    .io_cpu_memory_mmuBus_rsp_isIoAccess(_zz_263_),
    .io_cpu_memory_mmuBus_rsp_allowRead(_zz_264_),
    .io_cpu_memory_mmuBus_rsp_allowWrite(_zz_265_),
    .io_cpu_memory_mmuBus_rsp_allowExecute(_zz_266_),
    .io_cpu_memory_mmuBus_rsp_allowUser(_zz_267_),
    .io_cpu_memory_mmuBus_rsp_miss(_zz_268_),
    .io_cpu_memory_mmuBus_rsp_hit(_zz_269_),
    .io_cpu_memory_mmuBus_end(_zz_300_),
    .io_cpu_writeBack_isValid(_zz_270_),
    .io_cpu_writeBack_isStuck(writeBack_arbitration_isStuck),
    .io_cpu_writeBack_isUser(_zz_271_),
    .io_cpu_writeBack_haltIt(_zz_301_),
    .io_cpu_writeBack_data(_zz_302_),
    .io_cpu_writeBack_mmuMiss(_zz_303_),
    .io_cpu_writeBack_illegalAccess(_zz_304_),
    .io_cpu_writeBack_unalignedAccess(_zz_305_),
    .io_cpu_writeBack_accessError(_zz_306_),
    .io_cpu_writeBack_badAddr(_zz_307_),
    .io_mem_cmd_valid(_zz_308_),
    .io_mem_cmd_ready(dBus_cmd_ready),
    .io_mem_cmd_payload_wr(_zz_309_),
    .io_mem_cmd_payload_address(_zz_310_),
    .io_mem_cmd_payload_data(_zz_311_),
    .io_mem_cmd_payload_mask(_zz_312_),
    .io_mem_cmd_payload_length(_zz_313_),
    .io_mem_cmd_payload_last(_zz_314_),
    .io_mem_rsp_valid(dBus_rsp_valid),
    .io_mem_rsp_payload_data(dBus_rsp_payload_data),
    .io_mem_rsp_payload_error(dBus_rsp_payload_error),
    .clk(clk),
    .reset(reset) 
  );
  StreamFork streamFork_1_ ( 
    .io_input_valid(_zz_272_),
    .io_input_ready(_zz_315_),
    .io_input_payload_wr(dBus_cmd_payload_wr),
    .io_input_payload_address(dBus_cmd_payload_address),
    .io_input_payload_data(dBus_cmd_payload_data),
    .io_input_payload_mask(dBus_cmd_payload_mask),
    .io_input_payload_length(dBus_cmd_payload_length),
    .io_input_payload_last(dBus_cmd_payload_last),
    .io_outputs_0_valid(_zz_316_),
    .io_outputs_0_ready(_zz_273_),
    .io_outputs_0_payload_wr(_zz_317_),
    .io_outputs_0_payload_address(_zz_318_),
    .io_outputs_0_payload_data(_zz_319_),
    .io_outputs_0_payload_mask(_zz_320_),
    .io_outputs_0_payload_length(_zz_321_),
    .io_outputs_0_payload_last(_zz_322_),
    .io_outputs_1_valid(_zz_323_),
    .io_outputs_1_ready(_zz_274_),
    .io_outputs_1_payload_wr(_zz_324_),
    .io_outputs_1_payload_address(_zz_325_),
    .io_outputs_1_payload_data(_zz_326_),
    .io_outputs_1_payload_mask(_zz_327_),
    .io_outputs_1_payload_length(_zz_328_),
    .io_outputs_1_payload_last(_zz_329_),
    .clk(clk),
    .reset(reset) 
  );
  JtagBridge jtagBridge_1_ ( 
    .io_jtag_tms(jtag_tms),
    .io_jtag_tdi(jtag_tdi),
    .io_jtag_tdo(_zz_330_),
    .io_jtag_tck(jtag_tck),
    .io_remote_cmd_valid(_zz_331_),
    .io_remote_cmd_ready(_zz_335_),
    .io_remote_cmd_payload_last(_zz_332_),
    .io_remote_cmd_payload_fragment(_zz_333_),
    .io_remote_rsp_valid(_zz_336_),
    .io_remote_rsp_ready(_zz_334_),
    .io_remote_rsp_payload_error(_zz_337_),
    .io_remote_rsp_payload_data(_zz_338_),
    .clk(clk),
    .reset(reset) 
  );
  SystemDebugger systemDebugger_1_ ( 
    .io_remote_cmd_valid(_zz_331_),
    .io_remote_cmd_ready(_zz_335_),
    .io_remote_cmd_payload_last(_zz_332_),
    .io_remote_cmd_payload_fragment(_zz_333_),
    .io_remote_rsp_valid(_zz_336_),
    .io_remote_rsp_ready(_zz_334_),
    .io_remote_rsp_payload_error(_zz_337_),
    .io_remote_rsp_payload_data(_zz_338_),
    .io_mem_cmd_valid(_zz_339_),
    .io_mem_cmd_ready(debug_bus_cmd_ready),
    .io_mem_cmd_payload_address(_zz_340_),
    .io_mem_cmd_payload_data(_zz_341_),
    .io_mem_cmd_payload_wr(_zz_342_),
    .io_mem_cmd_payload_size(_zz_343_),
    .io_mem_rsp_valid(_zz_242_),
    .io_mem_rsp_payload(debug_bus_rsp_data),
    .clk(clk),
    .reset(reset) 
  );
  always @(*) begin
    case(_zz_449_)
      2'b00 : begin
        _zz_277_ = _zz_115_;
      end
      2'b01 : begin
        _zz_277_ = _zz_113_;
      end
      2'b10 : begin
        _zz_277_ = _zz_106_;
      end
      default : begin
        _zz_277_ = _zz_103_;
      end
    endcase
  end

  assign decode_SRC2_CTRL = _zz_1_;
  assign _zz_2_ = _zz_3_;
  assign execute_BRANCH_CALC = _zz_32_;
  assign execute_MUL_LL = _zz_43_;
  assign writeBack_FORMAL_PC_NEXT = memory_to_writeBack_FORMAL_PC_NEXT;
  assign memory_FORMAL_PC_NEXT = execute_to_memory_FORMAL_PC_NEXT;
  assign execute_FORMAL_PC_NEXT = decode_to_execute_FORMAL_PC_NEXT;
  assign decode_FORMAL_PC_NEXT = _zz_96_;
  assign execute_SHIFT_RIGHT = _zz_46_;
  assign _zz_4_ = _zz_5_;
  assign decode_SHIFT_CTRL = _zz_6_;
  assign _zz_7_ = _zz_8_;
  assign decode_SRC_USE_SUB_LESS = _zz_82_;
  assign decode_CSR_WRITE_OPCODE = _zz_30_;
  assign memory_IS_MUL = execute_to_memory_IS_MUL;
  assign execute_IS_MUL = decode_to_execute_IS_MUL;
  assign decode_IS_MUL = _zz_67_;
  assign execute_MUL_HL = _zz_41_;
  assign decode_IS_CSR = _zz_73_;
  assign execute_FLUSH_ALL = decode_to_execute_FLUSH_ALL;
  assign decode_FLUSH_ALL = _zz_85_;
  assign _zz_9_ = _zz_10_;
  assign decode_IS_RS1_SIGNED = _zz_68_;
  assign writeBack_REGFILE_WRITE_DATA = memory_to_writeBack_REGFILE_WRITE_DATA;
  assign memory_REGFILE_WRITE_DATA = execute_to_memory_REGFILE_WRITE_DATA;
  assign execute_REGFILE_WRITE_DATA = _zz_57_;
  assign execute_BYPASSABLE_MEMORY_STAGE = decode_to_execute_BYPASSABLE_MEMORY_STAGE;
  assign decode_BYPASSABLE_MEMORY_STAGE = _zz_66_;
  assign decode_SRC_LESS_UNSIGNED = _zz_80_;
  assign decode_MEMORY_MANAGMENT = _zz_77_;
  assign memory_MUL_LOW = _zz_39_;
  assign decode_IS_DIV = _zz_84_;
  assign memory_MEMORY_WR = execute_to_memory_MEMORY_WR;
  assign decode_MEMORY_WR = _zz_76_;
  assign execute_BRANCH_DO = _zz_33_;
  assign decode_DO_EBREAK = _zz_37_;
  assign decode_MEMORY_ENABLE = _zz_65_;
  assign decode_CSR_READ_OPCODE = _zz_29_;
  assign decode_BYPASSABLE_EXECUTE_STAGE = _zz_79_;
  assign decode_ALU_BITWISE_CTRL = _zz_11_;
  assign _zz_12_ = _zz_13_;
  assign execute_MUL_LH = _zz_42_;
  assign memory_MUL_HH = execute_to_memory_MUL_HH;
  assign execute_MUL_HH = _zz_40_;
  assign decode_ALU_CTRL = _zz_14_;
  assign _zz_15_ = _zz_16_;
  assign decode_IS_RS2_SIGNED = _zz_87_;
  assign memory_MEMORY_ADDRESS_LOW = execute_to_memory_MEMORY_ADDRESS_LOW;
  assign execute_MEMORY_ADDRESS_LOW = _zz_90_;
  assign decode_PREDICTION_HAD_BRANCHED2 = _zz_36_;
  assign memory_PC = execute_to_memory_PC;
  assign decode_SRC1_CTRL = _zz_17_;
  assign _zz_18_ = _zz_19_;
  assign _zz_20_ = _zz_21_;
  assign _zz_22_ = _zz_23_;
  assign decode_ENV_CTRL = _zz_24_;
  assign _zz_25_ = _zz_26_;
  assign execute_CSR_READ_OPCODE = decode_to_execute_CSR_READ_OPCODE;
  assign execute_CSR_WRITE_OPCODE = decode_to_execute_CSR_WRITE_OPCODE;
  assign execute_IS_CSR = decode_to_execute_IS_CSR;
  assign memory_ENV_CTRL = _zz_27_;
  assign execute_ENV_CTRL = _zz_28_;
  assign writeBack_ENV_CTRL = _zz_31_;
  assign memory_BRANCH_CALC = execute_to_memory_BRANCH_CALC;
  assign memory_BRANCH_DO = execute_to_memory_BRANCH_DO;
  assign execute_PREDICTION_HAD_BRANCHED2 = decode_to_execute_PREDICTION_HAD_BRANCHED2;
  assign execute_BRANCH_COND_RESULT = _zz_35_;
  assign execute_BRANCH_CTRL = _zz_34_;
  assign execute_PC = decode_to_execute_PC;
  assign execute_DO_EBREAK = decode_to_execute_DO_EBREAK;
  assign decode_IS_EBREAK = _zz_81_;
  assign decode_RS2_USE = _zz_69_;
  assign decode_RS1_USE = _zz_72_;
  always @ (*) begin
    _zz_38_ = execute_REGFILE_WRITE_DATA;
    execute_arbitration_haltItself = 1'b0;
    if((execute_arbitration_isValid && execute_IS_CSR))begin
      _zz_38_ = execute_CsrPlugin_readData;
      if(execute_CsrPlugin_blockedBySideEffects)begin
        execute_arbitration_haltItself = 1'b1;
      end
    end
  end

  assign execute_REGFILE_WRITE_VALID = decode_to_execute_REGFILE_WRITE_VALID;
  assign execute_BYPASSABLE_EXECUTE_STAGE = decode_to_execute_BYPASSABLE_EXECUTE_STAGE;
  assign memory_REGFILE_WRITE_VALID = execute_to_memory_REGFILE_WRITE_VALID;
  assign memory_BYPASSABLE_MEMORY_STAGE = execute_to_memory_BYPASSABLE_MEMORY_STAGE;
  assign writeBack_REGFILE_WRITE_VALID = memory_to_writeBack_REGFILE_WRITE_VALID;
  always @ (*) begin
    decode_RS2 = _zz_62_;
    decode_RS1 = _zz_63_;
    if(_zz_181_)begin
      if((_zz_182_ == decode_INSTRUCTION[19 : 15]))begin
        decode_RS1 = _zz_183_;
      end
      if((_zz_182_ == decode_INSTRUCTION[24 : 20]))begin
        decode_RS2 = _zz_183_;
      end
    end
    if((writeBack_arbitration_isValid && writeBack_REGFILE_WRITE_VALID))begin
      if(1'b1)begin
        if(_zz_184_)begin
          decode_RS1 = _zz_89_;
        end
        if(_zz_185_)begin
          decode_RS2 = _zz_89_;
        end
      end
    end
    if((memory_arbitration_isValid && memory_REGFILE_WRITE_VALID))begin
      if(memory_BYPASSABLE_MEMORY_STAGE)begin
        if(_zz_186_)begin
          decode_RS1 = _zz_44_;
        end
        if(_zz_187_)begin
          decode_RS2 = _zz_44_;
        end
      end
    end
    if((execute_arbitration_isValid && execute_REGFILE_WRITE_VALID))begin
      if(execute_BYPASSABLE_EXECUTE_STAGE)begin
        if(_zz_188_)begin
          decode_RS1 = _zz_38_;
        end
        if(_zz_189_)begin
          decode_RS2 = _zz_38_;
        end
      end
    end
  end

  assign execute_IS_RS1_SIGNED = decode_to_execute_IS_RS1_SIGNED;
  assign execute_RS1 = decode_to_execute_RS1;
  assign execute_IS_DIV = decode_to_execute_IS_DIV;
  assign execute_IS_RS2_SIGNED = decode_to_execute_IS_RS2_SIGNED;
  assign memory_INSTRUCTION = execute_to_memory_INSTRUCTION;
  assign memory_IS_DIV = execute_to_memory_IS_DIV;
  assign writeBack_IS_MUL = memory_to_writeBack_IS_MUL;
  assign writeBack_MUL_HH = memory_to_writeBack_MUL_HH;
  assign writeBack_MUL_LOW = memory_to_writeBack_MUL_LOW;
  assign memory_MUL_HL = execute_to_memory_MUL_HL;
  assign memory_MUL_LH = execute_to_memory_MUL_LH;
  assign memory_MUL_LL = execute_to_memory_MUL_LL;
  assign memory_SHIFT_RIGHT = execute_to_memory_SHIFT_RIGHT;
  always @ (*) begin
    _zz_44_ = memory_REGFILE_WRITE_DATA;
    memory_arbitration_haltItself = 1'b0;
    _zz_243_ = 1'b0;
    if((memory_arbitration_isValid && memory_FLUSH_ALL))begin
      _zz_243_ = 1'b1;
      if((! _zz_278_))begin
        memory_arbitration_haltItself = 1'b1;
      end
    end
    if(_zz_296_)begin
      memory_arbitration_haltItself = 1'b1;
    end
    if(((_zz_297_ && (! 1'b1)) && (! 1'b0)))begin
      memory_arbitration_haltItself = 1'b1;
    end
    case(memory_SHIFT_CTRL)
      `ShiftCtrlEnum_defaultEncoding_SLL_1 : begin
        _zz_44_ = _zz_170_;
      end
      `ShiftCtrlEnum_defaultEncoding_SRL_1, `ShiftCtrlEnum_defaultEncoding_SRA_1 : begin
        _zz_44_ = memory_SHIFT_RIGHT;
      end
      default : begin
      end
    endcase
    memory_DivPlugin_div_counter_willIncrement = 1'b0;
    if(_zz_344_)begin
      if(_zz_345_)begin
        memory_arbitration_haltItself = 1'b1;
        memory_DivPlugin_div_counter_willIncrement = 1'b1;
      end
      _zz_44_ = memory_DivPlugin_div_result;
    end
  end

  assign memory_SHIFT_CTRL = _zz_45_;
  assign execute_SHIFT_CTRL = _zz_47_;
  assign execute_SRC_LESS_UNSIGNED = decode_to_execute_SRC_LESS_UNSIGNED;
  assign execute_SRC_USE_SUB_LESS = decode_to_execute_SRC_USE_SUB_LESS;
  assign _zz_51_ = execute_PC;
  assign execute_SRC2_CTRL = _zz_52_;
  assign execute_SRC1_CTRL = _zz_54_;
  assign execute_SRC_ADD_SUB = _zz_50_;
  assign execute_SRC_LESS = _zz_48_;
  assign execute_ALU_CTRL = _zz_56_;
  assign execute_SRC2 = _zz_53_;
  assign execute_SRC1 = _zz_55_;
  assign execute_ALU_BITWISE_CTRL = _zz_58_;
  assign _zz_59_ = writeBack_INSTRUCTION;
  assign _zz_60_ = writeBack_REGFILE_WRITE_VALID;
  always @ (*) begin
    _zz_61_ = 1'b0;
    if(writeBack_RegFilePlugin_regFileWrite_valid)begin
      _zz_61_ = 1'b1;
    end
  end

  assign decode_INSTRUCTION_ANTICIPATED = _zz_92_;
  always @ (*) begin
    decode_REGFILE_WRITE_VALID = _zz_83_;
    if((decode_INSTRUCTION[11 : 7] == (5'b00000)))begin
      decode_REGFILE_WRITE_VALID = 1'b0;
    end
  end

  assign decode_LEGAL_INSTRUCTION = _zz_88_;
  assign decode_INSTRUCTION_READY = 1'b1;
  always @ (*) begin
    _zz_89_ = writeBack_REGFILE_WRITE_DATA;
    if((writeBack_arbitration_isValid && writeBack_MEMORY_ENABLE))begin
      _zz_89_ = writeBack_DBusCachedPlugin_rspFormated;
    end
    if((writeBack_arbitration_isValid && writeBack_IS_MUL))begin
      case(_zz_356_)
        2'b00 : begin
          _zz_89_ = _zz_412_;
        end
        default : begin
          _zz_89_ = _zz_413_;
        end
      endcase
    end
  end

  assign writeBack_MEMORY_ADDRESS_LOW = memory_to_writeBack_MEMORY_ADDRESS_LOW;
  assign writeBack_MEMORY_WR = memory_to_writeBack_MEMORY_WR;
  assign writeBack_MEMORY_ENABLE = memory_to_writeBack_MEMORY_ENABLE;
  assign memory_MEMORY_ENABLE = execute_to_memory_MEMORY_ENABLE;
  assign execute_MEMORY_MANAGMENT = decode_to_execute_MEMORY_MANAGMENT;
  assign execute_RS2 = decode_to_execute_RS2;
  assign execute_SRC_ADD = _zz_49_;
  assign execute_MEMORY_WR = decode_to_execute_MEMORY_WR;
  assign execute_MEMORY_ENABLE = decode_to_execute_MEMORY_ENABLE;
  assign execute_INSTRUCTION = decode_to_execute_INSTRUCTION;
  assign memory_FLUSH_ALL = execute_to_memory_FLUSH_ALL;
  always @ (*) begin
    IBusCachedPlugin_issueDetected = _zz_91_;
    _zz_107_ = 1'b0;
    if(((IBusCachedPlugin_stages_2_input_valid && ((_zz_287_ || _zz_288_) || _zz_289_)) && (! _zz_91_)))begin
      IBusCachedPlugin_issueDetected = 1'b1;
      _zz_107_ = IBusCachedPlugin_iBusRsp_readyForError;
    end
  end

  always @ (*) begin
    _zz_91_ = 1'b0;
    IBusCachedPlugin_redoFetch = 1'b0;
    if(((IBusCachedPlugin_stages_2_input_valid && _zz_291_) && (! 1'b0)))begin
      _zz_91_ = 1'b1;
      IBusCachedPlugin_redoFetch = IBusCachedPlugin_iBusRsp_readyForError;
    end
  end

  assign decode_BRANCH_CTRL = _zz_93_;
  always @ (*) begin
    _zz_94_ = memory_FORMAL_PC_NEXT;
    if(_zz_112_)begin
      _zz_94_ = _zz_113_;
    end
  end

  always @ (*) begin
    _zz_95_ = decode_FORMAL_PC_NEXT;
    if(_zz_102_)begin
      _zz_95_ = _zz_103_;
    end
    if(_zz_105_)begin
      _zz_95_ = _zz_106_;
    end
  end

  assign writeBack_PC = memory_to_writeBack_PC;
  assign writeBack_INSTRUCTION = memory_to_writeBack_INSTRUCTION;
  assign decode_PC = _zz_98_;
  always @ (*) begin
    decode_INSTRUCTION = _zz_97_;
    if((_zz_212_ != (3'b000)))begin
      decode_INSTRUCTION = _zz_213_;
    end
  end

  always @ (*) begin
    decode_arbitration_haltItself = 1'b0;
    decode_arbitration_isValid = (IBusCachedPlugin_iBusRsp_decodeInput_valid && (! IBusCachedPlugin_injector_decodeRemoved));
    _zz_111_ = 1'b0;
    case(_zz_212_)
      3'b000 : begin
      end
      3'b001 : begin
      end
      3'b010 : begin
        decode_arbitration_isValid = 1'b1;
        decode_arbitration_haltItself = 1'b1;
      end
      3'b011 : begin
        decode_arbitration_isValid = 1'b1;
      end
      3'b100 : begin
        _zz_111_ = 1'b1;
      end
      default : begin
      end
    endcase
  end

  always @ (*) begin
    decode_arbitration_haltByOther = 1'b0;
    if((decode_arbitration_isValid && (_zz_178_ || _zz_179_)))begin
      decode_arbitration_haltByOther = 1'b1;
    end
    if((CsrPlugin_interrupt && decode_arbitration_isValid))begin
      decode_arbitration_haltByOther = 1'b1;
    end
    if(({(memory_arbitration_isValid && (memory_ENV_CTRL == `EnvCtrlEnum_defaultEncoding_XRET)),(execute_arbitration_isValid && (execute_ENV_CTRL == `EnvCtrlEnum_defaultEncoding_XRET))} != (2'b00)))begin
      decode_arbitration_haltByOther = 1'b1;
    end
  end

  always @ (*) begin
    decode_arbitration_removeIt = 1'b0;
    if(decode_exception_agregat_valid)begin
      decode_arbitration_removeIt = 1'b1;
    end
    if(decode_arbitration_isFlushed)begin
      decode_arbitration_removeIt = 1'b1;
    end
  end

  assign decode_arbitration_flushAll = 1'b0;
  assign decode_arbitration_redoIt = 1'b0;
  always @ (*) begin
    execute_arbitration_haltByOther = 1'b0;
    _zz_99_ = 1'b0;
    _zz_100_ = 1'b0;
    if(_zz_346_)begin
      execute_arbitration_haltByOther = 1'b1;
      if(_zz_347_)begin
        _zz_100_ = 1'b1;
        _zz_99_ = 1'b1;
      end
    end
    if(DebugPlugin_haltIt)begin
      _zz_99_ = 1'b1;
    end
    if(_zz_348_)begin
      _zz_99_ = 1'b1;
    end
    if((((CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_decode || CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute) || CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory) || CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack))begin
      _zz_99_ = 1'b1;
    end
  end

  always @ (*) begin
    execute_arbitration_removeIt = 1'b0;
    if(execute_arbitration_isFlushed)begin
      execute_arbitration_removeIt = 1'b1;
    end
  end

  always @ (*) begin
    execute_arbitration_flushAll = 1'b0;
    if(_zz_346_)begin
      if(_zz_347_)begin
        execute_arbitration_flushAll = 1'b1;
      end
    end
    if(_zz_112_)begin
      execute_arbitration_flushAll = 1'b1;
    end
    if(memory_exception_agregat_valid)begin
      execute_arbitration_flushAll = 1'b1;
    end
  end

  assign execute_arbitration_redoIt = 1'b0;
  assign memory_arbitration_haltByOther = 1'b0;
  always @ (*) begin
    memory_arbitration_removeIt = 1'b0;
    if(memory_exception_agregat_valid)begin
      memory_arbitration_removeIt = 1'b1;
    end
    if(memory_arbitration_isFlushed)begin
      memory_arbitration_removeIt = 1'b1;
    end
  end

  always @ (*) begin
    memory_arbitration_flushAll = 1'b0;
    writeBack_arbitration_removeIt = 1'b0;
    _zz_114_ = 1'b0;
    _zz_115_ = (32'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx);
    CsrPlugin_exceptionPortCtrl_exceptionValids_writeBack = CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack;
    if(writeBack_exception_agregat_valid)begin
      memory_arbitration_flushAll = 1'b1;
      writeBack_arbitration_removeIt = 1'b1;
      CsrPlugin_exceptionPortCtrl_exceptionValids_writeBack = 1'b1;
    end
    if(_zz_349_)begin
      _zz_114_ = 1'b1;
      _zz_115_ = {CsrPlugin_mtvec_base,(2'b00)};
      memory_arbitration_flushAll = 1'b1;
    end
    if(_zz_350_)begin
      _zz_115_ = CsrPlugin_mepc;
      _zz_114_ = 1'b1;
      memory_arbitration_flushAll = 1'b1;
    end
    if(writeBack_arbitration_isFlushed)begin
      writeBack_arbitration_removeIt = 1'b1;
    end
  end

  assign memory_arbitration_redoIt = 1'b0;
  always @ (*) begin
    writeBack_arbitration_haltItself = 1'b0;
    if(_zz_301_)begin
      writeBack_arbitration_haltItself = 1'b1;
    end
  end

  assign writeBack_arbitration_haltByOther = 1'b0;
  assign writeBack_arbitration_flushAll = 1'b0;
  assign writeBack_arbitration_redoIt = 1'b0;
  always @ (*) begin
    _zz_101_ = 1'b0;
    if((IBusCachedPlugin_iBusRsp_stages_1_input_valid || IBusCachedPlugin_stages_2_input_valid))begin
      _zz_101_ = 1'b1;
    end
  end

  always @ (*) begin
    _zz_116_ = 1'b1;
    if((DebugPlugin_haltIt || DebugPlugin_stepIt))begin
      _zz_116_ = 1'b0;
    end
  end

  always @ (*) begin
    _zz_117_ = 1'b1;
    if(DebugPlugin_haltIt)begin
      _zz_117_ = 1'b0;
    end
  end

  assign IBusCachedPlugin_jump_pcLoad_valid = (((_zz_102_ || _zz_105_) || _zz_112_) || _zz_114_);
  assign _zz_118_ = {_zz_102_,{_zz_105_,{_zz_112_,_zz_114_}}};
  assign _zz_119_ = (_zz_118_ & (~ _zz_359_));
  assign _zz_120_ = _zz_119_[3];
  assign _zz_121_ = (_zz_119_[1] || _zz_120_);
  assign _zz_122_ = (_zz_119_[2] || _zz_120_);
  assign IBusCachedPlugin_jump_pcLoad_payload = _zz_277_;
  assign _zz_123_ = (! _zz_99_);
  assign IBusCachedPlugin_fetchPc_output_valid = (IBusCachedPlugin_fetchPc_preOutput_valid && _zz_123_);
  assign IBusCachedPlugin_fetchPc_preOutput_ready = (IBusCachedPlugin_fetchPc_output_ready && _zz_123_);
  assign IBusCachedPlugin_fetchPc_output_payload = IBusCachedPlugin_fetchPc_preOutput_payload;
  always @ (*) begin
    IBusCachedPlugin_fetchPc_propagatePc = 1'b0;
    if((IBusCachedPlugin_iBusRsp_stages_1_input_valid && IBusCachedPlugin_iBusRsp_stages_1_input_ready))begin
      IBusCachedPlugin_fetchPc_propagatePc = 1'b1;
    end
  end

  always @ (*) begin
    IBusCachedPlugin_fetchPc_pc = (IBusCachedPlugin_fetchPc_pcReg + _zz_361_);
    IBusCachedPlugin_fetchPc_samplePcNext = 1'b0;
    if(IBusCachedPlugin_fetchPc_propagatePc)begin
      IBusCachedPlugin_fetchPc_samplePcNext = 1'b1;
    end
    if(IBusCachedPlugin_jump_pcLoad_valid)begin
      IBusCachedPlugin_fetchPc_samplePcNext = 1'b1;
      IBusCachedPlugin_fetchPc_pc = IBusCachedPlugin_jump_pcLoad_payload;
    end
    if(_zz_351_)begin
      IBusCachedPlugin_fetchPc_samplePcNext = 1'b1;
    end
    IBusCachedPlugin_fetchPc_pc[0] = 1'b0;
    IBusCachedPlugin_fetchPc_pc[1] = 1'b0;
  end

  assign IBusCachedPlugin_fetchPc_preOutput_valid = _zz_124_;
  assign IBusCachedPlugin_fetchPc_preOutput_payload = IBusCachedPlugin_fetchPc_pc;
  assign IBusCachedPlugin_iBusRsp_stages_0_input_valid = IBusCachedPlugin_fetchPc_output_valid;
  assign IBusCachedPlugin_fetchPc_output_ready = IBusCachedPlugin_iBusRsp_stages_0_input_ready;
  assign IBusCachedPlugin_iBusRsp_stages_0_input_payload = IBusCachedPlugin_fetchPc_output_payload;
  assign IBusCachedPlugin_iBusRsp_stages_0_inputSample = 1'b1;
  always @ (*) begin
    IBusCachedPlugin_iBusRsp_stages_0_halt = 1'b0;
    if(_zz_280_)begin
      IBusCachedPlugin_iBusRsp_stages_0_halt = 1'b1;
    end
  end

  assign _zz_125_ = (! IBusCachedPlugin_iBusRsp_stages_0_halt);
  assign IBusCachedPlugin_iBusRsp_stages_0_input_ready = (IBusCachedPlugin_iBusRsp_stages_0_output_ready && _zz_125_);
  assign IBusCachedPlugin_iBusRsp_stages_0_output_valid = (IBusCachedPlugin_iBusRsp_stages_0_input_valid && _zz_125_);
  assign IBusCachedPlugin_iBusRsp_stages_0_output_payload = IBusCachedPlugin_iBusRsp_stages_0_input_payload;
  always @ (*) begin
    IBusCachedPlugin_iBusRsp_stages_1_halt = 1'b0;
    if(((_zz_283_ && (! 1'b1)) && (! 1'b0)))begin
      IBusCachedPlugin_iBusRsp_stages_1_halt = 1'b1;
    end
  end

  assign _zz_126_ = (! IBusCachedPlugin_iBusRsp_stages_1_halt);
  assign IBusCachedPlugin_iBusRsp_stages_1_input_ready = (IBusCachedPlugin_iBusRsp_stages_1_output_ready && _zz_126_);
  assign IBusCachedPlugin_iBusRsp_stages_1_output_valid = (IBusCachedPlugin_iBusRsp_stages_1_input_valid && _zz_126_);
  assign IBusCachedPlugin_iBusRsp_stages_1_output_payload = IBusCachedPlugin_iBusRsp_stages_1_input_payload;
  always @ (*) begin
    IBusCachedPlugin_stages_2_halt = 1'b0;
    if((IBusCachedPlugin_issueDetected || IBusCachedPlugin_iBusRspOutputHalt))begin
      IBusCachedPlugin_stages_2_halt = 1'b1;
    end
  end

  assign _zz_127_ = (! IBusCachedPlugin_stages_2_halt);
  assign IBusCachedPlugin_stages_2_input_ready = (IBusCachedPlugin_stages_2_output_ready && _zz_127_);
  assign IBusCachedPlugin_stages_2_output_valid = (IBusCachedPlugin_stages_2_input_valid && _zz_127_);
  assign IBusCachedPlugin_stages_2_output_payload = IBusCachedPlugin_stages_2_input_payload;
  assign IBusCachedPlugin_iBusRsp_stages_0_output_ready = _zz_128_;
  assign _zz_128_ = ((1'b0 && (! _zz_129_)) || IBusCachedPlugin_iBusRsp_stages_1_input_ready);
  assign _zz_129_ = _zz_130_;
  assign IBusCachedPlugin_iBusRsp_stages_1_input_valid = _zz_129_;
  assign IBusCachedPlugin_iBusRsp_stages_1_input_payload = IBusCachedPlugin_fetchPc_pcReg;
  assign IBusCachedPlugin_iBusRsp_stages_1_output_ready = ((1'b0 && (! _zz_131_)) || IBusCachedPlugin_stages_2_input_ready);
  assign _zz_131_ = _zz_132_;
  assign IBusCachedPlugin_stages_2_input_valid = _zz_131_;
  assign IBusCachedPlugin_stages_2_input_payload = _zz_133_;
  assign IBusCachedPlugin_iBusRsp_readyForError = 1'b1;
  assign IBusCachedPlugin_iBusRsp_decodeInput_ready = (! decode_arbitration_isStuck);
  assign _zz_98_ = IBusCachedPlugin_iBusRsp_decodeInput_payload_pc;
  assign _zz_97_ = IBusCachedPlugin_iBusRsp_decodeInput_payload_rsp_rawInDecode;
  assign _zz_96_ = (decode_PC + (32'b00000000000000000000000000000100));
  assign _zz_134_ = _zz_362_[11];
  always @ (*) begin
    _zz_135_[18] = _zz_134_;
    _zz_135_[17] = _zz_134_;
    _zz_135_[16] = _zz_134_;
    _zz_135_[15] = _zz_134_;
    _zz_135_[14] = _zz_134_;
    _zz_135_[13] = _zz_134_;
    _zz_135_[12] = _zz_134_;
    _zz_135_[11] = _zz_134_;
    _zz_135_[10] = _zz_134_;
    _zz_135_[9] = _zz_134_;
    _zz_135_[8] = _zz_134_;
    _zz_135_[7] = _zz_134_;
    _zz_135_[6] = _zz_134_;
    _zz_135_[5] = _zz_134_;
    _zz_135_[4] = _zz_134_;
    _zz_135_[3] = _zz_134_;
    _zz_135_[2] = _zz_134_;
    _zz_135_[1] = _zz_134_;
    _zz_135_[0] = _zz_134_;
  end

  assign _zz_104_ = ((decode_BRANCH_CTRL == `BranchCtrlEnum_defaultEncoding_JAL) || ((decode_BRANCH_CTRL == `BranchCtrlEnum_defaultEncoding_B) && _zz_363_[31]));
  assign _zz_102_ = (_zz_104_ && decode_arbitration_isFiring);
  assign _zz_136_ = _zz_364_[19];
  always @ (*) begin
    _zz_137_[10] = _zz_136_;
    _zz_137_[9] = _zz_136_;
    _zz_137_[8] = _zz_136_;
    _zz_137_[7] = _zz_136_;
    _zz_137_[6] = _zz_136_;
    _zz_137_[5] = _zz_136_;
    _zz_137_[4] = _zz_136_;
    _zz_137_[3] = _zz_136_;
    _zz_137_[2] = _zz_136_;
    _zz_137_[1] = _zz_136_;
    _zz_137_[0] = _zz_136_;
  end

  assign _zz_138_ = _zz_365_[11];
  always @ (*) begin
    _zz_139_[18] = _zz_138_;
    _zz_139_[17] = _zz_138_;
    _zz_139_[16] = _zz_138_;
    _zz_139_[15] = _zz_138_;
    _zz_139_[14] = _zz_138_;
    _zz_139_[13] = _zz_138_;
    _zz_139_[12] = _zz_138_;
    _zz_139_[11] = _zz_138_;
    _zz_139_[10] = _zz_138_;
    _zz_139_[9] = _zz_138_;
    _zz_139_[8] = _zz_138_;
    _zz_139_[7] = _zz_138_;
    _zz_139_[6] = _zz_138_;
    _zz_139_[5] = _zz_138_;
    _zz_139_[4] = _zz_138_;
    _zz_139_[3] = _zz_138_;
    _zz_139_[2] = _zz_138_;
    _zz_139_[1] = _zz_138_;
    _zz_139_[0] = _zz_138_;
  end

  assign _zz_103_ = (decode_PC + ((decode_BRANCH_CTRL == `BranchCtrlEnum_defaultEncoding_JAL) ? {{_zz_137_,{{{_zz_450_,_zz_451_},_zz_452_},decode_INSTRUCTION[30 : 21]}},1'b0} : {{_zz_139_,{{{_zz_453_,_zz_454_},decode_INSTRUCTION[30 : 25]},decode_INSTRUCTION[11 : 8]}},1'b0}));
  assign iBus_cmd_valid = _zz_293_;
  always @ (*) begin
    iBus_cmd_payload_address = _zz_294_;
    iBus_cmd_payload_address = _zz_294_;
  end

  assign iBus_cmd_payload_size = _zz_295_;
  assign _zz_245_ = (IBusCachedPlugin_jump_pcLoad_valid || _zz_100_);
  assign IBusCachedPlugin_iBusRspOutputHalt = 1'b0;
  assign _zz_246_ = (_zz_108_[31 : 28] == (4'b1111));
  assign _zz_247_ = 1'b1;
  assign _zz_248_ = 1'b1;
  assign _zz_249_ = 1'b1;
  assign _zz_250_ = 1'b1;
  assign _zz_251_ = 1'b0;
  assign _zz_252_ = 1'b1;
  assign _zz_244_ = (! IBusCachedPlugin_iBusRsp_stages_1_input_ready);
  assign _zz_253_ = (! IBusCachedPlugin_stages_2_input_ready);
  assign _zz_254_ = (CsrPlugin_privilege == (2'b00));
  assign _zz_92_ = (decode_arbitration_isStuck ? decode_INSTRUCTION : _zz_281_);
  assign _zz_105_ = IBusCachedPlugin_redoFetch;
  assign _zz_106_ = IBusCachedPlugin_stages_2_input_payload;
  assign IBusCachedPlugin_iBusRsp_decodeInput_valid = IBusCachedPlugin_stages_2_output_valid;
  assign IBusCachedPlugin_stages_2_output_ready = IBusCachedPlugin_iBusRsp_decodeInput_ready;
  assign IBusCachedPlugin_iBusRsp_decodeInput_payload_rsp_rawInDecode = _zz_290_;
  assign IBusCachedPlugin_iBusRsp_decodeInput_payload_pc = IBusCachedPlugin_stages_2_output_payload;
  assign dBus_cmd_valid = _zz_308_;
  assign dBus_cmd_payload_wr = _zz_309_;
  assign dBus_cmd_payload_address = _zz_310_;
  assign dBus_cmd_payload_data = _zz_311_;
  assign dBus_cmd_payload_mask = _zz_312_;
  assign dBus_cmd_payload_length = _zz_313_;
  assign dBus_cmd_payload_last = _zz_314_;
  assign execute_DBusCachedPlugin_size = execute_INSTRUCTION[13 : 12];
  assign _zz_255_ = (execute_arbitration_isValid && execute_MEMORY_ENABLE);
  assign _zz_257_ = execute_SRC_ADD;
  always @ (*) begin
    case(execute_DBusCachedPlugin_size)
      2'b00 : begin
        _zz_140_ = {{{execute_RS2[7 : 0],execute_RS2[7 : 0]},execute_RS2[7 : 0]},execute_RS2[7 : 0]};
      end
      2'b01 : begin
        _zz_140_ = {execute_RS2[15 : 0],execute_RS2[15 : 0]};
      end
      default : begin
        _zz_140_ = execute_RS2[31 : 0];
      end
    endcase
  end

  assign _zz_258_ = 1'b0;
  assign _zz_256_ = (execute_MEMORY_MANAGMENT ? `DataCacheCpuCmdKind_defaultEncoding_MANAGMENT : `DataCacheCpuCmdKind_defaultEncoding_MEMORY);
  assign _zz_259_ = execute_INSTRUCTION[28];
  assign _zz_260_ = execute_INSTRUCTION[29];
  assign _zz_261_ = execute_INSTRUCTION[30];
  assign _zz_90_ = _zz_257_[1 : 0];
  assign _zz_262_ = (memory_arbitration_isValid && memory_MEMORY_ENABLE);
  assign _zz_263_ = (_zz_109_[31 : 27] != (5'b10010));   // bard0: data cached ONLY in 0x90000000-0x97FFFFFF (matches mbv D-cache range); DMA memory at 0x9F000000 stays uncached so BD writes reach DDR
  assign _zz_264_ = 1'b1;
  assign _zz_265_ = 1'b1;
  assign _zz_266_ = 1'b1;
  assign _zz_267_ = 1'b1;
  assign _zz_268_ = 1'b0;
  assign _zz_269_ = 1'b1;
  assign _zz_270_ = (writeBack_arbitration_isValid && writeBack_MEMORY_ENABLE);
  assign _zz_271_ = (CsrPlugin_privilege == (2'b00));
  assign writeBack_exception_agregat_valid = (((_zz_303_ || _zz_306_) || _zz_304_) || _zz_305_);
  assign writeBack_exception_agregat_payload_badAddr = _zz_307_;
  always @ (*) begin
    writeBack_exception_agregat_payload_code = (4'bxxxx);
    if((_zz_304_ || _zz_306_))begin
      writeBack_exception_agregat_payload_code = {1'd0, _zz_366_};
    end
    if(_zz_305_)begin
      writeBack_exception_agregat_payload_code = {1'd0, _zz_367_};
    end
    if(_zz_303_)begin
      writeBack_exception_agregat_payload_code = (4'b1101);
    end
  end

  always @ (*) begin
    writeBack_DBusCachedPlugin_rspShifted = _zz_302_;
    case(writeBack_MEMORY_ADDRESS_LOW)
      2'b01 : begin
        writeBack_DBusCachedPlugin_rspShifted[7 : 0] = _zz_302_[15 : 8];
      end
      2'b10 : begin
        writeBack_DBusCachedPlugin_rspShifted[15 : 0] = _zz_302_[31 : 16];
      end
      2'b11 : begin
        writeBack_DBusCachedPlugin_rspShifted[7 : 0] = _zz_302_[31 : 24];
      end
      default : begin
      end
    endcase
  end

  assign _zz_141_ = (writeBack_DBusCachedPlugin_rspShifted[7] && (! writeBack_INSTRUCTION[14]));
  always @ (*) begin
    _zz_142_[31] = _zz_141_;
    _zz_142_[30] = _zz_141_;
    _zz_142_[29] = _zz_141_;
    _zz_142_[28] = _zz_141_;
    _zz_142_[27] = _zz_141_;
    _zz_142_[26] = _zz_141_;
    _zz_142_[25] = _zz_141_;
    _zz_142_[24] = _zz_141_;
    _zz_142_[23] = _zz_141_;
    _zz_142_[22] = _zz_141_;
    _zz_142_[21] = _zz_141_;
    _zz_142_[20] = _zz_141_;
    _zz_142_[19] = _zz_141_;
    _zz_142_[18] = _zz_141_;
    _zz_142_[17] = _zz_141_;
    _zz_142_[16] = _zz_141_;
    _zz_142_[15] = _zz_141_;
    _zz_142_[14] = _zz_141_;
    _zz_142_[13] = _zz_141_;
    _zz_142_[12] = _zz_141_;
    _zz_142_[11] = _zz_141_;
    _zz_142_[10] = _zz_141_;
    _zz_142_[9] = _zz_141_;
    _zz_142_[8] = _zz_141_;
    _zz_142_[7 : 0] = writeBack_DBusCachedPlugin_rspShifted[7 : 0];
  end

  assign _zz_143_ = (writeBack_DBusCachedPlugin_rspShifted[15] && (! writeBack_INSTRUCTION[14]));
  always @ (*) begin
    _zz_144_[31] = _zz_143_;
    _zz_144_[30] = _zz_143_;
    _zz_144_[29] = _zz_143_;
    _zz_144_[28] = _zz_143_;
    _zz_144_[27] = _zz_143_;
    _zz_144_[26] = _zz_143_;
    _zz_144_[25] = _zz_143_;
    _zz_144_[24] = _zz_143_;
    _zz_144_[23] = _zz_143_;
    _zz_144_[22] = _zz_143_;
    _zz_144_[21] = _zz_143_;
    _zz_144_[20] = _zz_143_;
    _zz_144_[19] = _zz_143_;
    _zz_144_[18] = _zz_143_;
    _zz_144_[17] = _zz_143_;
    _zz_144_[16] = _zz_143_;
    _zz_144_[15 : 0] = writeBack_DBusCachedPlugin_rspShifted[15 : 0];
  end

  always @ (*) begin
    case(_zz_354_)
      2'b00 : begin
        writeBack_DBusCachedPlugin_rspFormated = _zz_142_;
      end
      2'b01 : begin
        writeBack_DBusCachedPlugin_rspFormated = _zz_144_;
      end
      default : begin
        writeBack_DBusCachedPlugin_rspFormated = writeBack_DBusCachedPlugin_rspShifted;
      end
    endcase
  end

  assign _zz_108_ = _zz_284_;
  assign _zz_109_ = _zz_298_;
  assign _zz_146_ = ((decode_INSTRUCTION & (32'b00000000000000000001000000000000)) == (32'b00000000000000000000000000000000));
  assign _zz_147_ = ((decode_INSTRUCTION & (32'b00000000000000000100000000010100)) == (32'b00000000000000000000000000000100));
  assign _zz_148_ = ((decode_INSTRUCTION & (32'b00000000000000000000000001001000)) == (32'b00000000000000000000000001001000));
  assign _zz_149_ = ((decode_INSTRUCTION & (32'b00000000000000000000000000101000)) == (32'b00000000000000000000000000000000));
  assign _zz_150_ = ((decode_INSTRUCTION & (32'b00000000000000000100000000000100)) == (32'b00000000000000000000000000000100));
  assign _zz_151_ = ((decode_INSTRUCTION & (32'b00000000000000000000000000000100)) == (32'b00000000000000000000000000000100));
  assign _zz_152_ = ((decode_INSTRUCTION & (32'b00000000000000000001000001010000)) == (32'b00000000000000000001000000000000));
  assign _zz_153_ = ((decode_INSTRUCTION & (32'b00000000000000000100000001010000)) == (32'b00000000000000000100000001010000));
  assign _zz_145_ = {(((decode_INSTRUCTION & _zz_455_) == (32'b00000000000000000000000001010000)) != (1'b0)),{({_zz_152_,_zz_456_} != (2'b00)),{({_zz_457_,_zz_458_} != (5'b00000)),{(_zz_459_ != _zz_460_),{_zz_461_,{_zz_462_,_zz_463_}}}}}};
  assign _zz_88_ = ({((decode_INSTRUCTION & (32'b00000000000000000000000001011111)) == (32'b00000000000000000000000000010111)),{((decode_INSTRUCTION & (32'b00000000000000000000000001111111)) == (32'b00000000000000000000000001101111)),{((decode_INSTRUCTION & (32'b00000000000000000001000001101111)) == (32'b00000000000000000000000000000011)),{((decode_INSTRUCTION & _zz_613_) == (32'b00000000000000000001000001110011)),{(_zz_614_ == _zz_615_),{_zz_616_,{_zz_617_,_zz_618_}}}}}}} != (20'b00000000000000000000));
  assign _zz_87_ = _zz_368_[0];
  assign _zz_154_ = _zz_145_[3 : 2];
  assign _zz_86_ = _zz_154_;
  assign _zz_85_ = _zz_369_[0];
  assign _zz_84_ = _zz_370_[0];
  assign _zz_83_ = _zz_371_[0];
  assign _zz_82_ = _zz_372_[0];
  assign _zz_81_ = _zz_373_[0];
  assign _zz_80_ = _zz_374_[0];
  assign _zz_79_ = _zz_375_[0];
  assign _zz_155_ = _zz_145_[12 : 11];
  assign _zz_78_ = _zz_155_;
  assign _zz_77_ = _zz_376_[0];
  assign _zz_76_ = _zz_377_[0];
  assign _zz_156_ = _zz_145_[16 : 15];
  assign _zz_75_ = _zz_156_;
  assign _zz_157_ = _zz_145_[18 : 17];
  assign _zz_74_ = _zz_157_;
  assign _zz_73_ = _zz_378_[0];
  assign _zz_72_ = _zz_379_[0];
  assign _zz_158_ = _zz_145_[22 : 21];
  assign _zz_71_ = _zz_158_;
  assign _zz_159_ = _zz_145_[24 : 23];
  assign _zz_70_ = _zz_159_;
  assign _zz_69_ = _zz_380_[0];
  assign _zz_68_ = _zz_381_[0];
  assign _zz_67_ = _zz_382_[0];
  assign _zz_66_ = _zz_383_[0];
  assign _zz_65_ = _zz_384_[0];
  assign _zz_160_ = _zz_145_[30 : 30];
  assign _zz_64_ = _zz_160_;
  assign decodeExceptionPort_valid = ((decode_arbitration_isValid && decode_INSTRUCTION_READY) && (! decode_LEGAL_INSTRUCTION));
  assign decodeExceptionPort_1_code = (4'b0010);
  assign decodeExceptionPort_1_badAddr = (32'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx);
  assign decode_RegFilePlugin_regFileReadAddress1 = decode_INSTRUCTION_ANTICIPATED[19 : 15];
  assign decode_RegFilePlugin_regFileReadAddress2 = decode_INSTRUCTION_ANTICIPATED[24 : 20];
  assign decode_RegFilePlugin_rs1Data = _zz_275_;
  assign decode_RegFilePlugin_rs2Data = _zz_276_;
  assign _zz_63_ = decode_RegFilePlugin_rs1Data;
  assign _zz_62_ = decode_RegFilePlugin_rs2Data;
  always @ (*) begin
    writeBack_RegFilePlugin_regFileWrite_valid = (_zz_60_ && writeBack_arbitration_isFiring);
    if(_zz_161_)begin
      writeBack_RegFilePlugin_regFileWrite_valid = 1'b1;
    end
  end

  assign writeBack_RegFilePlugin_regFileWrite_payload_address = _zz_59_[11 : 7];
  assign writeBack_RegFilePlugin_regFileWrite_payload_data = _zz_89_;
  always @ (*) begin
    case(execute_ALU_BITWISE_CTRL)
      `AluBitwiseCtrlEnum_defaultEncoding_AND_1 : begin
        execute_IntAluPlugin_bitwise = (execute_SRC1 & execute_SRC2);
      end
      `AluBitwiseCtrlEnum_defaultEncoding_OR_1 : begin
        execute_IntAluPlugin_bitwise = (execute_SRC1 | execute_SRC2);
      end
      `AluBitwiseCtrlEnum_defaultEncoding_XOR_1 : begin
        execute_IntAluPlugin_bitwise = (execute_SRC1 ^ execute_SRC2);
      end
      default : begin
        execute_IntAluPlugin_bitwise = execute_SRC1;
      end
    endcase
  end

  always @ (*) begin
    case(execute_ALU_CTRL)
      `AluCtrlEnum_defaultEncoding_BITWISE : begin
        _zz_162_ = execute_IntAluPlugin_bitwise;
      end
      `AluCtrlEnum_defaultEncoding_SLT_SLTU : begin
        _zz_162_ = {31'd0, _zz_385_};
      end
      default : begin
        _zz_162_ = execute_SRC_ADD_SUB;
      end
    endcase
  end

  assign _zz_57_ = _zz_162_;
  always @ (*) begin
    case(execute_SRC1_CTRL)
      `Src1CtrlEnum_defaultEncoding_RS : begin
        _zz_163_ = execute_RS1;
      end
      `Src1CtrlEnum_defaultEncoding_PC_INCREMENT : begin
        _zz_163_ = {29'd0, _zz_386_};
      end
      `Src1CtrlEnum_defaultEncoding_IMU : begin
        _zz_163_ = {execute_INSTRUCTION[31 : 12],(12'b000000000000)};
      end
      default : begin
        _zz_163_ = {27'd0, _zz_387_};
      end
    endcase
  end

  assign _zz_55_ = _zz_163_;
  assign _zz_164_ = _zz_388_[11];
  always @ (*) begin
    _zz_165_[19] = _zz_164_;
    _zz_165_[18] = _zz_164_;
    _zz_165_[17] = _zz_164_;
    _zz_165_[16] = _zz_164_;
    _zz_165_[15] = _zz_164_;
    _zz_165_[14] = _zz_164_;
    _zz_165_[13] = _zz_164_;
    _zz_165_[12] = _zz_164_;
    _zz_165_[11] = _zz_164_;
    _zz_165_[10] = _zz_164_;
    _zz_165_[9] = _zz_164_;
    _zz_165_[8] = _zz_164_;
    _zz_165_[7] = _zz_164_;
    _zz_165_[6] = _zz_164_;
    _zz_165_[5] = _zz_164_;
    _zz_165_[4] = _zz_164_;
    _zz_165_[3] = _zz_164_;
    _zz_165_[2] = _zz_164_;
    _zz_165_[1] = _zz_164_;
    _zz_165_[0] = _zz_164_;
  end

  assign _zz_166_ = _zz_389_[11];
  always @ (*) begin
    _zz_167_[19] = _zz_166_;
    _zz_167_[18] = _zz_166_;
    _zz_167_[17] = _zz_166_;
    _zz_167_[16] = _zz_166_;
    _zz_167_[15] = _zz_166_;
    _zz_167_[14] = _zz_166_;
    _zz_167_[13] = _zz_166_;
    _zz_167_[12] = _zz_166_;
    _zz_167_[11] = _zz_166_;
    _zz_167_[10] = _zz_166_;
    _zz_167_[9] = _zz_166_;
    _zz_167_[8] = _zz_166_;
    _zz_167_[7] = _zz_166_;
    _zz_167_[6] = _zz_166_;
    _zz_167_[5] = _zz_166_;
    _zz_167_[4] = _zz_166_;
    _zz_167_[3] = _zz_166_;
    _zz_167_[2] = _zz_166_;
    _zz_167_[1] = _zz_166_;
    _zz_167_[0] = _zz_166_;
  end

  always @ (*) begin
    case(execute_SRC2_CTRL)
      `Src2CtrlEnum_defaultEncoding_RS : begin
        _zz_168_ = execute_RS2;
      end
      `Src2CtrlEnum_defaultEncoding_IMI : begin
        _zz_168_ = {_zz_165_,execute_INSTRUCTION[31 : 20]};
      end
      `Src2CtrlEnum_defaultEncoding_IMS : begin
        _zz_168_ = {_zz_167_,{execute_INSTRUCTION[31 : 25],execute_INSTRUCTION[11 : 7]}};
      end
      default : begin
        _zz_168_ = _zz_51_;
      end
    endcase
  end

  assign _zz_53_ = _zz_168_;
  assign execute_SrcPlugin_addSub = _zz_390_;
  assign execute_SrcPlugin_less = ((execute_SRC1[31] == execute_SRC2[31]) ? execute_SrcPlugin_addSub[31] : (execute_SRC_LESS_UNSIGNED ? execute_SRC2[31] : execute_SRC1[31]));
  assign _zz_50_ = execute_SrcPlugin_addSub;
  assign _zz_49_ = execute_SrcPlugin_addSub;
  assign _zz_48_ = execute_SrcPlugin_less;
  assign execute_FullBarrelShifterPlugin_amplitude = execute_SRC2[4 : 0];
  always @ (*) begin
    _zz_169_[0] = execute_SRC1[31];
    _zz_169_[1] = execute_SRC1[30];
    _zz_169_[2] = execute_SRC1[29];
    _zz_169_[3] = execute_SRC1[28];
    _zz_169_[4] = execute_SRC1[27];
    _zz_169_[5] = execute_SRC1[26];
    _zz_169_[6] = execute_SRC1[25];
    _zz_169_[7] = execute_SRC1[24];
    _zz_169_[8] = execute_SRC1[23];
    _zz_169_[9] = execute_SRC1[22];
    _zz_169_[10] = execute_SRC1[21];
    _zz_169_[11] = execute_SRC1[20];
    _zz_169_[12] = execute_SRC1[19];
    _zz_169_[13] = execute_SRC1[18];
    _zz_169_[14] = execute_SRC1[17];
    _zz_169_[15] = execute_SRC1[16];
    _zz_169_[16] = execute_SRC1[15];
    _zz_169_[17] = execute_SRC1[14];
    _zz_169_[18] = execute_SRC1[13];
    _zz_169_[19] = execute_SRC1[12];
    _zz_169_[20] = execute_SRC1[11];
    _zz_169_[21] = execute_SRC1[10];
    _zz_169_[22] = execute_SRC1[9];
    _zz_169_[23] = execute_SRC1[8];
    _zz_169_[24] = execute_SRC1[7];
    _zz_169_[25] = execute_SRC1[6];
    _zz_169_[26] = execute_SRC1[5];
    _zz_169_[27] = execute_SRC1[4];
    _zz_169_[28] = execute_SRC1[3];
    _zz_169_[29] = execute_SRC1[2];
    _zz_169_[30] = execute_SRC1[1];
    _zz_169_[31] = execute_SRC1[0];
  end

  assign execute_FullBarrelShifterPlugin_reversed = ((execute_SHIFT_CTRL == `ShiftCtrlEnum_defaultEncoding_SLL_1) ? _zz_169_ : execute_SRC1);
  assign _zz_46_ = _zz_399_;
  always @ (*) begin
    _zz_170_[0] = memory_SHIFT_RIGHT[31];
    _zz_170_[1] = memory_SHIFT_RIGHT[30];
    _zz_170_[2] = memory_SHIFT_RIGHT[29];
    _zz_170_[3] = memory_SHIFT_RIGHT[28];
    _zz_170_[4] = memory_SHIFT_RIGHT[27];
    _zz_170_[5] = memory_SHIFT_RIGHT[26];
    _zz_170_[6] = memory_SHIFT_RIGHT[25];
    _zz_170_[7] = memory_SHIFT_RIGHT[24];
    _zz_170_[8] = memory_SHIFT_RIGHT[23];
    _zz_170_[9] = memory_SHIFT_RIGHT[22];
    _zz_170_[10] = memory_SHIFT_RIGHT[21];
    _zz_170_[11] = memory_SHIFT_RIGHT[20];
    _zz_170_[12] = memory_SHIFT_RIGHT[19];
    _zz_170_[13] = memory_SHIFT_RIGHT[18];
    _zz_170_[14] = memory_SHIFT_RIGHT[17];
    _zz_170_[15] = memory_SHIFT_RIGHT[16];
    _zz_170_[16] = memory_SHIFT_RIGHT[15];
    _zz_170_[17] = memory_SHIFT_RIGHT[14];
    _zz_170_[18] = memory_SHIFT_RIGHT[13];
    _zz_170_[19] = memory_SHIFT_RIGHT[12];
    _zz_170_[20] = memory_SHIFT_RIGHT[11];
    _zz_170_[21] = memory_SHIFT_RIGHT[10];
    _zz_170_[22] = memory_SHIFT_RIGHT[9];
    _zz_170_[23] = memory_SHIFT_RIGHT[8];
    _zz_170_[24] = memory_SHIFT_RIGHT[7];
    _zz_170_[25] = memory_SHIFT_RIGHT[6];
    _zz_170_[26] = memory_SHIFT_RIGHT[5];
    _zz_170_[27] = memory_SHIFT_RIGHT[4];
    _zz_170_[28] = memory_SHIFT_RIGHT[3];
    _zz_170_[29] = memory_SHIFT_RIGHT[2];
    _zz_170_[30] = memory_SHIFT_RIGHT[1];
    _zz_170_[31] = memory_SHIFT_RIGHT[0];
  end

  assign execute_MulPlugin_a = execute_SRC1;
  assign execute_MulPlugin_b = execute_SRC2;
  always @ (*) begin
    case(_zz_355_)
      2'b01 : begin
        execute_MulPlugin_aSigned = 1'b1;
        execute_MulPlugin_bSigned = 1'b1;
      end
      2'b10 : begin
        execute_MulPlugin_aSigned = 1'b1;
        execute_MulPlugin_bSigned = 1'b0;
      end
      default : begin
        execute_MulPlugin_aSigned = 1'b0;
        execute_MulPlugin_bSigned = 1'b0;
      end
    endcase
  end

  assign execute_MulPlugin_aULow = execute_MulPlugin_a[15 : 0];
  assign execute_MulPlugin_bULow = execute_MulPlugin_b[15 : 0];
  assign execute_MulPlugin_aSLow = {1'b0,execute_MulPlugin_a[15 : 0]};
  assign execute_MulPlugin_bSLow = {1'b0,execute_MulPlugin_b[15 : 0]};
  assign execute_MulPlugin_aHigh = {(execute_MulPlugin_aSigned && execute_MulPlugin_a[31]),execute_MulPlugin_a[31 : 16]};
  assign execute_MulPlugin_bHigh = {(execute_MulPlugin_bSigned && execute_MulPlugin_b[31]),execute_MulPlugin_b[31 : 16]};
  assign _zz_43_ = (execute_MulPlugin_aULow * execute_MulPlugin_bULow);
  assign _zz_42_ = ($signed(execute_MulPlugin_aSLow) * $signed(execute_MulPlugin_bHigh));
  assign _zz_41_ = ($signed(execute_MulPlugin_aHigh) * $signed(execute_MulPlugin_bSLow));
  assign _zz_40_ = ($signed(execute_MulPlugin_aHigh) * $signed(execute_MulPlugin_bHigh));
  assign _zz_39_ = ($signed(_zz_401_) + $signed(_zz_409_));
  assign writeBack_MulPlugin_result = ($signed(_zz_410_) + $signed(_zz_411_));
  always @ (*) begin
    memory_DivPlugin_div_counter_willClear = 1'b0;
    if(_zz_352_)begin
      memory_DivPlugin_div_counter_willClear = 1'b1;
    end
  end

  assign memory_DivPlugin_div_counter_willOverflowIfInc = (memory_DivPlugin_div_counter_value == (6'b100001));
  assign memory_DivPlugin_div_counter_willOverflow = (memory_DivPlugin_div_counter_willOverflowIfInc && memory_DivPlugin_div_counter_willIncrement);
  always @ (*) begin
    if(memory_DivPlugin_div_counter_willOverflow)begin
      memory_DivPlugin_div_counter_valueNext = (6'b000000);
    end else begin
      memory_DivPlugin_div_counter_valueNext = (memory_DivPlugin_div_counter_value + _zz_415_);
    end
    if(memory_DivPlugin_div_counter_willClear)begin
      memory_DivPlugin_div_counter_valueNext = (6'b000000);
    end
  end

  assign _zz_171_ = memory_DivPlugin_rs1[31 : 0];
  assign _zz_172_ = {memory_DivPlugin_accumulator[31 : 0],_zz_171_[31]};
  assign _zz_173_ = (_zz_172_ - _zz_416_);
  assign _zz_174_ = (memory_INSTRUCTION[13] ? memory_DivPlugin_accumulator[31 : 0] : memory_DivPlugin_rs1[31 : 0]);
  assign _zz_175_ = (execute_RS2[31] && execute_IS_RS2_SIGNED);
  assign _zz_176_ = (1'b0 || ((execute_IS_DIV && execute_RS1[31]) && execute_IS_RS1_SIGNED));
  always @ (*) begin
    _zz_177_[32] = (execute_IS_RS1_SIGNED && execute_RS1[31]);
    _zz_177_[31 : 0] = execute_RS1;
  end

  always @ (*) begin
    _zz_178_ = 1'b0;
    _zz_179_ = 1'b0;
    if((writeBack_arbitration_isValid && writeBack_REGFILE_WRITE_VALID))begin
      if((1'b0 || (! 1'b1)))begin
        if(_zz_184_)begin
          _zz_178_ = 1'b1;
        end
        if(_zz_185_)begin
          _zz_179_ = 1'b1;
        end
      end
    end
    if((memory_arbitration_isValid && memory_REGFILE_WRITE_VALID))begin
      if((1'b0 || (! memory_BYPASSABLE_MEMORY_STAGE)))begin
        if(_zz_186_)begin
          _zz_178_ = 1'b1;
        end
        if(_zz_187_)begin
          _zz_179_ = 1'b1;
        end
      end
    end
    if((execute_arbitration_isValid && execute_REGFILE_WRITE_VALID))begin
      if((1'b0 || (! execute_BYPASSABLE_EXECUTE_STAGE)))begin
        if(_zz_188_)begin
          _zz_178_ = 1'b1;
        end
        if(_zz_189_)begin
          _zz_179_ = 1'b1;
        end
      end
    end
    if((! decode_RS1_USE))begin
      _zz_178_ = 1'b0;
    end
    if((! decode_RS2_USE))begin
      _zz_179_ = 1'b0;
    end
  end

  assign _zz_180_ = (_zz_60_ && writeBack_arbitration_isFiring);
  assign _zz_184_ = (writeBack_INSTRUCTION[11 : 7] == decode_INSTRUCTION[19 : 15]);
  assign _zz_185_ = (writeBack_INSTRUCTION[11 : 7] == decode_INSTRUCTION[24 : 20]);
  assign _zz_186_ = (memory_INSTRUCTION[11 : 7] == decode_INSTRUCTION[19 : 15]);
  assign _zz_187_ = (memory_INSTRUCTION[11 : 7] == decode_INSTRUCTION[24 : 20]);
  assign _zz_188_ = (execute_INSTRUCTION[11 : 7] == decode_INSTRUCTION[19 : 15]);
  assign _zz_189_ = (execute_INSTRUCTION[11 : 7] == decode_INSTRUCTION[24 : 20]);
  assign DebugPlugin_isPipBusy = (DebugPlugin_isPipActive || DebugPlugin_isPipActive_regNext);
  always @ (*) begin
    debug_bus_cmd_ready = 1'b1;
    _zz_110_ = 1'b0;
    if(debug_bus_cmd_valid)begin
      case(_zz_353_)
        6'b000000 : begin
        end
        6'b000001 : begin
          if(debug_bus_cmd_payload_wr)begin
            _zz_110_ = 1'b1;
            debug_bus_cmd_ready = _zz_111_;
          end
        end
        default : begin
        end
      endcase
    end
  end

  always @ (*) begin
    debug_bus_rsp_data = DebugPlugin_busReadDataReg;
    if((! _zz_190_))begin
      debug_bus_rsp_data[0] = DebugPlugin_resetIt;
      debug_bus_rsp_data[1] = DebugPlugin_haltIt;
      debug_bus_rsp_data[2] = DebugPlugin_isPipBusy;
      debug_bus_rsp_data[3] = DebugPlugin_haltedByBreak;
      debug_bus_rsp_data[4] = DebugPlugin_stepIt;
    end
  end

  assign _zz_37_ = ((! DebugPlugin_haltIt) && (decode_IS_EBREAK || 1'b0));
  assign debug_resetOut = DebugPlugin_resetIt_regNext;
  assign _zz_36_ = _zz_104_;
  assign execute_BranchPlugin_eq = (execute_SRC1 == execute_SRC2);
  assign _zz_191_ = execute_INSTRUCTION[14 : 12];
  always @ (*) begin
    if((_zz_191_ == (3'b000))) begin
        _zz_192_ = execute_BranchPlugin_eq;
    end else if((_zz_191_ == (3'b001))) begin
        _zz_192_ = (! execute_BranchPlugin_eq);
    end else if((((_zz_191_ & (3'b101)) == (3'b101)))) begin
        _zz_192_ = (! execute_SRC_LESS);
    end else begin
        _zz_192_ = execute_SRC_LESS;
    end
  end

  always @ (*) begin
    case(execute_BRANCH_CTRL)
      `BranchCtrlEnum_defaultEncoding_INC : begin
        _zz_193_ = 1'b0;
      end
      `BranchCtrlEnum_defaultEncoding_JAL : begin
        _zz_193_ = 1'b1;
      end
      `BranchCtrlEnum_defaultEncoding_JALR : begin
        _zz_193_ = 1'b1;
      end
      default : begin
        _zz_193_ = _zz_192_;
      end
    endcase
  end

  assign _zz_35_ = _zz_193_;
  assign _zz_194_ = _zz_429_[11];
  always @ (*) begin
    _zz_195_[19] = _zz_194_;
    _zz_195_[18] = _zz_194_;
    _zz_195_[17] = _zz_194_;
    _zz_195_[16] = _zz_194_;
    _zz_195_[15] = _zz_194_;
    _zz_195_[14] = _zz_194_;
    _zz_195_[13] = _zz_194_;
    _zz_195_[12] = _zz_194_;
    _zz_195_[11] = _zz_194_;
    _zz_195_[10] = _zz_194_;
    _zz_195_[9] = _zz_194_;
    _zz_195_[8] = _zz_194_;
    _zz_195_[7] = _zz_194_;
    _zz_195_[6] = _zz_194_;
    _zz_195_[5] = _zz_194_;
    _zz_195_[4] = _zz_194_;
    _zz_195_[3] = _zz_194_;
    _zz_195_[2] = _zz_194_;
    _zz_195_[1] = _zz_194_;
    _zz_195_[0] = _zz_194_;
  end

  assign _zz_196_ = _zz_430_[19];
  always @ (*) begin
    _zz_197_[10] = _zz_196_;
    _zz_197_[9] = _zz_196_;
    _zz_197_[8] = _zz_196_;
    _zz_197_[7] = _zz_196_;
    _zz_197_[6] = _zz_196_;
    _zz_197_[5] = _zz_196_;
    _zz_197_[4] = _zz_196_;
    _zz_197_[3] = _zz_196_;
    _zz_197_[2] = _zz_196_;
    _zz_197_[1] = _zz_196_;
    _zz_197_[0] = _zz_196_;
  end

  assign _zz_198_ = _zz_431_[11];
  always @ (*) begin
    _zz_199_[18] = _zz_198_;
    _zz_199_[17] = _zz_198_;
    _zz_199_[16] = _zz_198_;
    _zz_199_[15] = _zz_198_;
    _zz_199_[14] = _zz_198_;
    _zz_199_[13] = _zz_198_;
    _zz_199_[12] = _zz_198_;
    _zz_199_[11] = _zz_198_;
    _zz_199_[10] = _zz_198_;
    _zz_199_[9] = _zz_198_;
    _zz_199_[8] = _zz_198_;
    _zz_199_[7] = _zz_198_;
    _zz_199_[6] = _zz_198_;
    _zz_199_[5] = _zz_198_;
    _zz_199_[4] = _zz_198_;
    _zz_199_[3] = _zz_198_;
    _zz_199_[2] = _zz_198_;
    _zz_199_[1] = _zz_198_;
    _zz_199_[0] = _zz_198_;
  end

  always @ (*) begin
    case(execute_BRANCH_CTRL)
      `BranchCtrlEnum_defaultEncoding_JALR : begin
        _zz_200_ = (_zz_432_[1] ^ execute_RS1[1]);
      end
      `BranchCtrlEnum_defaultEncoding_JAL : begin
        _zz_200_ = _zz_433_[1];
      end
      default : begin
        _zz_200_ = _zz_434_[1];
      end
    endcase
  end

  assign execute_BranchPlugin_missAlignedTarget = (execute_BRANCH_COND_RESULT && _zz_200_);
  assign _zz_33_ = ((execute_PREDICTION_HAD_BRANCHED2 != execute_BRANCH_COND_RESULT) || execute_BranchPlugin_missAlignedTarget);
  always @ (*) begin
    case(execute_BRANCH_CTRL)
      `BranchCtrlEnum_defaultEncoding_JALR : begin
        execute_BranchPlugin_branch_src1 = execute_RS1;
        execute_BranchPlugin_branch_src2 = {_zz_202_,execute_INSTRUCTION[31 : 20]};
      end
      default : begin
        execute_BranchPlugin_branch_src1 = execute_PC;
        execute_BranchPlugin_branch_src2 = ((execute_BRANCH_CTRL == `BranchCtrlEnum_defaultEncoding_JAL) ? {{_zz_204_,{{{_zz_631_,execute_INSTRUCTION[19 : 12]},execute_INSTRUCTION[20]},execute_INSTRUCTION[30 : 21]}},1'b0} : {{_zz_206_,{{{_zz_632_,_zz_633_},execute_INSTRUCTION[30 : 25]},execute_INSTRUCTION[11 : 8]}},1'b0});
        if((execute_PREDICTION_HAD_BRANCHED2 && (! execute_BranchPlugin_missAlignedTarget)))begin
          execute_BranchPlugin_branch_src2 = {29'd0, _zz_438_};
        end
      end
    endcase
  end

  assign _zz_201_ = _zz_435_[11];
  always @ (*) begin
    _zz_202_[19] = _zz_201_;
    _zz_202_[18] = _zz_201_;
    _zz_202_[17] = _zz_201_;
    _zz_202_[16] = _zz_201_;
    _zz_202_[15] = _zz_201_;
    _zz_202_[14] = _zz_201_;
    _zz_202_[13] = _zz_201_;
    _zz_202_[12] = _zz_201_;
    _zz_202_[11] = _zz_201_;
    _zz_202_[10] = _zz_201_;
    _zz_202_[9] = _zz_201_;
    _zz_202_[8] = _zz_201_;
    _zz_202_[7] = _zz_201_;
    _zz_202_[6] = _zz_201_;
    _zz_202_[5] = _zz_201_;
    _zz_202_[4] = _zz_201_;
    _zz_202_[3] = _zz_201_;
    _zz_202_[2] = _zz_201_;
    _zz_202_[1] = _zz_201_;
    _zz_202_[0] = _zz_201_;
  end

  assign _zz_203_ = _zz_436_[19];
  always @ (*) begin
    _zz_204_[10] = _zz_203_;
    _zz_204_[9] = _zz_203_;
    _zz_204_[8] = _zz_203_;
    _zz_204_[7] = _zz_203_;
    _zz_204_[6] = _zz_203_;
    _zz_204_[5] = _zz_203_;
    _zz_204_[4] = _zz_203_;
    _zz_204_[3] = _zz_203_;
    _zz_204_[2] = _zz_203_;
    _zz_204_[1] = _zz_203_;
    _zz_204_[0] = _zz_203_;
  end

  assign _zz_205_ = _zz_437_[11];
  always @ (*) begin
    _zz_206_[18] = _zz_205_;
    _zz_206_[17] = _zz_205_;
    _zz_206_[16] = _zz_205_;
    _zz_206_[15] = _zz_205_;
    _zz_206_[14] = _zz_205_;
    _zz_206_[13] = _zz_205_;
    _zz_206_[12] = _zz_205_;
    _zz_206_[11] = _zz_205_;
    _zz_206_[10] = _zz_205_;
    _zz_206_[9] = _zz_205_;
    _zz_206_[8] = _zz_205_;
    _zz_206_[7] = _zz_205_;
    _zz_206_[6] = _zz_205_;
    _zz_206_[5] = _zz_205_;
    _zz_206_[4] = _zz_205_;
    _zz_206_[3] = _zz_205_;
    _zz_206_[2] = _zz_205_;
    _zz_206_[1] = _zz_205_;
    _zz_206_[0] = _zz_205_;
  end

  assign execute_BranchPlugin_branchAdder = (execute_BranchPlugin_branch_src1 + execute_BranchPlugin_branch_src2);
  assign _zz_32_ = {execute_BranchPlugin_branchAdder[31 : 1],(1'b0)};
  assign _zz_112_ = ((memory_arbitration_isValid && (! memory_arbitration_isStuckByOthers)) && memory_BRANCH_DO);
  assign _zz_113_ = memory_BRANCH_CALC;
  assign memory_exception_agregat_valid = (memory_arbitration_isValid && (memory_BRANCH_DO && memory_BRANCH_CALC[1]));
  assign memory_exception_agregat_payload_code = (4'b0000);
  assign memory_exception_agregat_payload_badAddr = memory_BRANCH_CALC;
  assign CsrPlugin_misa_base = (2'b01);
  assign CsrPlugin_misa_extensions = (26'b00000000000000000001000010);
  assign CsrPlugin_mtvec_mode = (2'b00);
  // bard0: CsrPlugin_mtvec_base is now a reg — driven by reset init and CSR write case
  assign CsrPlugin_medeleg = (32'b00000000000000000000000000000000);
  assign CsrPlugin_mideleg = (32'b00000000000000000000000000000000);
  assign _zz_207_ = (CsrPlugin_mip_MTIP && CsrPlugin_mie_MTIE);
  assign _zz_208_ = (CsrPlugin_mip_MSIP && CsrPlugin_mie_MSIE);
  assign _zz_209_ = (CsrPlugin_mip_MEIP && CsrPlugin_mie_MEIE);
  assign CsrPlugin_exceptionPortCtrl_exceptionTargetPrivilege = CsrPlugin_privilege;
  assign decode_exception_agregat_valid = (_zz_107_ || decodeExceptionPort_valid);
  assign _zz_210_ = {decodeExceptionPort_valid,_zz_107_};
  assign _zz_211_ = _zz_439_[0];
  assign decode_exception_agregat_payload_code = (_zz_211_ ? (_zz_288_ ? (4'b1110) : (4'b0001)) : decodeExceptionPort_1_code);
  assign decode_exception_agregat_payload_badAddr = (_zz_211_ ? IBusCachedPlugin_stages_2_input_payload : decodeExceptionPort_1_badAddr);
  always @ (*) begin
    CsrPlugin_exceptionPortCtrl_exceptionValids_decode = CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_decode;
    if(decode_exception_agregat_valid)begin
      CsrPlugin_exceptionPortCtrl_exceptionValids_decode = 1'b1;
    end
    if(decode_arbitration_isFlushed)begin
      CsrPlugin_exceptionPortCtrl_exceptionValids_decode = 1'b0;
    end
  end

  always @ (*) begin
    CsrPlugin_exceptionPortCtrl_exceptionValids_execute = CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute;
    if(execute_arbitration_isFlushed)begin
      CsrPlugin_exceptionPortCtrl_exceptionValids_execute = 1'b0;
    end
  end

  always @ (*) begin
    CsrPlugin_exceptionPortCtrl_exceptionValids_memory = CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory;
    if(memory_exception_agregat_valid)begin
      CsrPlugin_exceptionPortCtrl_exceptionValids_memory = 1'b1;
    end
    if(memory_arbitration_isFlushed)begin
      CsrPlugin_exceptionPortCtrl_exceptionValids_memory = 1'b0;
    end
  end

  always @ (*) begin
    CsrPlugin_interrupt = 1'b0;
    CsrPlugin_interruptCode = (4'bxxxx);
    CsrPlugin_interruptTargetPrivilege = (2'bxx);
    if(CsrPlugin_mstatus_MIE)begin
      if(((_zz_207_ || _zz_208_) || _zz_209_))begin
        CsrPlugin_interrupt = 1'b1;
      end
      if(_zz_207_)begin
        CsrPlugin_interruptCode = (4'b0111);
        CsrPlugin_interruptTargetPrivilege = (2'b11);
      end
      if(_zz_208_)begin
        CsrPlugin_interruptCode = (4'b0011);
        CsrPlugin_interruptTargetPrivilege = (2'b11);
      end
      if(_zz_209_)begin
        CsrPlugin_interruptCode = (4'b1011);
        CsrPlugin_interruptTargetPrivilege = (2'b11);
      end
    end
    if((! _zz_116_))begin
      CsrPlugin_interrupt = 1'b0;
    end
  end

  assign CsrPlugin_exception = (CsrPlugin_exceptionPortCtrl_exceptionValids_writeBack && _zz_117_);
  assign CsrPlugin_lastStageWasWfi = 1'b0;
  always @ (*) begin
    CsrPlugin_pipelineLiberator_done = ((! ((execute_arbitration_isValid || memory_arbitration_isValid) || writeBack_arbitration_isValid)) && IBusCachedPlugin_injector_nextPcCalc_3);
    if(((CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute || CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory) || CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack))begin
      CsrPlugin_pipelineLiberator_done = 1'b0;
    end
    if(CsrPlugin_hadException)begin
      CsrPlugin_pipelineLiberator_done = 1'b0;
    end
  end

  assign CsrPlugin_interruptJump = (CsrPlugin_interrupt && CsrPlugin_pipelineLiberator_done);
  always @ (*) begin
    CsrPlugin_targetPrivilege = CsrPlugin_interruptTargetPrivilege;
    if(CsrPlugin_hadException)begin
      CsrPlugin_targetPrivilege = CsrPlugin_exceptionPortCtrl_exceptionTargetPrivilege;
    end
  end

  always @ (*) begin
    CsrPlugin_trapCause = CsrPlugin_interruptCode;
    if(CsrPlugin_hadException)begin
      CsrPlugin_trapCause = CsrPlugin_exceptionPortCtrl_exceptionContext_code;
    end
  end

  assign contextSwitching = _zz_114_;
  assign _zz_30_ = (! (((decode_INSTRUCTION[14 : 13] == (2'b01)) && (decode_INSTRUCTION[19 : 15] == (5'b00000))) || ((decode_INSTRUCTION[14 : 13] == (2'b11)) && (decode_INSTRUCTION[19 : 15] == (5'b00000)))));
  assign _zz_29_ = (decode_INSTRUCTION[13 : 7] != (7'b0100000));
  assign execute_CsrPlugin_blockedBySideEffects = ({writeBack_arbitration_isValid,memory_arbitration_isValid} != (2'b00));
  always @ (*) begin
    execute_CsrPlugin_illegalAccess = 1'b1;
    execute_CsrPlugin_readData = (32'b00000000000000000000000000000000);
    case(execute_CsrPlugin_csrAddress)
      12'b001100000000 : begin
        execute_CsrPlugin_illegalAccess = 1'b0;
        execute_CsrPlugin_readData[12 : 11] = CsrPlugin_mstatus_MPP;
        execute_CsrPlugin_readData[7 : 7] = CsrPlugin_mstatus_MPIE;
        execute_CsrPlugin_readData[3 : 3] = CsrPlugin_mstatus_MIE;
      end
      12'b001101000001 : begin
        execute_CsrPlugin_illegalAccess = 1'b0;
        execute_CsrPlugin_readData[31 : 0] = CsrPlugin_mepc;
      end
      12'b001101000100 : begin
        execute_CsrPlugin_illegalAccess = 1'b0;
        execute_CsrPlugin_readData[11 : 11] = CsrPlugin_mip_MEIP;
        execute_CsrPlugin_readData[7 : 7] = CsrPlugin_mip_MTIP;
        execute_CsrPlugin_readData[3 : 3] = CsrPlugin_mip_MSIP;
      end
      12'b001101000011 : begin
        if(execute_CSR_READ_OPCODE)begin
          execute_CsrPlugin_illegalAccess = 1'b0;
        end
        execute_CsrPlugin_readData[31 : 0] = CsrPlugin_mtval;
      end
      12'b001100000100 : begin
        execute_CsrPlugin_illegalAccess = 1'b0;
        execute_CsrPlugin_readData[11 : 11] = CsrPlugin_mie_MEIE;
        execute_CsrPlugin_readData[7 : 7] = CsrPlugin_mie_MTIE;
        execute_CsrPlugin_readData[3 : 3] = CsrPlugin_mie_MSIE;
      end
      12'b001101000010 : begin
        if(execute_CSR_READ_OPCODE)begin
          execute_CsrPlugin_illegalAccess = 1'b0;
        end
        execute_CsrPlugin_readData[31 : 31] = CsrPlugin_mcause_interrupt;
        execute_CsrPlugin_readData[3 : 0] = CsrPlugin_mcause_exceptionCode;
      end
      12'b001100000101 : begin   // bard0: mtvec (0x305) — read/write
        execute_CsrPlugin_illegalAccess = 1'b0;
        execute_CsrPlugin_readData[31 : 2] = CsrPlugin_mtvec_base;
        execute_CsrPlugin_readData[1 : 0]  = CsrPlugin_mtvec_mode;
      end
      12'b111100010100 : begin   // bard0: mhartid (0xf14) — read-only zero
        if(execute_CSR_READ_OPCODE)begin
          execute_CsrPlugin_illegalAccess = 1'b0;
        end
      end
      12'b111100010001 : begin   // bard0: mvendorid (0xf11) — read-only zero
        if(execute_CSR_READ_OPCODE)begin
          execute_CsrPlugin_illegalAccess = 1'b0;
        end
      end
      12'b111100010010 : begin   // bard0: marchid (0xf12) — read-only zero
        if(execute_CSR_READ_OPCODE)begin
          execute_CsrPlugin_illegalAccess = 1'b0;
        end
      end
      12'b111100010011 : begin   // bard0: mimpid (0xf13) — read-only zero
        if(execute_CSR_READ_OPCODE)begin
          execute_CsrPlugin_illegalAccess = 1'b0;
        end
      end
      12'b001100000001 : begin   // bard0: misa (0x301) — read-only zero (Zephyr may probe)
        if(execute_CSR_READ_OPCODE)begin
          execute_CsrPlugin_illegalAccess = 1'b0;
        end
      end
      default : begin
      end
    endcase
    if((CsrPlugin_privilege < execute_CsrPlugin_csrAddress[9 : 8]))begin
      execute_CsrPlugin_illegalAccess = 1'b1;
    end
    if(((! execute_arbitration_isValid) || (! execute_IS_CSR)))begin
      execute_CsrPlugin_illegalAccess = 1'b0;
    end
  end

  always @ (*) begin
    execute_CsrPlugin_illegalInstruction = 1'b0;
    if((execute_arbitration_isValid && (execute_ENV_CTRL == `EnvCtrlEnum_defaultEncoding_XRET)))begin
      if((execute_INSTRUCTION[29 : 28] != CsrPlugin_privilege))begin
        execute_CsrPlugin_illegalInstruction = 1'b1;
      end
    end
  end

  assign execute_CsrPlugin_writeInstruction = ((execute_arbitration_isValid && execute_IS_CSR) && execute_CSR_WRITE_OPCODE);
  assign execute_CsrPlugin_readInstruction = ((execute_arbitration_isValid && execute_IS_CSR) && execute_CSR_READ_OPCODE);
  assign execute_CsrPlugin_writeEnable = ((execute_CsrPlugin_writeInstruction && (! execute_CsrPlugin_blockedBySideEffects)) && (! execute_arbitration_isStuckByOthers));
  assign execute_CsrPlugin_readEnable = ((execute_CsrPlugin_readInstruction && (! execute_CsrPlugin_blockedBySideEffects)) && (! execute_arbitration_isStuckByOthers));
  always @ (*) begin
    case(_zz_358_)
      1'b0 : begin
        execute_CsrPlugin_writeData = execute_SRC1;
      end
      default : begin
        execute_CsrPlugin_writeData = (execute_INSTRUCTION[12] ? (execute_CsrPlugin_readData & (~ execute_SRC1)) : (execute_CsrPlugin_readData | execute_SRC1));
      end
    endcase
  end

  assign execute_CsrPlugin_csrAddress = execute_INSTRUCTION[31 : 20];
  assign _zz_26_ = decode_ENV_CTRL;
  assign _zz_23_ = execute_ENV_CTRL;
  assign _zz_21_ = memory_ENV_CTRL;
  assign _zz_24_ = _zz_64_;
  assign _zz_28_ = decode_to_execute_ENV_CTRL;
  assign _zz_27_ = execute_to_memory_ENV_CTRL;
  assign _zz_31_ = memory_to_writeBack_ENV_CTRL;
  assign _zz_19_ = decode_SRC1_CTRL;
  assign _zz_17_ = _zz_70_;
  assign _zz_54_ = decode_to_execute_SRC1_CTRL;
  assign _zz_16_ = decode_ALU_CTRL;
  assign _zz_14_ = _zz_71_;
  assign _zz_56_ = decode_to_execute_ALU_CTRL;
  assign _zz_13_ = decode_ALU_BITWISE_CTRL;
  assign _zz_11_ = _zz_78_;
  assign _zz_58_ = decode_to_execute_ALU_BITWISE_CTRL;
  assign _zz_10_ = decode_BRANCH_CTRL;
  assign _zz_93_ = _zz_86_;
  assign _zz_34_ = decode_to_execute_BRANCH_CTRL;
  assign _zz_8_ = decode_SHIFT_CTRL;
  assign _zz_5_ = execute_SHIFT_CTRL;
  assign _zz_6_ = _zz_75_;
  assign _zz_47_ = decode_to_execute_SHIFT_CTRL;
  assign _zz_45_ = execute_to_memory_SHIFT_CTRL;
  assign _zz_3_ = decode_SRC2_CTRL;
  assign _zz_1_ = _zz_74_;
  assign _zz_52_ = decode_to_execute_SRC2_CTRL;
  assign decode_arbitration_isFlushed = (((decode_arbitration_flushAll || execute_arbitration_flushAll) || memory_arbitration_flushAll) || writeBack_arbitration_flushAll);
  assign execute_arbitration_isFlushed = ((execute_arbitration_flushAll || memory_arbitration_flushAll) || writeBack_arbitration_flushAll);
  assign memory_arbitration_isFlushed = (memory_arbitration_flushAll || writeBack_arbitration_flushAll);
  assign writeBack_arbitration_isFlushed = writeBack_arbitration_flushAll;
  assign decode_arbitration_isStuckByOthers = (decode_arbitration_haltByOther || (((1'b0 || execute_arbitration_isStuck) || memory_arbitration_isStuck) || writeBack_arbitration_isStuck));
  assign decode_arbitration_isStuck = (decode_arbitration_haltItself || decode_arbitration_isStuckByOthers);
  assign decode_arbitration_isMoving = ((! decode_arbitration_isStuck) && (! decode_arbitration_removeIt));
  assign decode_arbitration_isFiring = ((decode_arbitration_isValid && (! decode_arbitration_isStuck)) && (! decode_arbitration_removeIt));
  assign execute_arbitration_isStuckByOthers = (execute_arbitration_haltByOther || ((1'b0 || memory_arbitration_isStuck) || writeBack_arbitration_isStuck));
  assign execute_arbitration_isStuck = (execute_arbitration_haltItself || execute_arbitration_isStuckByOthers);
  assign execute_arbitration_isMoving = ((! execute_arbitration_isStuck) && (! execute_arbitration_removeIt));
  assign execute_arbitration_isFiring = ((execute_arbitration_isValid && (! execute_arbitration_isStuck)) && (! execute_arbitration_removeIt));
  assign memory_arbitration_isStuckByOthers = (memory_arbitration_haltByOther || (1'b0 || writeBack_arbitration_isStuck));
  assign memory_arbitration_isStuck = (memory_arbitration_haltItself || memory_arbitration_isStuckByOthers);
  assign memory_arbitration_isMoving = ((! memory_arbitration_isStuck) && (! memory_arbitration_removeIt));
  assign memory_arbitration_isFiring = ((memory_arbitration_isValid && (! memory_arbitration_isStuck)) && (! memory_arbitration_removeIt));
  assign writeBack_arbitration_isStuckByOthers = (writeBack_arbitration_haltByOther || 1'b0);
  assign writeBack_arbitration_isStuck = (writeBack_arbitration_haltItself || writeBack_arbitration_isStuckByOthers);
  assign writeBack_arbitration_isMoving = ((! writeBack_arbitration_isStuck) && (! writeBack_arbitration_removeIt));
  assign writeBack_arbitration_isFiring = ((writeBack_arbitration_isValid && (! writeBack_arbitration_isStuck)) && (! writeBack_arbitration_removeIt));
  assign iBus_cmd_ready = iBusAxi_ar_ready;
  assign iBus_rsp_valid = iBusAxi_r_valid;
  assign iBus_rsp_payload_data = iBusAxi_r_payload_data;
  assign iBus_rsp_payload_error = (! (iBusAxi_r_payload_resp == (2'b00)));
  assign iBusAxi_ar_valid = iBus_cmd_valid;
  assign iBusAxi_ar_payload_addr = iBus_cmd_payload_address;
  assign _zz_214_[0 : 0] = (1'b0);
  assign iBusAxi_ar_payload_id = _zz_214_;
  assign _zz_215_[3 : 0] = (4'b0000);
  assign iBusAxi_ar_payload_region = _zz_215_;
  assign iBusAxi_ar_payload_len = (8'b00000111);
  assign iBusAxi_ar_payload_size = (3'b010);
  assign iBusAxi_ar_payload_burst = (2'b01);
  assign iBusAxi_ar_payload_lock = (1'b0);
  assign iBusAxi_ar_payload_cache = (4'b1111);
  assign iBusAxi_ar_payload_qos = (4'b0000);
  assign iBusAxi_ar_payload_prot = (3'b110);
  assign iBusAxi_r_ready = 1'b1;
  always @ (*) begin
    _zz_220_ = 1'b0;
    if(((_zz_216_ && _zz_217_) && _zz_218_))begin
      _zz_220_ = 1'b1;
    end
  end

  always @ (*) begin
    _zz_221_ = 1'b0;
    if((_zz_233_ && 1'b1))begin
      _zz_221_ = 1'b1;
    end
  end

  always @ (*) begin
    if((_zz_220_ && (! _zz_221_)))begin
      _zz_223_ = (3'b001);
    end else begin
      if(((! _zz_220_) && _zz_221_))begin
        _zz_223_ = (3'b111);
      end else begin
        _zz_223_ = (3'b000);
      end
    end
  end

  assign _zz_224_ = (_zz_222_ + _zz_223_);
  assign _zz_225_ = (! (((_zz_222_ != (3'b000)) && (! dBus_cmd_payload_wr)) || (_zz_222_ == (3'b111))));
  assign dBus_cmd_ready = (_zz_315_ && _zz_225_);
  assign _zz_272_ = (dBus_cmd_valid && _zz_225_);
  always @ (*) begin
    _zz_227_ = _zz_316_;
    _zz_273_ = _zz_217_;
    if(_zz_226_)begin
      _zz_227_ = 1'b0;
      _zz_273_ = 1'b1;
    end
  end

  always @ (*) begin
    _zz_228_ = _zz_323_;
    _zz_274_ = _zz_219_;
    if((! _zz_324_))begin
      _zz_228_ = 1'b0;
      _zz_274_ = 1'b1;
    end
  end

  assign _zz_216_ = _zz_227_;
  assign _zz_218_ = _zz_317_;
  assign dBus_rsp_valid = _zz_234_;
  assign dBus_rsp_payload_error = (! (_zz_236_ == (2'b00)));
  assign dBus_rsp_payload_data = _zz_235_;
  assign _zz_229_ = _zz_216_;
  assign _zz_217_ = (_zz_232_ ? dBusAxi_aw_ready : dBusAxi_ar_ready);
  assign _zz_230_ = _zz_318_;
  assign _zz_231_ = {5'd0, _zz_321_};
  assign _zz_232_ = _zz_218_;
  assign _zz_219_ = _zz_237_;
  assign _zz_234_ = dBusAxi_r_valid;
  assign _zz_235_ = dBusAxi_r_payload_data;
  assign _zz_236_ = dBusAxi_r_payload_resp;
  assign _zz_233_ = dBusAxi_b_valid;
  assign dBusAxi_ar_valid = (_zz_229_ && (! _zz_232_));
  assign dBusAxi_ar_payload_addr = _zz_230_;
  assign _zz_238_[0 : 0] = (1'b0);
  assign dBusAxi_ar_payload_id = _zz_238_;
  assign _zz_239_[3 : 0] = (4'b0000);
  assign dBusAxi_ar_payload_region = _zz_239_;
  assign dBusAxi_ar_payload_len = _zz_231_;
  assign dBusAxi_ar_payload_size = (3'b010);
  assign dBusAxi_ar_payload_burst = (2'b01);
  assign dBusAxi_ar_payload_lock = (1'b0);
  assign dBusAxi_ar_payload_cache = (4'b1111);
  assign dBusAxi_ar_payload_qos = (4'b0000);
  assign dBusAxi_ar_payload_prot = (3'b010);
  assign dBusAxi_aw_valid = (_zz_229_ && _zz_232_);
  assign dBusAxi_aw_payload_addr = _zz_230_;
  assign _zz_240_[0 : 0] = (1'b0);
  assign dBusAxi_aw_payload_id = _zz_240_;
  assign _zz_241_[3 : 0] = (4'b0000);
  assign dBusAxi_aw_payload_region = _zz_241_;
  assign dBusAxi_aw_payload_len = _zz_231_;
  assign dBusAxi_aw_payload_size = (3'b010);
  assign dBusAxi_aw_payload_burst = (2'b01);
  assign dBusAxi_aw_payload_lock = (1'b0);
  assign dBusAxi_aw_payload_cache = (4'b1111);
  assign dBusAxi_aw_payload_qos = (4'b0000);
  assign dBusAxi_aw_payload_prot = (3'b010);
  assign dBusAxi_w_valid = _zz_228_;
  assign _zz_237_ = dBusAxi_w_ready;
  assign dBusAxi_w_payload_data = _zz_326_;
  assign dBusAxi_w_payload_strb = _zz_327_;
  assign dBusAxi_w_payload_last = _zz_329_;
  assign dBusAxi_r_ready = 1'b1;
  assign dBusAxi_b_ready = 1'b1;
  assign debug_bus_cmd_valid = _zz_339_;
  assign debug_bus_cmd_payload_wr = _zz_342_;
  assign debug_bus_cmd_payload_address = _zz_340_[7:0];
  assign debug_bus_cmd_payload_data = _zz_341_;
  assign jtag_tdo = _zz_330_;
  always @ (posedge clk or posedge reset) begin
    if (reset) begin
      CsrPlugin_privilege <= (2'b11);
      // bard0: mtvec_base init lives at its declaration to keep a single driver in the write always block
      IBusCachedPlugin_fetchPc_pcReg <= (32'b10010000000000000000000000000000);   // bard0: resetVector -> 0x9000_0000 (DDR direct; CPU held in reset until DDR loaded)
      IBusCachedPlugin_fetchPc_inc <= 1'b0;
      _zz_124_ <= 1'b0;
      _zz_130_ <= 1'b0;
      _zz_132_ <= 1'b0;
      IBusCachedPlugin_injector_nextPcCalc_valids_0 <= 1'b0;
      IBusCachedPlugin_injector_nextPcCalc_0 <= 1'b0;
      IBusCachedPlugin_injector_nextPcCalc_1 <= 1'b0;
      IBusCachedPlugin_injector_nextPcCalc_2 <= 1'b0;
      IBusCachedPlugin_injector_nextPcCalc_3 <= 1'b0;
      IBusCachedPlugin_injector_decodeRemoved <= 1'b0;
      _zz_161_ <= 1'b1;
      memory_DivPlugin_div_counter_value <= (6'b000000);
      _zz_181_ <= 1'b0;
      CsrPlugin_mstatus_MIE <= 1'b0;
      CsrPlugin_mstatus_MPIE <= 1'b0;
      CsrPlugin_mstatus_MPP <= (2'b11);
      CsrPlugin_mip_MEIP <= 1'b0;
      CsrPlugin_mip_MTIP <= 1'b0;
      CsrPlugin_mip_MSIP <= 1'b0;
      CsrPlugin_mie_MEIE <= 1'b0;
      CsrPlugin_mie_MTIE <= 1'b0;
      CsrPlugin_mie_MSIE <= 1'b0;
      CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_decode <= 1'b0;
      CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute <= 1'b0;
      CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory <= 1'b0;
      CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack <= 1'b0;
      CsrPlugin_hadException <= 1'b0;
      execute_arbitration_isValid <= 1'b0;
      memory_arbitration_isValid <= 1'b0;
      writeBack_arbitration_isValid <= 1'b0;
      _zz_212_ <= (3'b000);
      memory_to_writeBack_REGFILE_WRITE_DATA <= (32'b00000000000000000000000000000000);
      memory_to_writeBack_INSTRUCTION <= (32'b00000000000000000000000000000000);
      _zz_222_ <= (3'b000);
      _zz_226_ <= 1'b0;
      _zz_242_ <= 1'b0;
    end else begin
      if(IBusCachedPlugin_fetchPc_propagatePc)begin
        IBusCachedPlugin_fetchPc_inc <= 1'b0;
      end
      if(IBusCachedPlugin_jump_pcLoad_valid)begin
        IBusCachedPlugin_fetchPc_inc <= 1'b0;
      end
      if(_zz_351_)begin
        IBusCachedPlugin_fetchPc_inc <= 1'b1;
      end
      if(IBusCachedPlugin_fetchPc_samplePcNext)begin
        IBusCachedPlugin_fetchPc_pcReg <= IBusCachedPlugin_fetchPc_pc;
      end
      _zz_124_ <= 1'b1;
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_100_))begin
        _zz_130_ <= 1'b0;
      end
      if(_zz_128_)begin
        _zz_130_ <= IBusCachedPlugin_iBusRsp_stages_0_output_valid;
      end
      if(IBusCachedPlugin_iBusRsp_stages_1_output_ready)begin
        _zz_132_ <= IBusCachedPlugin_iBusRsp_stages_1_output_valid;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_100_))begin
        _zz_132_ <= 1'b0;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_100_))begin
        IBusCachedPlugin_injector_nextPcCalc_valids_0 <= 1'b0;
      end
      if((! (! IBusCachedPlugin_iBusRsp_stages_1_input_ready)))begin
        IBusCachedPlugin_injector_nextPcCalc_valids_0 <= 1'b1;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_100_))begin
        IBusCachedPlugin_injector_nextPcCalc_0 <= 1'b0;
      end
      if((! (! IBusCachedPlugin_stages_2_input_ready)))begin
        IBusCachedPlugin_injector_nextPcCalc_0 <= IBusCachedPlugin_injector_nextPcCalc_valids_0;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_100_))begin
        IBusCachedPlugin_injector_nextPcCalc_0 <= 1'b0;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_100_))begin
        IBusCachedPlugin_injector_nextPcCalc_1 <= 1'b0;
      end
      if((! execute_arbitration_isStuck))begin
        IBusCachedPlugin_injector_nextPcCalc_1 <= IBusCachedPlugin_injector_nextPcCalc_0;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_100_))begin
        IBusCachedPlugin_injector_nextPcCalc_1 <= 1'b0;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_100_))begin
        IBusCachedPlugin_injector_nextPcCalc_2 <= 1'b0;
      end
      if((! memory_arbitration_isStuck))begin
        IBusCachedPlugin_injector_nextPcCalc_2 <= IBusCachedPlugin_injector_nextPcCalc_1;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_100_))begin
        IBusCachedPlugin_injector_nextPcCalc_2 <= 1'b0;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_100_))begin
        IBusCachedPlugin_injector_nextPcCalc_3 <= 1'b0;
      end
      if((! writeBack_arbitration_isStuck))begin
        IBusCachedPlugin_injector_nextPcCalc_3 <= IBusCachedPlugin_injector_nextPcCalc_2;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_100_))begin
        IBusCachedPlugin_injector_nextPcCalc_3 <= 1'b0;
      end
      if(decode_arbitration_removeIt)begin
        IBusCachedPlugin_injector_decodeRemoved <= 1'b1;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_100_))begin
        IBusCachedPlugin_injector_decodeRemoved <= 1'b0;
      end
      _zz_161_ <= 1'b0;
      memory_DivPlugin_div_counter_value <= memory_DivPlugin_div_counter_valueNext;
      _zz_181_ <= _zz_180_;
      CsrPlugin_mip_MEIP <= externalInterrupt;
      CsrPlugin_mip_MTIP <= timerInterrupt;
      if((! decode_arbitration_isStuck))begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_decode <= 1'b0;
      end else begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_decode <= CsrPlugin_exceptionPortCtrl_exceptionValids_decode;
      end
      if((! execute_arbitration_isStuck))begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute <= (CsrPlugin_exceptionPortCtrl_exceptionValids_decode && (! decode_arbitration_isStuck));
      end else begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute <= CsrPlugin_exceptionPortCtrl_exceptionValids_execute;
      end
      if((! memory_arbitration_isStuck))begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory <= (CsrPlugin_exceptionPortCtrl_exceptionValids_execute && (! execute_arbitration_isStuck));
      end else begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory <= CsrPlugin_exceptionPortCtrl_exceptionValids_memory;
      end
      if((! writeBack_arbitration_isStuck))begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack <= (CsrPlugin_exceptionPortCtrl_exceptionValids_memory && (! memory_arbitration_isStuck));
      end else begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack <= 1'b0;
      end
      CsrPlugin_hadException <= CsrPlugin_exception;
      if(_zz_349_)begin
        case(CsrPlugin_targetPrivilege)
          2'b11 : begin
            CsrPlugin_mstatus_MIE <= 1'b0;
            CsrPlugin_mstatus_MPIE <= CsrPlugin_mstatus_MIE;
            CsrPlugin_mstatus_MPP <= CsrPlugin_privilege;
          end
          default : begin
          end
        endcase
      end
      if(_zz_350_)begin
        case(_zz_357_)
          2'b11 : begin
            CsrPlugin_mstatus_MIE <= CsrPlugin_mstatus_MPIE;
            CsrPlugin_mstatus_MPP <= (2'b00);
            CsrPlugin_mstatus_MPIE <= 1'b1;
            CsrPlugin_privilege <= CsrPlugin_mstatus_MPP;
          end
          default : begin
          end
        endcase
      end
      if((! writeBack_arbitration_isStuck))begin
        memory_to_writeBack_INSTRUCTION <= memory_INSTRUCTION;
      end
      if((! writeBack_arbitration_isStuck))begin
        memory_to_writeBack_REGFILE_WRITE_DATA <= _zz_44_;
      end
      if(((! execute_arbitration_isStuck) || execute_arbitration_removeIt))begin
        execute_arbitration_isValid <= 1'b0;
      end
      if(((! decode_arbitration_isStuck) && (! decode_arbitration_removeIt)))begin
        execute_arbitration_isValid <= decode_arbitration_isValid;
      end
      if(((! memory_arbitration_isStuck) || memory_arbitration_removeIt))begin
        memory_arbitration_isValid <= 1'b0;
      end
      if(((! execute_arbitration_isStuck) && (! execute_arbitration_removeIt)))begin
        memory_arbitration_isValid <= execute_arbitration_isValid;
      end
      if(((! writeBack_arbitration_isStuck) || writeBack_arbitration_removeIt))begin
        writeBack_arbitration_isValid <= 1'b0;
      end
      if(((! memory_arbitration_isStuck) && (! memory_arbitration_removeIt)))begin
        writeBack_arbitration_isValid <= memory_arbitration_isValid;
      end
      case(_zz_212_)
        3'b000 : begin
          if(_zz_110_)begin
            _zz_212_ <= (3'b001);
          end
        end
        3'b001 : begin
          _zz_212_ <= (3'b010);
        end
        3'b010 : begin
          _zz_212_ <= (3'b011);
        end
        3'b011 : begin
          if((! decode_arbitration_isStuck))begin
            _zz_212_ <= (3'b100);
          end
        end
        3'b100 : begin
          _zz_212_ <= (3'b000);
        end
        default : begin
        end
      endcase
      case(execute_CsrPlugin_csrAddress)
        12'b001100000000 : begin
          if(execute_CsrPlugin_writeEnable)begin
            CsrPlugin_mstatus_MPP <= execute_CsrPlugin_writeData[12 : 11];
            CsrPlugin_mstatus_MPIE <= _zz_441_[0];
            CsrPlugin_mstatus_MIE <= _zz_442_[0];
          end
        end
        12'b001101000001 : begin
        end
        12'b001101000100 : begin
          if(execute_CsrPlugin_writeEnable)begin
            CsrPlugin_mip_MSIP <= _zz_443_[0];
          end
        end
        12'b001101000011 : begin
        end
        12'b001100000100 : begin
          if(execute_CsrPlugin_writeEnable)begin
            CsrPlugin_mie_MEIE <= _zz_444_[0];
            CsrPlugin_mie_MTIE <= _zz_445_[0];
            CsrPlugin_mie_MSIE <= _zz_446_[0];
          end
        end
        12'b001101000010 : begin
        end
        default : begin
        end
      endcase
      _zz_222_ <= _zz_224_;
      if((_zz_316_ && _zz_273_))begin
        _zz_226_ <= (! _zz_322_);
      end
      _zz_242_ <= (debug_bus_cmd_valid && debug_bus_cmd_ready);
    end
  end

  always @ (posedge clk) begin
    if(IBusCachedPlugin_iBusRsp_stages_1_output_ready)begin
      _zz_133_ <= IBusCachedPlugin_iBusRsp_stages_1_output_payload;
    end
    if((memory_DivPlugin_div_counter_value == (6'b100000)))begin
      memory_DivPlugin_div_done <= 1'b1;
    end
    if((! memory_arbitration_isStuck))begin
      memory_DivPlugin_div_done <= 1'b0;
    end
    if(_zz_344_)begin
      if(_zz_345_)begin
        memory_DivPlugin_rs1[31 : 0] <= _zz_417_[31:0];
        memory_DivPlugin_accumulator[31 : 0] <= ((! _zz_173_[32]) ? _zz_418_ : _zz_419_);
        if((memory_DivPlugin_div_counter_value == (6'b100000)))begin
          memory_DivPlugin_div_result <= _zz_420_[31:0];
        end
      end
    end
    if(_zz_352_)begin
      memory_DivPlugin_accumulator <= (65'b00000000000000000000000000000000000000000000000000000000000000000);
      memory_DivPlugin_rs1 <= ((_zz_176_ ? (~ _zz_177_) : _zz_177_) + _zz_426_);
      memory_DivPlugin_rs2 <= ((_zz_175_ ? (~ execute_RS2) : execute_RS2) + _zz_428_);
      memory_DivPlugin_div_needRevert <= ((_zz_176_ ^ (_zz_175_ && (! execute_INSTRUCTION[13]))) && (! (((execute_RS2 == (32'b00000000000000000000000000000000)) && execute_IS_RS2_SIGNED) && (! execute_INSTRUCTION[13]))));
    end
    if(_zz_180_)begin
      _zz_182_ <= _zz_59_[11 : 7];
      _zz_183_ <= _zz_89_;
    end
    CsrPlugin_mcycle <= (CsrPlugin_mcycle + (64'b0000000000000000000000000000000000000000000000000000000000000001));
    if(writeBack_arbitration_isFiring)begin
      CsrPlugin_minstret <= (CsrPlugin_minstret + (64'b0000000000000000000000000000000000000000000000000000000000000001));
    end
    if(decode_exception_agregat_valid)begin
      CsrPlugin_exceptionPortCtrl_exceptionContext_code <= decode_exception_agregat_payload_code;
      CsrPlugin_exceptionPortCtrl_exceptionContext_badAddr <= decode_exception_agregat_payload_badAddr;
    end
    if(memory_exception_agregat_valid)begin
      CsrPlugin_exceptionPortCtrl_exceptionContext_code <= memory_exception_agregat_payload_code;
      CsrPlugin_exceptionPortCtrl_exceptionContext_badAddr <= memory_exception_agregat_payload_badAddr;
    end
    if(writeBack_exception_agregat_valid)begin
      CsrPlugin_exceptionPortCtrl_exceptionContext_code <= writeBack_exception_agregat_payload_code;
      CsrPlugin_exceptionPortCtrl_exceptionContext_badAddr <= writeBack_exception_agregat_payload_badAddr;
    end
    if((CsrPlugin_exception || CsrPlugin_interruptJump))begin
      case(CsrPlugin_privilege)
        2'b11 : begin
          CsrPlugin_mepc <= writeBack_PC;
        end
        default : begin
        end
      endcase
    end
    if(_zz_349_)begin
      case(CsrPlugin_targetPrivilege)
        2'b11 : begin
          CsrPlugin_mcause_interrupt <= (! CsrPlugin_hadException);
          CsrPlugin_mcause_exceptionCode <= CsrPlugin_trapCause;
          CsrPlugin_mtval <= CsrPlugin_exceptionPortCtrl_exceptionContext_badAddr;
        end
        default : begin
        end
      endcase
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_ENV_CTRL <= _zz_25_;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_ENV_CTRL <= _zz_22_;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_ENV_CTRL <= _zz_20_;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_SRC1_CTRL <= _zz_18_;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_PC <= decode_PC;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_PC <= _zz_51_;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_PC <= memory_PC;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_INSTRUCTION <= decode_INSTRUCTION;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_INSTRUCTION <= execute_INSTRUCTION;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_PREDICTION_HAD_BRANCHED2 <= decode_PREDICTION_HAD_BRANCHED2;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_MEMORY_ADDRESS_LOW <= execute_MEMORY_ADDRESS_LOW;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_MEMORY_ADDRESS_LOW <= memory_MEMORY_ADDRESS_LOW;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_IS_RS2_SIGNED <= decode_IS_RS2_SIGNED;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_ALU_CTRL <= _zz_15_;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_MUL_HH <= execute_MUL_HH;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_MUL_HH <= memory_MUL_HH;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_MUL_LH <= execute_MUL_LH;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_ALU_BITWISE_CTRL <= _zz_12_;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_BYPASSABLE_EXECUTE_STAGE <= decode_BYPASSABLE_EXECUTE_STAGE;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_CSR_READ_OPCODE <= decode_CSR_READ_OPCODE;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_MEMORY_ENABLE <= decode_MEMORY_ENABLE;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_MEMORY_ENABLE <= execute_MEMORY_ENABLE;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_MEMORY_ENABLE <= memory_MEMORY_ENABLE;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_DO_EBREAK <= decode_DO_EBREAK;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_BRANCH_DO <= execute_BRANCH_DO;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_MEMORY_WR <= decode_MEMORY_WR;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_MEMORY_WR <= execute_MEMORY_WR;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_MEMORY_WR <= memory_MEMORY_WR;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_IS_DIV <= decode_IS_DIV;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_IS_DIV <= execute_IS_DIV;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_MUL_LOW <= memory_MUL_LOW;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_MEMORY_MANAGMENT <= decode_MEMORY_MANAGMENT;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_SRC_LESS_UNSIGNED <= decode_SRC_LESS_UNSIGNED;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_BYPASSABLE_MEMORY_STAGE <= decode_BYPASSABLE_MEMORY_STAGE;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_BYPASSABLE_MEMORY_STAGE <= execute_BYPASSABLE_MEMORY_STAGE;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_REGFILE_WRITE_DATA <= _zz_38_;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_IS_RS1_SIGNED <= decode_IS_RS1_SIGNED;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_BRANCH_CTRL <= _zz_9_;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_FLUSH_ALL <= decode_FLUSH_ALL;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_FLUSH_ALL <= execute_FLUSH_ALL;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_IS_CSR <= decode_IS_CSR;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_MUL_HL <= execute_MUL_HL;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_IS_MUL <= decode_IS_MUL;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_IS_MUL <= execute_IS_MUL;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_IS_MUL <= memory_IS_MUL;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_CSR_WRITE_OPCODE <= decode_CSR_WRITE_OPCODE;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_SRC_USE_SUB_LESS <= decode_SRC_USE_SUB_LESS;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_SHIFT_CTRL <= _zz_7_;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_SHIFT_CTRL <= _zz_4_;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_SHIFT_RIGHT <= execute_SHIFT_RIGHT;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_REGFILE_WRITE_VALID <= decode_REGFILE_WRITE_VALID;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_REGFILE_WRITE_VALID <= execute_REGFILE_WRITE_VALID;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_REGFILE_WRITE_VALID <= memory_REGFILE_WRITE_VALID;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_RS1 <= decode_RS1;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_RS2 <= decode_RS2;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_FORMAL_PC_NEXT <= _zz_95_;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_FORMAL_PC_NEXT <= execute_FORMAL_PC_NEXT;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_FORMAL_PC_NEXT <= _zz_94_;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_MUL_LL <= execute_MUL_LL;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_BRANCH_CALC <= execute_BRANCH_CALC;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_SRC2_CTRL <= _zz_2_;
    end
    case(execute_CsrPlugin_csrAddress)
      12'b001100000000 : begin
      end
      12'b001101000001 : begin
        if(execute_CsrPlugin_writeEnable)begin
          CsrPlugin_mepc <= execute_CsrPlugin_writeData[31 : 0];
        end
      end
      12'b001101000100 : begin
      end
      12'b001101000011 : begin
      end
      12'b001100000100 : begin
      end
      12'b001101000010 : begin
      end
      12'b001100000101 : begin   // bard0: mtvec (0x305) write
        if(execute_CsrPlugin_writeEnable)begin
          CsrPlugin_mtvec_base <= execute_CsrPlugin_writeData[31 : 2];
        end
      end
      default : begin
      end
    endcase
  end

  always @ (posedge clk) begin
    DebugPlugin_firstCycle <= 1'b0;
    if(debug_bus_cmd_ready)begin
      DebugPlugin_firstCycle <= 1'b1;
    end
    DebugPlugin_secondCycle <= DebugPlugin_firstCycle;
    DebugPlugin_isPipActive <= (((decode_arbitration_isValid || execute_arbitration_isValid) || memory_arbitration_isValid) || writeBack_arbitration_isValid);
    DebugPlugin_isPipActive_regNext <= DebugPlugin_isPipActive;
    if(writeBack_arbitration_isValid)begin
      DebugPlugin_busReadDataReg <= _zz_89_;
    end
    _zz_190_ <= debug_bus_cmd_payload_address[2];
    if(_zz_346_)begin
      DebugPlugin_busReadDataReg <= execute_PC;
    end
    DebugPlugin_resetIt_regNext <= DebugPlugin_resetIt;
  end

  always @ (posedge clk or posedge debugReset) begin
    if (debugReset) begin
      DebugPlugin_resetIt <= 1'b0;
      DebugPlugin_haltIt <= 1'b0;
      DebugPlugin_stepIt <= 1'b0;
      DebugPlugin_haltedByBreak <= 1'b0;
    end else begin
      if(debug_bus_cmd_valid)begin
        case(_zz_353_)
          6'b000000 : begin
            if(debug_bus_cmd_payload_wr)begin
              DebugPlugin_stepIt <= debug_bus_cmd_payload_data[4];
              if(debug_bus_cmd_payload_data[16])begin
                DebugPlugin_resetIt <= 1'b1;
              end
              if(debug_bus_cmd_payload_data[24])begin
                DebugPlugin_resetIt <= 1'b0;
              end
              if(debug_bus_cmd_payload_data[17])begin
                DebugPlugin_haltIt <= 1'b1;
              end
              if(debug_bus_cmd_payload_data[25])begin
                DebugPlugin_haltIt <= 1'b0;
              end
              if(debug_bus_cmd_payload_data[25])begin
                DebugPlugin_haltedByBreak <= 1'b0;
              end
            end
          end
          6'b000001 : begin
          end
          default : begin
          end
        endcase
      end
      if(_zz_346_)begin
        if(_zz_347_)begin
          DebugPlugin_haltIt <= 1'b1;
          DebugPlugin_haltedByBreak <= 1'b1;
        end
      end
      if(_zz_348_)begin
        if(decode_arbitration_isValid)begin
          DebugPlugin_haltIt <= 1'b1;
        end
      end
      if((DebugPlugin_stepIt && ({writeBack_arbitration_redoIt,{memory_arbitration_redoIt,{execute_arbitration_redoIt,decode_arbitration_redoIt}}} != (4'b0000))))begin
        DebugPlugin_haltIt <= 1'b0;
      end
    end
  end

  always @ (posedge clk) begin
    _zz_213_ <= debug_bus_cmd_payload_data;
  end

endmodule

