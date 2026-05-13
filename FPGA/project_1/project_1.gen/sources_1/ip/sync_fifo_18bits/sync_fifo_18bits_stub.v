// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2024.1 (win64) Build 5076996 Wed May 22 18:37:14 MDT 2024
// Date        : Wed May 13 22:59:16 2026
// Host        : WBC running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               g:/Project/repository/fpga-based-sdr/FPGA/project_1/project_1.gen/sources_1/ip/sync_fifo_18bits/sync_fifo_18bits_stub.v
// Design      : sync_fifo_18bits
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a35tfgg484-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "fifo_generator_v13_2_10,Vivado 2024.1" *)
module sync_fifo_18bits(clk, srst, din, wr_en, rd_en, dout, full, almost_full, 
  wr_ack, overflow, empty, almost_empty, valid, underflow, data_count)
/* synthesis syn_black_box black_box_pad_pin="srst,din[17:0],wr_en,rd_en,dout[17:0],full,almost_full,wr_ack,overflow,empty,almost_empty,valid,underflow,data_count[6:0]" */
/* synthesis syn_force_seq_prim="clk" */;
  input clk /* synthesis syn_isclock = 1 */;
  input srst;
  input [17:0]din;
  input wr_en;
  input rd_en;
  output [17:0]dout;
  output full;
  output almost_full;
  output wr_ack;
  output overflow;
  output empty;
  output almost_empty;
  output valid;
  output underflow;
  output [6:0]data_count;
endmodule
