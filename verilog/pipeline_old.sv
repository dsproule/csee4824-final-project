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
    output IF_ID_PACKET IF_ID_reg_dbg
);

    //////////////////////////////////////////////////
    //                                              //
    //                Pipeline Wires                //
    //                                              //
    //////////////////////////////////////////////////

    // Pipeline register enables
    logic if_id_enable, id_ex_enable, ex_mem_enable, mem_wb_enable;

    // Wires from IF-Stage and IF/ID Pipeline Register
    logic Imem2proc_valid;
    logic [3:0] nextImem_tag;
    logic [`XLEN-1:0] proc2Imem_addr, lastImem_addr, new_addr;
    logic [63:0] Imem2proc_data;
    IF_ID_PACKET IF_packet, IF_ID_reg;
    
    // Wires from OoO RS/ROB/MT section
    logic [$bits(ROB_ENTRY)*`ROB_SZ-1:0] rob_table_out;
    logic [$bits(MT_ENTRY)*32-1:0] mt_table_out;
    RS_ENTRY [`RS_SZ-1:0] rs_table;
    
    logic              rs_stall, rob_full, rob_empty, retire, regfile_write_en;
    logic [4:0]        retire_r_wire, regfile_write_idx;
    ROB_T              T_wire, retire_T_wire;
    MT_ENTRY           T1_wire, T2_wire;
    logic [`RS_SZ-1:0] FU_ready, busy;
    logic [`XLEN-1:0]  V1_rs, V2_rs, V1_rob, V2_rob, V1_regfile, V2_regfile;
    logic [`XLEN-1:0]  regfile_write_data, rob_write_data;
    logic [`RS_SZ:0]   X_idx, S_idx, req_idx, fu_idx;
    D_S_PACKET         D_packet, D_S_reg;
    S_X_PACKET [`RS_SZ-1:0] S_packets, S_X_regs;

    // Wires from X stage
    CDB cdb;
    PPLN_CTRL pipeline_control;
    X_C_PACKET [`RS_SZ-1:0] X_packets, X_C_regs;
    logic [`RS_SZ-1:0] cdb_valid, gnt, FU_req;
    logic [`RS_SZ:0]   cdb_idx, gnt_idx;

    // Outputs from MEM-Stage to memory
    logic [`XLEN-1:0] proc2Dmem_addr;
    logic [`XLEN-1:0] proc2Dmem_data;
    logic [1:0]       proc2Dmem_command, proc2Imem_command;
    MEM_SIZE          proc2Dmem_size;

    // Outputs from WB-Stage (These loop back to the register file in ID)
    logic             wb_regfile_en;
    logic [4:0]       wb_regfile_idx;
    logic [`XLEN-1:0] wb_regfile_data;

    assign rob_table_out_dbg = rob_table_out;
    assign mt_table_out_dbg  = mt_table_out;
    assign rs_table_dbg      = rs_table;
    assign cdb_dbg           = cdb;
    assign X_packets_dbg     = X_packets;
    assign busy_dbg          = busy;
    assign IF_ID_reg_dbg     = IF_ID_reg;

    //////////////////////////////////////////////////
    //                                              //
    //                Memory Outputs                //
    //                                              //
    //////////////////////////////////////////////////

    // these signals go to and from the processor and memory
    // we give precedence to the mem stage over instruction fetch
    // note that there is no latency in project 3
    // but there will be a 100ns latency in project 4

    always_comb begin
        if (reset) begin
            proc2Dmem_command = BUS_NONE;
        end else if (proc2Dmem_command != BUS_NONE) begin // read or write DATA from memory
            proc2mem_command = proc2Dmem_command;
            proc2mem_addr    = proc2Dmem_addr;
`ifndef CACHE_MODE
            proc2mem_size    = proc2Dmem_size;  // size is never DOUBLE in project 3
`endif
        end else begin                          // read an INSTRUCTION from memory
            proc2mem_command = proc2Imem_command;
            proc2mem_addr    = proc2Imem_addr;
`ifndef CACHE_MODE
            proc2mem_size    = DOUBLE;          // instructions load a full memory line (64 bits)
`endif
        end
        proc2mem_data = {32'b0, proc2Dmem_data};
    end

    //////////////////////////////////////////////////
    //                                              //
    //                  IF-Stage                    //
    //                                              //
    //////////////////////////////////////////////////

    if_stage if_stage_0(
        // Inputs
        .clock (clock),
        .reset (reset),
        .if_valid       (Imem2proc_valid),
        .take_branch    (),                 // ignore because this scares me for now
        .branch_target  (),                 // check above comment
        .Imem2proc_data (Imem2proc_data),

        // Outputs
        .if_packet      (IF_packet),
        .proc2Imem_addr (proc2Imem_addr)
    );

    // when response comes back in turn on the if_stage
    assign Imem2proc_valid = (mem2proc_tag == nextImem_tag) & (nextImem_tag != '0);

    always_ff @(posedge clock) begin
        new_addr <= (lastImem_addr != IF_ID_reg.NPC) & ~reset & IF_ID_reg.valid;

        if (reset) begin
            lastImem_addr <= `XLEN'hFFFFFFFF;

            IF_ID_reg.inst  <= `NOP;
            IF_ID_reg.valid <= `TRUE;
            IF_ID_reg.NPC   <= 'h4;
            IF_ID_reg.PC    <= 0;
        end else begin
            // makes the last_addr trail the PC
            lastImem_addr <= IF_ID_reg.PC;

            // we can pass '0 because we only check valid in next stage
            IF_ID_reg <= (IF_packet.valid) ? IF_packet : '0;
        end
    end

    always_comb begin
        if (new_addr) begin
            proc2Imem_command = BUS_LOAD;
            nextImem_tag      = mem2proc_response;
        end else begin
            proc2Imem_command = BUS_NONE;
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

    map_table map_table_inst (
        // Inputs
        .clock(clock), .reset(reset), 
        .en(D_S_reg.valid & ~rs_stall), 
        .r(D_S_reg.r), .r1(D_S_reg.r1), .r2(D_S_reg.r2), 
        .retire_r(retire_r_wire), 
        .cdb(cdb), .T(T_wire), .retire_T(retire_T_wire), 
        
        // Outputs
        .T1(T1_wire), .T2(T2_wire), 
        .mt_table_out(mt_table_out)
    );

    assign V1_rs = (T1_wire.plus == 1) ? V1_rob : V1_regfile;
    assign V2_rs = (T2_wire.plus == 1) ? V2_rob : V2_regfile;

    rs_stage rs_stage_inst (
        // Inputs
        .clock(clock), .reset(reset), .en(D_S_reg.valid & ~rs_stall), 
        .cdb(cdb), .D_S_reg(D_S_reg), 
        .FU_ready(FU_ready),
        .T(T_wire), .T1(T1_wire), .T2(T2_wire), 
        .V1(V1_rs), .V2(V2_rs), 

        // Outputs           
        .stall(rs_stall),
        .S_packet(S_packets), 
        .rs_table(rs_table), .busy(busy)
    );

    // for FU_ready S_X
    always_ff @(posedge clock) begin
        for (fu_idx = 0; fu_idx < `RS_SZ; fu_idx++)
            if (reset | gnt[fu_idx])
                FU_ready[fu_idx] <= `TRUE;      // general FU wipe
            else if (FU_ready[fu_idx] & S_packets[fu_idx].valid)
                FU_ready[fu_idx] <= `FALSE;     // FU reserved by entry (issue)
    end

    rob rob_inst (
        // Inputs
        .clock(clock), .reset(reset),
        .r(D_S_reg.r), .T1(T1_wire.T), .T2(T2_wire.T),
        .cdb(cdb),
        .dispatch_valid(D_S_reg.valid & ~rs_stall), 
        .T(T_wire), .retire_T_out(retire_T_wire), 

        // Outputs
        .ppln_ctrl(pipeline_control), .full(rob_full), .empty(rob_empty), 
        .retire(retire), .regfile_write_idx_out(retire_r_wire), 
        .regfile_write_data(rob_write_data), .rob_table_out(rob_table_out),
        .V1(V1_rob), .V2(V2_rob)
    );

    assign regfile_write_en   = retire;
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
            if (reset) begin
                S_X_regs[S_idx] <= 0;            
            end else if (FU_ready[S_idx] & S_packets[S_idx].valid) begin
                S_X_regs[S_idx] <= S_packets[S_idx];
            end else begin
                S_X_regs[S_idx] <= 0;
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
        .clock(clock), .reset(reset), 
        .S_X_reg(S_X_regs[1]), 

        // Outputs    
        .X_packet(X_packets[1])
    );

    // X_C regs
    always_ff @(posedge clock) begin
        for (X_idx = 0; X_idx < `RS_SZ; X_idx++)
            if (reset) begin
                X_C_regs[X_idx] <= 0;
            end else if (X_packets[X_idx].valid) begin
                X_C_regs[X_idx] <= X_packets[X_idx];
            end
    end

    //////////////////////////////////////////////////
    //                                              //
    //               Commit stage                   //
    //                                              //
    //////////////////////////////////////////////////

    always_comb begin
        for(req_idx = 0; req_idx <`RS_SZ; req_idx++)
            if(X_packets[req_idx].valid === 1)
                FU_req[req_idx] = 1;
            else
                FU_req[req_idx] = 0;
    end

    always_ff @(posedge clock) begin
        for (gnt_idx = 0; gnt_idx < `RS_SZ; gnt_idx++)
            if (reset)
                cdb_valid[gnt_idx] <= '0;
            else
                cdb_valid[gnt_idx] <= gnt[gnt_idx];
    end

    // CDB stage
    always_comb begin
        cdb_idx = (cdb_valid[0]) ? 0 :
                  (cdb_valid[1]) ? 1 : 
                  (cdb_valid[2]) ? 2 : 3;
        cdb.ppln_ctrl = X_C_regs[cdb_idx].ppln_ctrl;
        if(|cdb_valid) begin
            cdb.valid = `TRUE;
            cdb.T = X_C_regs[cdb_idx].T;
            cdb.V = X_C_regs[cdb_idx].result;
        end else begin
            cdb.valid = `FALSE;
            cdb.T = 0;
            cdb.V = 0;
        end
    end

    rps4 arb (
        .clock(clock), .reset(reset), 
        .req(FU_req), 
        .en(1'b1), 
        
        .gnt(gnt), .count()
    );

    //////////////////////////////////////////////////
    //                                              //
    //               Pipeline Outputs               //
    //                                              //
    //////////////////////////////////////////////////

    assign pipeline_completed_insts = {3'b0, pipeline_control.valid};    // commit one valid instruction
    assign pipeline_error_status    = pipeline_control.illegal        ? ILLEGAL_INST :
                                      pipeline_control.halt           ? HALTED_ON_WFI :
                                      (mem2proc_response==4'h0 & proc2mem_command != BUS_NONE) ? LOAD_ACCESS_FAULT : 
                                                                        NO_ERROR;

    assign pipeline_commit_wr_en   = regfile_write_en;
    assign pipeline_commit_wr_idx  = regfile_write_idx;
    assign pipeline_commit_wr_data = regfile_write_data;
    // assign pipeline_commit_NPC     = mem_wb_reg.NPC;

endmodule // pipeline
