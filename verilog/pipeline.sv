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
    output MEM_SIZE          proc2mem_size,    // Data size sent to memory

    // Note: these are assigned at the very bottom of the module
    output logic [3:0]       pipeline_completed_insts,
    output EXCEPTION_CODE    pipeline_error_status,
    output logic [4:0]       pipeline_commit_wr_idx,
    output logic [`XLEN-1:0] pipeline_commit_wr_data,
    output logic             pipeline_commit_wr_en,
    output logic [`XLEN-1:0] pipeline_commit_NPC,

    // Debug outputs
    output logic [$bits(ROB_ENTRY)*`ROB_SZ-1:0] rob_table_out_dbg,
    output logic [$bits(MT_ENTRY)*32-1:0] mt_table_out_dbg,
    output RS_ENTRY [`RS_SZ-1:0] rs_table_dbg,
    
    output X_C_PACKET [`RS_SZ-1:0] X_C_regs_dbg,
    output S_X_PACKET [`RS_SZ-1:0] S_X_regs_dbg,
    output IF_ID_PACKET IF_ID_reg_dbg,
    output D_S_PACKET D_S_reg_dbg,
    output CDB cdb_dbg,

    output logic [`RS_SZ-1:0] busy_dbg,
    output [`RS_SZ-1:0] FU_ready_dbg, FU_req_dbg, gnt_dbg,

    output ROB_T rob_head_dbg, rob_tail_dbg,
    output logic rob_retire_dbg,
    output PPLN_CTRL rob_pipeline_control_dbg,
    output ROB_T retire_T_wire_dbg 
);

    //////////////////////////////////////////////////
    //                                              //
    //                Pipeline Wires                //
    //                                              //
    //////////////////////////////////////////////////
    
    // Enable signals
    logic IF_enable, D_enable, IF_stall;

    // IF_ID Stages
    logic take_branch;
    IF_ID_PACKET IF_ID_reg, IF_packet;
    D_S_PACKET D_S_reg, D_packet;
    logic [1:0] proc2Dmem_command, proc2Imem_command;
    logic [`XLEN-1:0] proc2Imem_addr;
    logic [`XLEN-1:0] branch_target, branch_pred_target;

    // Map table outputs
    MT_ENTRY T1_wire, T2_wire;
    logic [$bits(MT_ENTRY)*32-1:0] mt_table_out;

    // RS outputs
    logic rs_stall;
    logic [`XLEN-1:0] V1_rs, V2_rs;
    RS_ENTRY [`RS_SZ-1:0] rs_table_out;
    logic [`RS_SZ-1:0] busy;

    // X stage
    logic [`RS_SZ:0] fu_idx, S_idx, X_idx, req_idx;    
    S_X_PACKET [`RS_SZ-1:0] S_packets, S_X_regs;
    X_C_PACKET [`RS_SZ-1:0] X_packets, X_C_regs;
    MEM_SIZE proc2Dmem_size;
    logic [`XLEN-1:0] proc2Dmem_addr [1:0];
    logic wr_mem, rd_mem;

    // ROB outputs
    PPLN_CTRL pipeline_control;
    logic rob_full, rob_empty, retire;
    logic [`XLEN-1:0] V1_rob, V2_rob, rob_write_data, V1_rob_final, V2_rob_final;
    logic [$bits(ROB_ENTRY)*`ROB_SZ-1:0] rob_table_out;

    // Regfile inputs/outputs
    logic regfile_write_en;
    logic [`XLEN-1:0] V1_regfile, V2_regfile, regfile_write_data;
    logic [4:0] regfile_write_idx;

    // Commit Stage
    logic [`RS_SZ:0] gnt_idx, cdb_idx;
    logic [`RS_SZ-1:0] gnt, FU_req, FU_ready;
    logic cdb_valid;
    CDB cdb;

    logic [4:0] retire_r_wire;
    ROB_T rob_T_wire, retire_T_wire;
    ROB_T rob_head, rob_tail;

    // Caches 
    logic [`XLEN-1:0] proc2Icache_addr;
    logic [63:0] Icache_data_out;
    logic Icache_valid_out;
    
    logic [`XLEN-1:0] cache2Dmem_addr;
    logic [1:0] cache2Dmem_command;
    logic Dcache_valid_out;
    logic [63:0] proc2Dcache_data, cache2Dmem_data, Dcache_data_out;
    logic wr_proc, wr_valid;

    // debug outputs
    assign IF_ID_reg_dbg     = IF_ID_reg;
    assign D_S_reg_dbg       = D_S_reg;
    assign mt_table_out_dbg  = mt_table_out;
    assign rs_table_dbg      = rs_table_out;
    assign busy_dbg          = busy;
    assign FU_ready_dbg      = FU_ready;
    assign FU_req_dbg        = FU_req;
    assign gnt_dbg           = gnt;
    assign S_X_regs_dbg      = S_X_regs;
    assign X_C_regs_dbg      = X_C_regs;
    assign cdb_dbg           = cdb;
    assign rob_table_out_dbg = rob_table_out;
    assign rob_head_dbg      = rob_head;
    assign rob_tail_dbg      = rob_tail;
    
    assign rob_retire_dbg    = retire; 
    assign retire_T_wire_dbg = retire_T_wire;

    assign rob_pipeline_control_dbg = pipeline_control;

    //////////////////////////////////////////////////
    //                                              //
    //                Memory Outputs                //
    //                                              //
    //////////////////////////////////////////////////

    assign rd_mem = S_X_regs[2].valid;
    assign wr_mem = S_X_regs[3].valid;
    assign Dmem_req = (wr_mem | rd_mem);

    // for all memory vectors, ind0 -> wr and ind1 -> rd

    always_comb begin
        if (Dmem_req) begin
            proc2mem_addr        = cache2Dmem_addr;
            proc2mem_command     = cache2Dmem_command;
        end else begin
            proc2mem_addr        = proc2Imem_addr;
            proc2mem_command     = proc2Imem_command;
        end
        proc2mem_data = cache2Dmem_data;
    end

    //////////////////////////////////////////////////
    //                                              //
    //                  IF-Stage                    //
    //                                              //
    //////////////////////////////////////////////////

    assign take_branch   = pipeline_control.flush;
    assign branch_target = pipeline_control.branch_addr; 

    icache icache_0 (
        .clock(clock), .reset(reset | take_branch),
        .Imem2proc_response((Dmem_req) ? '0 : mem2proc_response), // Should be zero unless there is a response
        .Imem2proc_data(mem2proc_data),
        .Imem2proc_tag(mem2proc_tag),

        // From fetch stage
        .proc2Icache_addr(proc2Icache_addr),

        // To memory
        .proc2Imem_command(proc2Imem_command),
        .proc2Imem_addr(proc2Imem_addr),

        // To fetch stage
        .Icache_data_out(Icache_data_out), // Data is mem[proc2Icache_addr]
        .Icache_valid_out(Icache_valid_out) // When valid is high
    );

    if_stage if_stage_0(
        .clock(clock), .reset(reset), 
        .if_valid(~Dmem_req & Icache_valid_out),
        .pipe_stall(rs_stall),
        .take_branch(take_branch | branch_pred),
        .branch_target((branch_pred) ? branch_pred_target : branch_target),
        .Imem2proc_data(Icache_data_out),

        .if_packet(IF_packet),
        .proc2Imem_addr(proc2Icache_addr)
    );

    two_bit_pred branch_pred_0(
        .clock(clock), .reset(reset), .en(D_packet.cond_branch & ~take_branch & D_packet.valid), 
        .D_packet(D_packet),

        .branch_target(branch_pred_target),
        .branch_pred(branch_pred)
    );

    assign IF_enable = 1'b1 & ~rs_stall;
    always_ff @(posedge clock) begin
        if (reset | take_branch | branch_pred) begin
            IF_ID_reg <= '0;
        end else if (IF_enable) begin
            IF_ID_reg <= IF_packet;
        end
    end

    //////////////////////////////////////////////////
    //                                              //
    //                   D-Stage                    //
    //                                              //
    //////////////////////////////////////////////////

    logic alu_fu, mult_fu;
    d_stage d_stage_0(
        // Inputs
        .IF_ID_reg(IF_ID_reg),
        .alu_fu(alu_fu),
        .mult_fu(mult_fu),

        // Outputs
        .D_packet(D_packet)
    );

    assign D_enable = 1'b1 & ~rs_stall;         // if rs_stalls, means inst was not processed
    always_ff @(posedge clock) begin
        if (reset | take_branch) begin
            D_S_reg <= '0;
            alu_fu <= '0;
            mult_fu <= '0;
        // separated because may need a signal to stall
        end else if (D_enable) begin
            D_S_reg <= D_packet;
            D_S_reg.branch_pred <= branch_pred;

            if (D_packet.valid & (D_packet.rs_idx == 0 || D_packet.rs_idx == 4))
                alu_fu <= ~alu_fu;
            if (D_packet.valid & (D_packet.rs_idx == 1 || D_packet.rs_idx == 5))
                mult_fu <= ~mult_fu;
        end

    end

    //////////////////////////////////////////////////
    //                                              //
    //              RS/MT/ROB/Regs                  //
    //                                              //
    //////////////////////////////////////////////////

    map_table map_table_inst (
        // Inputs
        .clock(clock), .reset(reset | take_branch), .has_dest(D_S_reg.has_dest),
        .en(D_S_reg.valid & ~rs_stall), 
        .r(D_S_reg.r), .r1(D_S_reg.r1), .r2(D_S_reg.r2), 
        .retire_r(retire_r_wire), 
        .cdb(cdb), .T(rob_T_wire), .retire_T(retire_T_wire), 
        
        // Outputs
        .T1(T1_wire), .T2(T2_wire), 
        .mt_table_out(mt_table_out)
    );

    assign V1_rob_final = (retire && (retire_T_wire == T1_wire.T)) ? rob_write_data : V1_rob;
    assign V2_rob_final = (retire && (retire_T_wire == T2_wire.T)) ? rob_write_data : V2_rob;
    assign V1_rs = (T1_wire.plus == 1) ? V1_rob_final : V1_regfile;
    assign V2_rs = (T2_wire.plus == 1) ? V2_rob_final : V2_regfile;

    logic rs_idx_full;
    logic [`RS_SZ-1:0] FU_ready_no_lsq;

    assign rs_stall = ((D_S_reg.rs_idx == 2) | (D_S_reg.rs_idx == 3)) ? (busy[3:2] != 2'b00) : rs_idx_full;
    assign FU_ready_no_lsq = {FU_ready[5:4], FU_ready[3] & ~rd_mem, FU_ready[2] & ~wr_mem, FU_ready[1:0]};
    rs_stage rs_stage_inst (
        // Inputs
        .clock(clock), .reset(reset | take_branch), .alloc_en(D_S_reg.valid & ~rs_stall), 
        .cdb(cdb), .D_S_reg(D_S_reg), 
        .FU_ready(FU_ready_no_lsq),
        .T(rob_T_wire), .T1(T1_wire), .T2(T2_wire), 
        .V1(V1_rs), .V2(V2_rs), 

        // Outputs           
        .rs_idx_full(rs_idx_full),
        .S_packet(S_packets), 
        .rs_table(rs_table_out), .busy(busy)
    );

    always_ff @(posedge clock) begin
        for (fu_idx = 0; fu_idx < `RS_SZ; fu_idx++)
            if (reset | take_branch) begin
                FU_ready[fu_idx] <= `TRUE; // all FUs are available in the beginning
            end else if (FU_ready[fu_idx] & S_packets[fu_idx].valid) begin
                FU_ready[fu_idx] <= `FALSE; // FU is in used
            end else if (gnt[fu_idx]) begin
                FU_ready[fu_idx] <= `TRUE;
            end
    end
    
    rob rob_inst (
        // Inputs
        .clock(clock), .reset(reset | take_branch),
        .r(D_S_reg.r), .T1(T1_wire.T), .T2(T2_wire.T),
        .NPC(D_S_reg.PC),
        .cdb(cdb),
        .dispatch_valid(D_S_reg.valid & ~rs_stall), 
        
        // Outputs
        .T(rob_T_wire), .retire_T_out(retire_T_wire), 
        .ppln_ctrl(pipeline_control), .full(rob_full), .empty(rob_empty), 
        .retire(retire), .regfile_write_idx_out(retire_r_wire), 
        .regfile_write_data(rob_write_data), .rob_table_out(rob_table_out),
        .V1(V1_rob), .V2(V2_rob),
        .head(rob_head), .tail(rob_tail),
        .commit_NPC(pipeline_commit_NPC)
    );

    assign regfile_write_en   = retire & (pipeline_control.has_dest) & ~pipeline_control.halt;
    assign regfile_write_data = rob_write_data;
    assign regfile_write_idx  = retire_r_wire;

    regfile regfile_inst (
        // Inputs
        .clock(clock), 
        .read_idx_1(D_S_reg.r1), .read_idx_2(D_S_reg.r2), 
        .write_idx(regfile_write_idx),
        .write_en(regfile_write_en), .write_data(regfile_write_data),

        // Outputs
        .read_out_1(V1_regfile), .read_out_2(V2_regfile)
    );

    //////////////////////////////////////////////////
    //                                              //
    //                    S/X Regs                  //
    //                                              //
    //////////////////////////////////////////////////

    always_ff @(posedge clock) begin
        for (S_idx = 0; S_idx < `RS_SZ; S_idx++)
            if (reset | (gnt[S_idx] & ~S_packets[S_idx].valid)) begin
                S_X_regs[S_idx] <= 0;            
            end else if (S_packets[S_idx].valid) begin
                S_X_regs[S_idx] <= S_packets[S_idx];
            end
    end

    //////////////////////////////////////////////////
    //                                              //
    //                    X_Stage                   //
    //                                              //
    //////////////////////////////////////////////////

    func_unit_0 func_unit_00(
        // Inputs
        .S_X_reg(S_X_regs[0]), 
        
        // Outputs
        .X_packet(X_packets[0])
    );

    func_unit_1 func_unit_01(
        // Inputs
        .clock(clock), .reset(reset | take_branch), 
        .retired(gnt[1]),
        .S_X_reg(S_X_regs[1]), 

        // Outputs    
        .X_packet(X_packets[1])
    );

    dcache dache_0(
        .clock(clock), .reset(reset | take_branch),

        // From memory
        .Dmem2proc_response((Dmem_req) ? mem2proc_response : '0), .Dmem2proc_tag(mem2proc_tag),
        .Dmem2proc_data(mem2proc_data),

        // From FU stage
        .proc2Dcache_addr((wr_mem) ? proc2Dmem_addr[0] : proc2Dmem_addr[1]),
        .proc2Dcache_data(proc2Dcache_data),
        .wr_proc(wr_proc),

        // To memory
        .proc2Dmem_command(cache2Dmem_command),
        .proc2Dmem_addr(cache2Dmem_addr),
        .proc2Dmem_data(cache2Dmem_data),

        // To fetch stage
        .Dcache_data_out(Dcache_data_out),
        .Dcache_valid_out(Dcache_valid_out),
        .wr_valid(wr_valid)
    );

    assign wr_proc = wr_mem & Dcache_valid_out;

    func_unit_2 func_unit_02 (
        .clock(clock), .reset(reset | take_branch), 
        .committed(gnt[2]), .data_valid(Dcache_valid_out & rd_mem),
        .Dmem2proc_data(Dcache_data_out),
        .S_X_reg(S_X_regs[2]),

        // output logic mem_load_pend,
        .proc2Dmem_addr(proc2Dmem_addr[1]),
        .X_packet(X_packets[2])
    );

    func_unit_3 func_unit_03(
        .clock(clock), .reset(reset | take_branch), .committed(gnt[3]), .wr_valid(wr_valid & wr_mem),
        .Dmem2proc_data(Dcache_data_out),
        .S_X_reg(S_X_regs[3]),

        .proc2Dmem_addr(proc2Dmem_addr[0]),
        .proc2Dcache_data(proc2Dcache_data),
        .X_packet(X_packets[3])
    );

    func_unit_0 func_unit_04(
        // Inputs
        .S_X_reg(S_X_regs[4]), 
        
        // Outputs
        .X_packet(X_packets[4])
    );

    func_unit_1 func_unit_05(
        // Inputs
        .clock(clock), .reset(reset | take_branch), 
        .retired(gnt[5]),
        .S_X_reg(S_X_regs[5]), 

        // Outputs    
        .X_packet(X_packets[5])
    );

    // X_C regs
    always_ff @(posedge clock) begin
        for (X_idx = 0; X_idx < `RS_SZ; X_idx++)
            if (reset | gnt[X_idx]) begin
                X_C_regs[X_idx] <= '0;
                FU_req[X_idx]   <= `FALSE;
            end else if (X_packets[X_idx].valid) begin
                X_C_regs[X_idx] <= X_packets[X_idx];
                FU_req[X_idx]   <= `TRUE;
            end
    end

    //////////////////////////////////////////////////
    //                                              //
    //               Commit stage                   //
    //                                              //
    //////////////////////////////////////////////////

    // CDB stage
    always_comb begin
        // turn the arbiter signal to idx
        for (gnt_idx = 0; gnt_idx < `RS_SZ; gnt_idx++)
            if (gnt[gnt_idx])
                cdb_idx = gnt_idx;
        
        // pass values along
        if (cdb_valid) begin
            cdb.T = X_C_regs[cdb_idx].T;
            cdb.V = X_C_regs[cdb_idx].result;
        end else begin
            cdb.T = '0;
            cdb.V = '0;
        end

        cdb.ppln_ctrl = X_C_regs[cdb_idx].ppln_ctrl;
        cdb.valid = cdb_valid;
    end

    rps arb (
        .clock(clock), .reset(reset | take_branch), 
        .req(FU_req), 
        .en(1'b1), 
        
        .gnt(gnt), .req_up(cdb_valid)
    );

    //////////////////////////////////////////////////
    //                                              //
    //               Pipeline Outputs               //
    //                                              //
    //////////////////////////////////////////////////

    assign pipeline_completed_insts = {3'b0, retire};    // commit one valid instruction
    assign pipeline_error_status    = pipeline_control.illegal        ? ILLEGAL_INST :
                                      pipeline_control.halt           ? HALTED_ON_WFI :
                                      (mem2proc_response==4'h0 & (proc2mem_command != BUS_NONE)) ? LOAD_ACCESS_FAULT : NO_ERROR;
    assign pipeline_commit_wr_en   = regfile_write_en;
    assign pipeline_commit_wr_idx  = regfile_write_idx;
    assign pipeline_commit_wr_data = regfile_write_data; 

endmodule // pipeline
