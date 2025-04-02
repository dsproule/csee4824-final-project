/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  pipeline.sv                                         //
//                                                                     //
//  Description :  Top-level module of the verisimple pipeline;        //
//                 This instantiates and connects the 5 stages of the  //
//                 Verisimple pipeline together.                       //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

module pipeline (
    input        clock,             // System clock
    input        reset,             // System reset
    input [3:0]  mem2proc_response, // Tag from memory about current request
    input [63:0] mem2proc_data,     // Data coming back from memory
    input [3:0]  mem2proc_tag,      // Tag from memory about current reply

    output logic [1:0]       proc2mem_command, // Command sent to memory
    output logic [`XLEN-1:0] proc2mem_addr,    // Address sent to memory
    output logic [63:0]      proc2mem_data,    // Data sent to memory
`ifndef CACHE_MODE // no longer sending size to memory
    output MEM_SIZE          proc2mem_size,    // Data size sent to memory
`endif

    // Note: these are assigned at the very bottom of the module
    output logic [3:0]       pipeline_completed_insts,
    output EXCEPTION_CODE    pipeline_error_status,
    output logic [4:0]       pipeline_commit_wr_idx,
    output logic [`XLEN-1:0] pipeline_commit_wr_data,
    output logic             pipeline_commit_wr_en,
    output logic [`XLEN-1:0] pipeline_commit_NPC,

    output logic [$bits(ROB_ENTRY)*`ROB_SZ-1:0] rob_table_out_dbg,
    output logic [$bits(MT_ENTRY)*32-1:0] mt_table_out_dbg,
    output RS_ENTRY [`RS_SZ-1:0] rs_table_dbg,
    output X_C_PACKET [`RS_SZ-1:0] X_packets_dbg,
    output CDB cdb_dbg,
    output logic [`RS_SZ-1:0] busy_dbg,
    output IF_ID_PACKET IF_ID_reg_dbg,
    output D_S_PACKET D_S_reg_dbg
);

    //////////////////////////////////////////////////
    //                                              //
    //                Pipeline Wires                //
    //                                              //
    //////////////////////////////////////////////////
    
    // IF_ID Stages
    logic take_branch;
    IF_ID_PACKET IF_ID_reg, IF_packet;
    D_S_PACKET D_S_reg, D_packet;
    logic [1:0] proc2Dmem_command, proc2Imem_command, proc2mem_command;
    logic [`XLEN-1:0] proc2Imem_addr, proc2Dmem_addr, proc2mem_addr;
    logic [`XLEN-1:0] branch_target;

    // debug outputs
    assign IF_ID_reg_dbg = IF_ID_reg;
    assign D_S_reg_dbg   = D_S_reg;

    //////////////////////////////////////////////////
    //                                              //
    //                Memory Outputs                //
    //                                              //
    //////////////////////////////////////////////////

    assign proc2Dmem_command = BUS_NONE;
    assign Dmem_req = (proc2Dmem_command != BUS_NONE);

    always_comb begin
        if (Dmem_req) begin
            proc2mem_addr    = proc2Dmem_addr;
            proc2mem_command = proc2Dmem_command;
`ifndef CACHE_MODE
            proc2mem_size    = proc2Dmem_size;  // size is never DOUBLE in project 3
`endif
        end else begin
            proc2mem_addr    = proc2Imem_addr;
            proc2mem_command = proc2Imem_command;
`ifndef CACHE_MODE
            proc2mem_size    = DOUBLE;  // size is never DOUBLE in project 3
`endif
        end
        // proc2mem_data = {32'b0, proc2Dmem_data};
    end

    //////////////////////////////////////////////////
    //                                              //
    //                  IF-Stage                    //
    //                                              //
    //////////////////////////////////////////////////

    assign take_branch   = `FALSE;        // for now
    assign branch_target = '0;            // for now

    if_stage if_stage_0(
        .clock(clock), .reset(reset), .gnt(~Dmem_req),
        .take_branch(take_branch),
        .branch_target(branch_target),
        .Imem2proc_data(mem2proc_data),
        .Imem2proc_response(mem2proc_response), .Imem2proc_tag(mem2proc_tag),

        .mem_req(Imem_req),
        .IF_packet(IF_packet),
        .proc2Imem_command(proc2Imem_command),
        .proc2Imem_addr(proc2Imem_addr)
    );

    always_ff @(posedge clock) begin
        if (reset) begin
            IF_ID_reg <= '0;
        end else begin
            IF_ID_reg <= (IF_packet.valid) ? IF_packet : '0;
        end
    end

    //////////////////////////////////////////////////
    //                                              //
    //                   D-Stage                    //
    //                                              //
    //////////////////////////////////////////////////

    d_stage d_stage_0(
        // Inputs
        .IF_ID_reg(IF_ID_reg),

        // Outputs
        .D_packet(D_packet)
    );

    always_ff @(posedge clock) begin
        if (reset) begin
            D_S_reg <= '0;
        // separated because may need a signal to stall
        end else begin
            D_S_reg <= (D_packet.valid) ? D_packet : '0;
        end
    end

    //////////////////////////////////////////////////
    //                                              //
    //               Pipeline Outputs               //
    //                                              //
    //////////////////////////////////////////////////

    // assign pipeline_completed_insts = {3'b0, pipeline_control.valid};    // commit one valid instruction
    // assign pipeline_error_status    = pipeline_control.illegal        ? ILLEGAL_INST :
    //                                   pipeline_control.halt           ? HALTED_ON_WFI :
    //                                   (mem2proc_response==4'h0 & proc2mem_command != BUS_NONE) ? LOAD_ACCESS_FAULT : 
    //                                                                     NO_ERROR;

    assign pipeline_completed_insts = {3'b0, D_S_reg.valid};    // commit one valid instruction
    assign pipeline_error_status    =  (D_S_reg.halt) ? HALTED_ON_WFI : NO_ERROR;
    // assign pipeline_commit_wr_en   = regfile_write_en;
    // assign pipeline_commit_wr_idx  = regfile_write_idx;
    // assign pipeline_commit_wr_data = regfile_write_data;
    // assign pipeline_commit_NPC     = mem_wb_reg.NPC;

endmodule // pipeline
