 /*                                                                      
 Copyright 2018-2020 Nuclei System Technology, Inc.                
                                                                         
 Licensed under the Apache License, Version 2.0 (the "License");         
 you may not use this file except in compliance with the License.        
 You may obtain a copy of the License at                                 
                                                                         
     http://www.apache.org/licenses/LICENSE-2.0                          
                                                                         
  Unless required by applicable law or agreed to in writing, software    
 distributed under the License is distributed on an "AS IS" BASIS,       
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and     
 limitations under the License.                                          
 */                                                                      
                                                                         
                                                                         
                                                                         
//=====================================================================
//
// Designer   : Bob Hu
//
// Description:
//  The Dispatch module to dispatch instructions to different functional units
//
// ====================================================================
`include "e203_defines.v"

module e203_exu_disp(
  input  wfi_halt_exu_req,  //接收一个来自交付模块的暂停请求
  output wfi_halt_exu_ack,  //确认交付模块发来的数据已经接受无误

  input  oitf_empty, //数据相关性判断 高电平时表示没有长指令在执行
  input  amo_wait,//来自exu的lsuagu，不知道干麼的  如果为1，是不是表示有指令没处理完？？？？？？？？？？？？？？？？？？？
  //////////////////////////////////////////////////////////////
  // The operands and decode info from dispatch
  input  disp_i_valid, // Handshake valid //ifetch向disp发送读写反馈请求信号 说明disp读取了流水线寄存器中的指令
  output disp_i_ready, // Handshake ready  //disp向ifetch返回读写反馈接受信号 disp读取了指令并且执行完了

  // The operand 1/2 read-enable signals and indexes
  input  disp_i_rs1x0,  //该指令原操作数1的寄存器索引为x0 来自decode
  input  disp_i_rs2x0,  //该指令原操作数2的寄存器索引为x0 来自decode
  input  disp_i_rs1en,  //需要读取原操作数1 来自decode
  input  disp_i_rs2en,  //需要读取原操作数2 来自decode
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rs1idx,//该指令原操作数1的寄存器索引 来自ifetch 也可以来自decode，只是decode的索引悬空了
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rs2idx,//该指令原操作数2的寄存器索引 来自ifetch
  input  [`E203_XLEN-1:0] disp_i_rs1, //来自通用寄存器的结果
  input  [`E203_XLEN-1:0] disp_i_rs2, //来自通用寄存器的结果
  input  disp_i_rdwen, //来自decode，指令需要写结果操作数到寄存器  应该也可以来自minidecode，只是minidecode的被悬空了
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rdidx,  //来自decode，该指令结果寄存器索引
  input  [`E203_DECINFO_WIDTH-1:0]  disp_i_info,    //来自decode，该指令信息info bus
  input  [`E203_XLEN-1:0] disp_i_imm,  //来自decode，该指令使用的立即数
  input  [`E203_PC_SIZE-1:0] disp_i_pc,  //来自pc寄存器
  input  disp_i_misalgn,  //始终是0
  input  disp_i_buserr ,  //来自取址后的寄存器
  input  disp_i_ilegl  ,  //来自取址后的寄存器


  //////////////////////////////////////////////////////////////
  // Dispatch to ALU
  output disp_o_alu_valid, //disp向alu发送读写请求信号
  input  disp_o_alu_ready,  //alu向disp返回的读写接受信号

  input  disp_o_alu_longpipe, //指令到alu处理完之后发现他是一条长指令，就需要递交到oitf

  output [`E203_XLEN-1:0] disp_o_alu_rs1, //发送给alu，rs1的值
  output [`E203_XLEN-1:0] disp_o_alu_rs2, //发送给alu，rs2的值
  output disp_o_alu_rdwen,        //从译码就知道指令需要写结果操作数到寄存器，发送给alu
  output [`E203_RFIDX_WIDTH-1:0] disp_o_alu_rdidx,    //从译码就知道写回结果寄存器的索引是多少，发送给alu
  output [`E203_DECINFO_WIDTH-1:0]  disp_o_alu_info,    //从译码得出的指令信息，发送给alu
  output [`E203_XLEN-1:0] disp_o_alu_imm,   //指令使用的立即数的值，发送给alu
  output [`E203_PC_SIZE-1:0] disp_o_alu_pc, //指令的pc值，发送给alu
  output [`E203_ITAG_WIDTH-1:0] disp_o_alu_itag,  //oitf的写地址
  output disp_o_alu_misalgn,  //指令取址时发生了非对齐错误，发送给alu
  output disp_o_alu_buserr ,  //指令访问存储器时发生错误，发送给alu
  output disp_o_alu_ilegl  ,  //指令译码后发现是一条错误指令，发送给alu

  //////////////////////////////////////////////////////////////
  // Dispatch to OITF
  input  oitfrd_match_disprs1,  // 派遣指令rs1和任意一个oitf中的rd有冲突标记
  input  oitfrd_match_disprs2,  // 派遣指令rs2和任意一个oitf中的rd有冲突标记
  input  oitfrd_match_disprs3,// 派遣指令rs3和任意一个oitf中的rd有冲突标记
  input  oitfrd_match_disprd, // 派遣指令rd和任意一个oitf中的rd有冲突标记
  input  [`E203_ITAG_WIDTH-1:0] disp_oitf_ptr , // oitf fifo的写地址

  output disp_oitf_ena,   //派遣一个长指令的使能信号，需要写入oitf
  input  disp_oitf_ready,//oitf 非满，可以进行派遣，即可以允许指令递交oitf

  output disp_oitf_rs1fpu, // 派遣指令操作数要读取第1个浮点通用寄存器组 总是0
  output disp_oitf_rs2fpu, // 派遣指令操作数要读取第2个浮点通用寄存器组 总是0
  output disp_oitf_rs3fpu, // 派遣指令操作数要读取第3个浮点通用寄存器组 总是0
  output disp_oitf_rdfpu , // 派遣指令操作数要写回浮点通用寄存器组 总是0

  output disp_oitf_rs1en , // 派遣指令要读取rs1操作数寄存器
  output disp_oitf_rs2en , // 派遣指令要读取rs2操作数寄存器
  output disp_oitf_rs3en , // 派遣指令要读取rs3操作数寄存器 总是0 只有浮点计算才能用到
  output disp_oitf_rdwen ,  // 派遣指令是要写回rd操作数寄存器

  output [`E203_RFIDX_WIDTH-1:0] disp_oitf_rs1idx, //派遣指令rs1操作数的索引
  output [`E203_RFIDX_WIDTH-1:0] disp_oitf_rs2idx, //派遣指令rs2操作数的索引
  output [`E203_RFIDX_WIDTH-1:0] disp_oitf_rs3idx, //派遣指令rs3操作数的索引
  output [`E203_RFIDX_WIDTH-1:0] disp_oitf_rdidx , //派遣指令rd操作数的索引

  output [`E203_PC_SIZE-1:0] disp_oitf_pc ,  //派遣指令的pc值，来自pc寄存器

  
  input  clk,
  input  rst_n
  );


  wire [`E203_DECINFO_GRP_WIDTH-1:0] disp_i_info_grp  = disp_i_info [`E203_DECINFO_GRP]; //记录info bus的后3位disp_i_info [2：0]

  // Based on current 2 pipe stage implementation, the 2nd stage need to have all instruction
  //   to be commited via ALU interface, so every instruction need to be dispatched to ALU,
  //   regardless it is long pipe or not, and inside ALU it will issue instructions to different
  //   other longpipes
  //wire disp_alu  = (disp_i_info_grp == `E203_DECINFO_GRP_ALU) 
  //               | (disp_i_info_grp == `E203_DECINFO_GRP_BJP) 
  //               | (disp_i_info_grp == `E203_DECINFO_GRP_CSR) 
  //              `ifdef E203_SUPPORT_SHARE_MULDIV //{
  //               | (disp_i_info_grp == `E203_DECINFO_GRP_MULDIV) 
  //              `endif//E203_SUPPORT_SHARE_MULDIV}
  //               | (disp_i_info_grp == `E203_DECINFO_GRP_AGU);
/*
  `define E203_DECINFO_GRP_WIDTH    3
  `define E203_DECINFO_GRP_ALU      `E203_DECINFO_GRP_WIDTH'd0
  `define E203_DECINFO_GRP_AGU      `E203_DECINFO_GRP_WIDTH'd1
  `define E203_DECINFO_GRP_BJP      `E203_DECINFO_GRP_WIDTH'd2
  `define E203_DECINFO_GRP_CSR      `E203_DECINFO_GRP_WIDTH'd3
  `define E203_DECINFO_GRP_MULDIV   `E203_DECINFO_GRP_WIDTH'd4
  `define E203_DECINFO_GRP_NICE      `E203_DECINFO_GRP_WIDTH'd5
  `define E203_DECINFO_GRP_FPU      `E203_DECINFO_GRP_WIDTH'd6

  `define E203_DECINFO_GRP_FPU_WIDTH    2
  `define E203_DECINFO_GRP_FPU_FLSU     `E203_DECINFO_GRP_FPU_WIDTH'd0
  `define E203_DECINFO_GRP_FPU_FMAC     `E203_DECINFO_GRP_FPU_WIDTH'd1
  `define E203_DECINFO_GRP_FPU_FDIV     `E203_DECINFO_GRP_FPU_WIDTH'd2
  `define E203_DECINFO_GRP_FPU_FMIS     `E203_DECINFO_GRP_FPU_WIDTH'd3*/

  wire disp_csr = (disp_i_info_grp == `E203_DECINFO_GRP_CSR); //如果info bus的后三位 == 3 递交一条csr指令？？？？？？

  wire disp_alu_longp_prdt = (disp_i_info_grp == `E203_DECINFO_GRP_AGU)  //如果info bus的后三位 == 1 递交一条长指令？？？？？
                             ;

  wire disp_alu_longp_real = disp_o_alu_longpipe;//暂时不知道是什么信号，可能是提示这是一条长指令？？？？？？？？？？？？？？？？

  // Both fence and fencei need to make sure all outstanding instruction have been completed
  wire disp_fence_fencei   = (disp_i_info_grp == `E203_DECINFO_GRP_BJP) &               
                               ( disp_i_info [`E203_DECINFO_BJP_FENCE] | disp_i_info [`E203_DECINFO_BJP_FENCEI]);   //递交一条fence-fencei指令？？？？

  // Since any instruction will need to be dispatched to ALU, we dont need the gate here
  //   wire   disp_i_ready_pos = disp_alu & disp_o_alu_ready;
  //   assign disp_o_alu_valid = disp_alu & disp_i_valid_pos; 
  wire disp_i_valid_pos;  //向alu派遣指令
  wire   disp_i_ready_pos = disp_o_alu_ready;   //alu处理完了disp派遣的指令返回一个指示信号
  assign disp_o_alu_valid = disp_i_valid_pos;   //表示要向alu派遣指令
  
  //////////////////////////////////////////////////////////////
  // The Dispatch Scheme Introduction for two-pipeline stage
  //  #1: The instruction after dispatched must have already have operand fetched, so
  //      there is no any WAR dependency happened.
  //  #2: The ALU-instruction are dispatched and executed in-order inside ALU, so
  //      there is no any WAW dependency happened among ALU instructions.
  //      Note: LSU since its AGU is handled inside ALU, so it is treated as a ALU instruction
  //  #3: The non-ALU-instruction are all tracked by OITF, and must be write-back in-order, so 
  //      it is like ALU in-ordered. So there is no any WAW dependency happened among
  //      non-ALU instructions.
  //  Then what dependency will we have?
  //  * RAW: This is the real dependency
  //  * WAW: The WAW between ALU an non-ALU instructions
  //
  //  So #1, The dispatching ALU instruction can not proceed and must be stalled when
  //      ** RAW: The ALU reading operands have data dependency with OITF entries
  //         *** Note: since it is 2 pipeline stage, any last ALU instruction have already
  //             write-back into the regfile. So there is no chance for ALU instr to depend 
  //             on last ALU instructions as RAW. 
  //             Note: if it is 3 pipeline stages, then we also need to consider the ALU-to-ALU 
  //                   RAW dependency.
  //      ** WAW: The ALU writing result have no any data dependency with OITF entries
  //           Note: Since the ALU instruction handled by ALU may surpass non-ALU OITF instructions
  //                 so we must check this.
  //  And #2, The dispatching non-ALU instruction can not proceed and must be stalled when
  //      ** RAW: The non-ALU reading operands have data dependency with OITF entries
  //         *** Note: since it is 2 pipeline stage, any last ALU instruction have already
  //             write-back into the regfile. So there is no chance for non-ALU instr to depend 
  //             on last ALU instructions as RAW. 
  //             Note: if it is 3 pipeline stages, then we also need to consider the non-ALU-to-ALU 
  //                   RAW dependency.

  wire raw_dep =  ((oitfrd_match_disprs1) |         //根据来自oitf的数据判断数据相关性
                   (oitfrd_match_disprs2) |
                   (oitfrd_match_disprs3)); 
               // Only check the longp instructions (non-ALU) for WAW, here if we 
               //   use the precise version (disp_alu_longp_real), it will hurt timing very much, but
               //   if we use imprecise version of disp_alu_longp_prdt, it is kind of tricky and in 
               //   some corner case. For example, the AGU (treated as longp) will actually not dispatch
               //   to longp but just directly commited, then it become a normal ALU instruction, and should
               //   check the WAW dependency, but this only happened when it is AMO or unaligned-uop, so
               //   ideally we dont need to worry about it, because
               //     * We dont support AMO in 2 stage CPU here
               //     * We dont support Unalign load-store in 2 stage CPU here, which 
               //         will be triggered as exception, so will not really write-back
               //         into regfile
               //     * But it depends on some assumption, so it is still risky if in the future something changed.
               // Nevertheless: using this condition only waiver the longpipe WAW case, that is, two
               //   longp instruction write-back same reg back2back. Is it possible or is it common? 
               //   after we checking the benmark result we found if we remove this complexity here 
               //   it just does not change any benchmark number, so just remove that condition out. Means
               //   all of the instructions will check waw_dep
  //wire alu_waw_dep = (~disp_alu_longp_prdt) & (oitfrd_match_disprd & disp_i_rdwen); 
  wire waw_dep = (oitfrd_match_disprd); //根据来自oitf的数据判断数据相关性

  wire dep = raw_dep | waw_dep;  //其中一个有相关性就说明具有相关性

  // The WFI halt exu ack will be asserted when the OITF is empty
  //    and also there is no AMO oustanding uops 
  assign wfi_halt_exu_ack = oitf_empty & (~amo_wait);  //确认来自交付模块的信息已经接受无误

  wire disp_condition =                     //满足派遣的条件就可以进行派遣
                 // To be more conservtive, any accessing CSR instruction need to wait the oitf to be empty.
                 // Theoretically speaking, it should also flush pipeline after the CSR have been updated
                 //  to make sure the subsequent instruction get correct CSR values, but in our 2-pipeline stage
                 //  implementation, CSR is updated after EXU stage, and subsequent are all executed at EXU stage,
                 //  no chance to got wrong CSR values, so we dont need to worry about this.
                 (disp_csr ? oitf_empty : 1'b1)
                 // To handle the Fence: just stall dispatch until the OITF is empty
               & (disp_fence_fencei ? oitf_empty : 1'b1)
                 // If it was a WFI instruction commited halt req, then it will stall the disaptch
               & (~wfi_halt_exu_req)   
                 // No dependency
               & (~dep)   
               ////  // If dispatch to ALU as long pipeline, then must check
               ////  //   the OITF is ready
               //// & ((disp_alu & disp_o_alu_longpipe) ? disp_oitf_ready : 1'b1);
               // To cut the critical timing  path from longpipe signal
               // we always assume the LSU will need oitf ready
               & (disp_alu_longp_prdt ? disp_oitf_ready : 1'b1);

  assign disp_i_valid_pos = disp_condition & disp_i_valid;    //说明从流水线寄存器取来的指令现在满足派遣的条件，要给alu派遣指令
  assign disp_i_ready     = disp_condition & disp_i_ready_pos; //说明从流水线寄存器发来的指令已经在alu执行完了，就给ifetch返回一个读写反馈请求


  wire [`E203_XLEN-1:0] disp_i_rs1_msked = disp_i_rs1 & {`E203_XLEN{~disp_i_rs1x0}};//如果译码的结果是0那就取0，如果是1那就取通用寄存器给的结果
  wire [`E203_XLEN-1:0] disp_i_rs2_msked = disp_i_rs2 & {`E203_XLEN{~disp_i_rs2x0}};//如果译码的结果是0那就取0，如果是1那就取通用寄存器给的结
    // Since we always dispatch any instructions into ALU, so we dont need to gate ops here
  //assign disp_o_alu_rs1   = {`E203_XLEN{disp_alu}} & disp_i_rs1_msked;
  //assign disp_o_alu_rs2   = {`E203_XLEN{disp_alu}} & disp_i_rs2_msked;
  //assign disp_o_alu_rdwen = disp_alu & disp_i_rdwen;
  //assign disp_o_alu_rdidx = {`E203_RFIDX_WIDTH{disp_alu}} & disp_i_rdidx;
  //assign disp_o_alu_info  = {`E203_DECINFO_WIDTH{disp_alu}} & disp_i_info;  
  assign disp_o_alu_rs1   = disp_i_rs1_msked; //发送给alu，rs1的值
  assign disp_o_alu_rs2   = disp_i_rs2_msked; //发送给alu，rs2的值
  assign disp_o_alu_rdwen = disp_i_rdwen; //发送给alu，指令需要写回结果寄存器
  assign disp_o_alu_rdidx = disp_i_rdidx; //发送给alu，指令需要结果寄存器的索引
  assign disp_o_alu_info  = disp_i_info;    //发送给alu，从译码得出的指令信息，发送给alu
  
    // Why we use precise version of disp_longp here, because
    //   only when it is really dispatched as long pipe then allocate the OITF
  assign disp_oitf_ena = disp_o_alu_valid & disp_o_alu_ready & disp_alu_longp_real;   //指令到alu处理完发现是一条长指令，派遣一个长指令的使能信号，需要写入oitf

  assign disp_o_alu_imm  = disp_i_imm;  //来自minidecode，指令使用的立即数的值
  assign disp_o_alu_pc   = disp_i_pc;//指令的pc值，发送给alu
  assign disp_o_alu_itag = disp_oitf_ptr; // oitf fifo的写地址
  assign disp_o_alu_misalgn= disp_i_misalgn;  //来自decode，取址非对齐异常
  assign disp_o_alu_buserr = disp_i_buserr ;  //来自decode，取址访问存储器异常
  assign disp_o_alu_ilegl  = disp_i_ilegl  ;  //来自decode，该指令是非法指令



  `ifndef E203_HAS_FPU//{
  wire disp_i_fpu       = 1'b0;
  wire disp_i_fpu_rs1en = 1'b0;
  wire disp_i_fpu_rs2en = 1'b0;
  wire disp_i_fpu_rs3en = 1'b0;
  wire disp_i_fpu_rdwen = 1'b0;
  wire [`E203_RFIDX_WIDTH-1:0] disp_i_fpu_rs1idx = `E203_RFIDX_WIDTH'b0;
  wire [`E203_RFIDX_WIDTH-1:0] disp_i_fpu_rs2idx = `E203_RFIDX_WIDTH'b0;
  wire [`E203_RFIDX_WIDTH-1:0] disp_i_fpu_rs3idx = `E203_RFIDX_WIDTH'b0;
  wire [`E203_RFIDX_WIDTH-1:0] disp_i_fpu_rdidx  = `E203_RFIDX_WIDTH'b0;
  wire disp_i_fpu_rs1fpu = 1'b0;
  wire disp_i_fpu_rs2fpu = 1'b0;
  wire disp_i_fpu_rs3fpu = 1'b0;
  wire disp_i_fpu_rdfpu  = 1'b0;
  `endif//}
  assign disp_oitf_rs1fpu = disp_i_fpu ? (disp_i_fpu_rs1en & disp_i_fpu_rs1fpu) : 1'b0;
  assign disp_oitf_rs2fpu = disp_i_fpu ? (disp_i_fpu_rs2en & disp_i_fpu_rs2fpu) : 1'b0;
  assign disp_oitf_rs3fpu = disp_i_fpu ? (disp_i_fpu_rs3en & disp_i_fpu_rs3fpu) : 1'b0;
  assign disp_oitf_rdfpu  = disp_i_fpu ? (disp_i_fpu_rdwen & disp_i_fpu_rdfpu ) : 1'b0;

  assign disp_oitf_rs1en  = disp_i_fpu ? disp_i_fpu_rs1en : disp_i_rs1en; //需要读取原操作数1，来自decode
  assign disp_oitf_rs2en  = disp_i_fpu ? disp_i_fpu_rs2en : disp_i_rs2en; //需要读取原操作数1，来自decode
  assign disp_oitf_rs3en  = disp_i_fpu ? disp_i_fpu_rs3en : 1'b0;         //不需要读取原操作数3
  assign disp_oitf_rdwen  = disp_i_fpu ? disp_i_fpu_rdwen : disp_i_rdwen; //指令需要写结果操作数到寄存器

  assign disp_oitf_rs1idx = disp_i_fpu ? disp_i_fpu_rs1idx : disp_i_rs1idx;//该指令原操作数1的寄存器索引 来自ifu的ifetch
  assign disp_oitf_rs2idx = disp_i_fpu ? disp_i_fpu_rs2idx : disp_i_rs2idx;//该指令原操作数2的寄存器索引 来自ifu的ifetch
  assign disp_oitf_rs3idx = disp_i_fpu ? disp_i_fpu_rs3idx : `E203_RFIDX_WIDTH'b0;  //0
  assign disp_oitf_rdidx  = disp_i_fpu ? disp_i_fpu_rdidx  : disp_i_rdidx; //来自decode，该指令结果寄存器索引

  assign disp_oitf_pc  = disp_i_pc;  //来自decode，该指令的pc值

endmodule                                      
                                               
                                               
                                               
