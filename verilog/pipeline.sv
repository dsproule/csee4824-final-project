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
    logic [`XLEN-1:0] branch_target;

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
    logic [`XLEN-1:0] proc2Dmem_data;
    MEM_SIZE proc2Dmem_size;
    logic [`XLEN-1:0] proc2Dmem_addr [1:0];
    logic [1:0] Dmem_gnt;
    logic wr_mem, rd_mem;

    // ROB outputs
    PPLN_CTRL pipeline_control;
    logic rob_full, rob_empty, retire;
    logic [`XLEN-1:0] V1_rob, V2_rob, rob_write_data;
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
    ROB_T mt_T_wire, retire_T_wire;
    ROB_T rob_head, rob_tail;

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

    assign Dmem_req = (wr_mem | rd_mem);

    // for all memory vectors, ind0 -> wr and ind1 -> rd

    always_comb begin
        Dmem_gnt = 2'b00;

        if (Dmem_req) begin
            if (wr_mem) begin
                proc2mem_addr    = proc2Dmem_addr[0];
                proc2mem_command = BUS_STORE;
                Dmem_gnt = 2'b01;
            end else begin
                proc2mem_addr    = proc2Dmem_addr[1];
                proc2mem_command = BUS_LOAD;
                Dmem_gnt = 2'b10;
            end
        end else begin
            proc2mem_addr    = proc2Imem_addr;
            proc2mem_command = proc2Imem_command;
        end
        proc2mem_data = {32'b0, proc2Dmem_data};
    end

    //////////////////////////////////////////////////
    //                                              //
    //                  IF-Stage                    //
    //                                              //
    //////////////////////////////////////////////////

    assign take_branch   = pipeline_control.flush;
    assign branch_target = rob_write_data; 
    assign IF_stall = 0;

    if_stage if_stage_0(
        .clock(clock), .reset(reset), .stall(rs_stall), .Imem_gnt(~Dmem_req & ~rs_stall),
        .take_branch(take_branch),
        .branch_target(branch_target),
        .Imem2proc_data(mem2proc_data),
        .Imem2proc_response(mem2proc_response), .Imem2proc_tag(mem2proc_tag),

        .mem_req(Imem_req),
        .IF_packet(IF_packet),
        .proc2Imem_command(proc2Imem_command),
        .proc2Imem_addr(proc2Imem_addr)
    );

    assign IF_enable = 1'b1 & ~rs_stall;
    always_ff @(posedge clock) begin
        if (reset | take_branch) begin
            IF_ID_reg <= '0;
        end else if (IF_enable) begin
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

    assign D_enable = 1'b1 & ~rs_stall;         // if rs_stalls, means inst was not processed
    always_ff @(posedge clock) begin
        if (reset | take_branch) begin
            D_S_reg <= '0;
        // separated because may need a signal to stall
        end else if (D_enable) begin
            D_S_reg <= (D_packet.valid) ? D_packet : '0;
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
        .cdb(cdb), .T(mt_T_wire), .retire_T(retire_T_wire), 
        
        // Outputs
        .T1(T1_wire), .T2(T2_wire), 
        .mt_table_out(mt_table_out)
    );

    assign V1_rs = (T1_wire.plus == 1) ? V1_rob : V1_regfile;
    assign V2_rs = (T2_wire.plus == 1) ? V2_rob : V2_regfile;

    logic rs_idx_full;
    // assign rs_stall = rs_idx_full;
    assign rs_stall = ((D_S_reg.rs_idx == 2) | (D_S_reg.rs_idx == 3)) ? (busy[3:2] != 2'b00) : rs_idx_full;
    rs_stage rs_stage_inst (
        // Inputs
        .clock(clock), .reset(reset | take_branch), .alloc_en(D_S_reg.valid), 
        .cdb(cdb), .D_S_reg(D_S_reg), 
        .FU_ready(FU_ready),
        .T(mt_T_wire), .T1(T1_wire), .T2(T2_wire), 
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
        .NPC(D_S_reg.NPC),
        .cdb(cdb),
        .dispatch_valid(D_S_reg.valid & ~rs_stall), 
        .T(mt_T_wire), .retire_T_out(retire_T_wire), 

        // Outputs
        .ppln_ctrl(pipeline_control), .full(rob_full), .empty(rob_empty), 
        .retire(retire), .regfile_write_idx_out(retire_r_wire), 
        .regfile_write_data(rob_write_data), .rob_table_out(rob_table_out),
        .V1(V1_rob), .V2(V2_rob),
        .head(rob_head), .tail(rob_tail),
        .commit_NPC(pipeline_commit_NPC)
    );

    assign regfile_write_en   = retire & (~pipeline_control.is_store & ~pipeline_control.is_branch) & ~pipeline_control.halt;
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

    func_unit_2 func_unit_02 (
            .clock(clock), .reset(reset | take_branch), .Dmem_gnt(Dmem_gnt[1]),
            .retired(gnt[2]),
            .mem2proc_response(mem2proc_response), .mem2proc_tag(mem2proc_tag),
            .Dmem2proc_data(mem2proc_data[`XLEN-1:0]),
            .S_X_reg(S_X_regs[2]),

            .mem_load_pend(rd_mem),
            .proc2Dmem_addr(proc2Dmem_addr[1]),
            .X_packet(X_packets[2])
    );

    func_unit_3 func_unit_03 (
        .clock(clock), .reset(reset | take_branch), 
        .Dmem_gnt(Dmem_gnt[0]),              // signal that the memory was listening to this module
        .retired(gnt[3]),                    // the current mem_store has been 
        .S_X_reg(S_X_regs[3]),

        .mem_store_pend(wr_mem),             // the module is attempting to store a value
        .proc2Dmem_addr(proc2Dmem_addr[0]),
        .proc2Dmem_data(proc2Dmem_data),
        .X_packet(X_packets[3])
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

    // FU requests CDB based on completion of valid input
    // always_comb begin
    //     for(req_idx = 0; req_idx <`RS_SZ; req_idx++)
    //         FU_req[req_idx] = X_C_regs[req_idx].valid;
    // end

    // CDB stage
    assign cdb_valid = (gnt != 4'h0);
    always_comb begin
        // turn the arbiter signal to idx
        cdb_idx = (gnt[0]) ? 0 :
                  (gnt[1]) ? 1 : 
                  (gnt[2]) ? 2 : 3;
        
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

    rps4 arb (
        .clock(clock), .reset(reset | take_branch), 
        .req(FU_req), 
        .en(1'b1), 
        
        .gnt(gnt), .count()
    );

    //////////////////////////////////////////////////
    //                                              //
    //               Pipeline Outputs               //
    //                                              //
    //////////////////////////////////////////////////

    assign pipeline_completed_insts = {3'b0, retire};    // commit one valid instruction
    assign pipeline_error_status    = pipeline_control.illegal        ? ILLEGAL_INST :
                                      pipeline_control.halt           ? HALTED_ON_WFI :
                                      (mem2proc_response==4'h0 & (proc2mem_command == BUS_LOAD)) ? LOAD_ACCESS_FAULT : NO_ERROR;
    assign pipeline_commit_wr_en   = regfile_write_en;
    assign pipeline_commit_wr_idx  = regfile_write_idx;
    assign pipeline_commit_wr_data = regfile_write_data; 

endmodule // pipeline
