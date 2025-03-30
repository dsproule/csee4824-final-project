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

    // Debug outputs: these signals are solely used for debugging in testbenches
    // Do not change for project 3
    // You should definitely change these for project 4
    output logic [`XLEN-1:0] if_NPC_dbg,
    output logic [31:0]      if_inst_dbg,
    output logic             if_valid_dbg,
    output logic [`XLEN-1:0] if_id_NPC_dbg,
    output logic [31:0]      if_id_inst_dbg,
    output logic             if_id_valid_dbg,
    output logic [`XLEN-1:0] id_ex_NPC_dbg,
    output logic [31:0]      id_ex_inst_dbg,
    output logic             id_ex_valid_dbg,
    output logic [`XLEN-1:0] ex_mem_NPC_dbg,
    output logic [31:0]      ex_mem_inst_dbg,
    output logic             ex_mem_valid_dbg,
    output logic [`XLEN-1:0] mem_wb_NPC_dbg,
    output logic [31:0]      mem_wb_inst_dbg,
    output logic             mem_wb_valid_dbg
);

    //////////////////////////////////////////////////
    //                                              //
    //                Pipeline Wires                //
    //                                              //
    //////////////////////////////////////////////////

    // Pipeline register enables
    logic if_id_enable, id_ex_enable, ex_mem_enable, mem_wb_enable;

    // Outputs from IF-Stage and IF/ID Pipeline Register
    logic [`XLEN-1:0] proc2Imem_addr;
    IF_ID_PACKET if_packet, if_id_reg;

    // Outputs from decode to rs, mt and rob
    D_S_PACKET D_packet, D_S_reg;

    // Outputs from rs to FU
    S_X_PACKET [`RS_SZ-1:0] S_packets, S_X_reg;
    logic [`RS_SZ:0] S_idx;

    // Outputs from FU to X_C (cdb)
    X_C_PACKET [`RS_SZ-1:0] X_packets, X_C_reg;
    logic [`RS_SZ:0] X_idx;
    logic [`RS_SZ-1:0] gnt;
    CDB cdb;

    // Outputs and inputs for RS alloc stage
    logic rs_busy;
    ROB_T T;
    MT_ENTRY mt_T1, mt_T2;
    logic [`XLEN-1:0] regfile_V1, regfile_V2, rs_V1, rs_V2, rob_V1, rob_V2;

    // Outputs from ID stage and ID/EX Pipeline Register
    // ID_EX_PACKET id_packet, id_ex_reg;

    // Outputs from EX-Stage and EX/MEM Pipeline Register // ?needed
    // EX_MEM_PACKET ex_packet, ex_mem_reg;

    // // Outputs from MEM-Stage and MEM/WB Pipeline Register
    // MEM_WB_PACKET mem_packet, mem_wb_reg;

    // Outputs from MEM-Stage to memory
    // logic [`XLEN-1:0] proc2Dmem_addr;
    // logic [`XLEN-1:0] proc2Dmem_data;
    // logic [1:0]       proc2Dmem_command;
    // MEM_SIZE          proc2Dmem_size;

    // Outputs from Commit-rob
    logic              rob_regfile_en, rob_full, rob_retire, no_X_req, ppl_flush, mem_store;
    logic [4:0]        rob_regfile_idx;
    logic [`XLEN-1:0]  rob_regfile_data;
    logic [$clog2(`RS_SZ)-1:0] cdb_idx;
    logic [$bits(ROB_ENTRY)*`ROB_SZ-1:0] rob_table_out;
    logic [`RS_SZ-1:0] FU_ready;
    PPLN_CTRL ppln_ctrl;
    ROB_T rob_retire_T;

    // // Outputs from WB-Stage (These loop back to the register file in ID)
    // logic             wb_regfile_en;
    // logic [4:0]       wb_regfile_idx;
    // logic [`XLEN-1:0] wb_regfile_data;

    // Debug values
    logic [$bits(MT_ENTRY)*32-1:0] mt_table_dbg;
    logic [`RS_SZ-1:0] busy_dbg;
    RS_ENTRY [`RS_SZ-1:0]  rs_table_dbg;

    //////////////////////////////////////////////////
    //                                              //
    //                Memory Outputs                //
    //                                              //
    //////////////////////////////////////////////////

    // these signals go to and from the processor and memory
    // we give precedence to the mem stage over instruction fetch
    // note that there is no latency in project 3
    // but there will be a 100ns latency in project 4

    // always_comb begin
    //     if (proc2Dmem_command != BUS_NONE) begin // read or write DATA from memory
    //         proc2mem_command = proc2Dmem_command;
    //         proc2mem_addr    = proc2Dmem_addr;
    //         proc2mem_size    = proc2Dmem_size;  // size is never DOUBLE in project 3
    //     end else begin                          // read an INSTRUCTION from memory
    //         proc2mem_command = BUS_LOAD;
    //         proc2mem_addr    = proc2Imem_addr;
    //         proc2mem_size    = DOUBLE;          // instructions load a full memory line (64 bits)
    //     end
    //     proc2mem_data = {32'b0, proc2Dmem_data};
    // end

    always_comb begin
        // read an INSTRUCTION from memory
        proc2mem_command = BUS_LOAD;
        proc2mem_addr    = proc2Imem_addr;
        proc2mem_size    = DOUBLE;          // instructions load a full memory line (64 bits)
        proc2mem_data = {64'b0};
    end

    //////////////////////////////////////////////////
    //                                              //
    //                  Valid Bit                   //
    //                                              //
    //////////////////////////////////////////////////

    // This state controls the stall signal that artificially forces IF
    // to stall until the previous instruction has completed.
    // For project 3, start by setting this to always be 1
    logic struct_hazard;
    logic control_hazard;
    logic ex_forward_a;
    logic ex_forward_b;
    logic mem_forward_a;
    logic mem_forward_b;
    logic load_hazard;

    // always_comb begin
    //     struct_hazard = (ex_mem_reg.rd_mem == 1'b1) | (ex_mem_reg.wr_mem == 1'b1);
    //     control_hazard = ex_mem_reg.take_branch;

    //     ex_forward_a = (ex_mem_reg.dest_reg_idx != `ZERO_REG) & (ex_mem_reg.dest_reg_idx == id_ex_reg.inst.r.rs1);
    //     ex_forward_b = (ex_mem_reg.dest_reg_idx != `ZERO_REG) & (ex_mem_reg.dest_reg_idx == id_ex_reg.inst.r.rs2);
    //     mem_forward_a = (mem_wb_reg.dest_reg_idx != `ZERO_REG) & (mem_wb_reg.dest_reg_idx == id_ex_reg.inst.r.rs1);
    //     mem_forward_b = (mem_wb_reg.dest_reg_idx != `ZERO_REG) & (mem_wb_reg.dest_reg_idx == id_ex_reg.inst.r.rs2);

    //     load_hazard = (id_ex_reg.rd_mem) & ((id_ex_reg.dest_reg_idx == if_id_reg.inst.r.rs1) | (id_ex_reg.dest_reg_idx == if_id_reg.inst.r.rs2));
    // end

    logic next_if_valid;
    assign next_if_valid = 1;
    // assign next_if_valid = (load_hazard | struct_hazard) ? 0 : 1;

    //////////////////////////////////////////////////
    //                                              //
    //                  IF-Stage                    //
    //                                              //
    //////////////////////////////////////////////////

    stage_if stage_if_0 (
        // Inputs
        .clock (clock),
        .reset (reset),
        .if_valid       (next_if_valid),
        .take_branch    (0), // TODO: no branch for now
        .branch_target  (64'b0), // TODO: no branch for now
        .Imem2proc_data (mem2proc_data),
        .load_hazard    (load_hazard),

        // Outputs
        .if_packet      (if_packet),
        .proc2Imem_addr (proc2Imem_addr)
    );

    // debug outputs
    assign if_NPC_dbg   = if_packet.NPC;
    assign if_inst_dbg  = if_packet.inst;
    assign if_valid_dbg = if_packet.valid;

    //////////////////////////////////////////////////
    //                                              //
    //            IF/ID Pipeline Register           //
    //                                              //
    //////////////////////////////////////////////////

    assign if_id_enable = 1'b1; // always enabled
    // synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if (reset) begin
            if_id_reg.inst  <= `NOP;
            if_id_reg.valid <= `FALSE;
            if_id_reg.NPC   <= 0;
            if_id_reg.PC    <= 0;
        // end else if (control_hazard) begin
        //     if_id_reg.inst  <= `NOP;
        //     if_id_reg.valid <= `FALSE;
        //     if_id_reg.NPC   <= 0;
        //     if_id_reg.PC    <= 0;
        // end else if (load_hazard) begin
        //     if_id_reg <= if_id_reg;
        end else if (if_id_enable) begin
            if_id_reg <= if_packet;
        end
    end

    // debug outputs
    assign if_id_NPC_dbg   = if_id_reg.NPC;
    assign if_id_inst_dbg  = if_id_reg.inst;
    assign if_id_valid_dbg = if_id_reg.valid;

    //////////////////////////////////////////////////
    //                                              //
    //                  ID-Stage                    //
    //                                              //
    //////////////////////////////////////////////////

    d_stage d_stage_0(
        // Inputs
        .IF_ID_reg(if_id_reg),

        // Outputs
        .D_packet(D_packet)
    );

    //////////////////////////////////////////////////
    //                                              //
    //            D/S Pipeline Register             //
    //                                              //
    //////////////////////////////////////////////////

    assign D_S_enable = 1'b1; // always enabled
    // synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if (reset) begin
            D_S_reg <= {
                `NOP, 
                {`XLEN{1'b0}}, // PC
                {`XLEN{1'b0}}, // NPC
                {`XLEN{1'b0}}, // r
                {`XLEN{1'b0}}, // r1
                {`XLEN{1'b0}}, // r2
                OPA_IS_RS1,
                OPB_IS_RS2,
                1'b0,          // cond
                1'b0,          // uncond
                ALU_ADD,       // alu_func
                `RS_SZ'd2, // the functional unit is use
                1'b0, // halt
                1'b0, // illegal
                1'b0, // csr_op
                `FALSE  // valid
            };
        end else if (D_S_enable) begin
            D_S_reg <= D_packet;
        end
    end

    //////////////////////////////////////////////////
    //                                              //
    //            RS, Map table                     //
    //                                              //
    //////////////////////////////////////////////////

    map_table map_table_0(
        // Inputs
        .clock(clock), .reset(reset),
        // .en(D_S_reg.valid & ~rs_busy),
        .en(D_S_reg.valid & ~d_stall), // shouldn't care about stall because you can do cdb broadcast even if rs stall
        .en_r(retire),
        .r(D_S_reg.r), .r1(D_S_reg.r1), .r2(D_S_reg.r2),
        .retire_r(rob_regfile_idx), // from ROB
        .cdb(cdb),
        .T(T), // from ROB
        .retire_T(rob_retire_T), // from ROB

        // Outputs
        .T1(mt_T1), .T2(mt_T2), // to rs

        // Debug Outputs
        .mt_table_out(mt_table_dbg)

    );

    assign rs_V1 =  (mt_T1.T == 0) ? regfile_V1 :
                    (mt_T1.plus)   ?   rob_V1   : 0;
    assign rs_V2 =  (mt_T2.T == 0) ? regfile_V2 :
                    (mt_T2.plus)   ?   rob_V2   : 0;

    rs_stage rs_stage_0(
        // Inputs
        .clock(clock), .reset(reset),
        .en(D_S_reg.valid & ~d_stall),
        .cdb(cdb),
        .D_S_reg(D_S_reg),      
        .FU_ready(FU_ready),    // from fu arb
        .T(T),                  // from rob
        .T1(mt_T1), .T2(mt_T2),       // from mt
        .V1(rs_V1), .V2(rs_V2),       // mux between mt & rob

        // Outputs
        .d_stall(rs_busy),
        .S_packet(S_packets),

        // Debug Outputs
        .rs_table(rs_table_dbg),
        .busy(busy_dbg)
    );

    regfile regfile_0(
        // Inputs
        .clock(clock),
        .read_idx_1(D_S_reg.r1), .read_idx_2(D_S_reg.r2), .write_idx(rob_regfile_idx),
        .write_en(rob_retire),
        .write_data(rob_regfile_data),

        // Outputs
        .read_out_1(regfile_V1), .read_out_2(regfile_V2)
    );
    
    //////////////////////////////////////////////////
    //                                              //
    //                  S/X reg                     //
    //                                              //
    //////////////////////////////////////////////////

    assign S_X_enable = 1'b1; // always enabled
    always_ff @(posedge clock) begin
        for (S_idx = 0; S_idx < `RS_SZ; S_idx++)
            if (reset) begin
                S_X_reg[S_idx] <= 0;                // may need to be more graceful one day but for rn idc
            end else if (FU_ready[S_idx]) begin
                S_X_reg[S_idx] <= S_packets[S_idx];
            end
    end

    //////////////////////////////////////////////////
    //                                              //
    //              Functional Units                //
    //                                              //
    //////////////////////////////////////////////////

    func_unit_0 func_unit_00(
        .S_X_reg(S_X_reg[0]),

        .X_packet(X_packets[0])
    );

    func_unit_1 func_unit_01(
        .clock(clock), .reset(reset),
        .S_X_reg(S_X_reg[1]),

        .X_packet(X_packets[1])
    );

    func_unit_2 func_unit_02(
        .S_X_reg(S_X_reg[2]),

        .X_packet(X_packets[2])
    );

    func_unit_3 func_unit_03(
        .S_X_reg(S_X_reg[3]),

        .X_packet(X_packets[3])
    );

    //////////////////////////////////////////////////
    //                                              //
    //               X/C regs and CDB               //
    //                                              //
    //////////////////////////////////////////////////

    assign X_C_enable = 1'b1; // always enabled
    // synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        for (X_idx = 0; X_idx < `RS_SZ; X_idx++)
            if (reset) begin
                FU_ready[X_idx] <= `TRUE;
                X_C_reg[X_idx] <= 0;
            end else if (X_packets[X_idx].valid) begin
                X_C_reg[X_idx] <= X_packets[X_idx];
                FU_ready[X_idx] <= `TRUE;
            end

            // Frees up FU if cdb currently has it
            if (gnt[X_idx])
                FU_ready <= 0;
    end

    rps4 arb (
        .clock(clock), .reset(reset),
        .req(FU_ready),
        .en(rob_full),

        .gnt(gnt),
        .count()
    );

    assign no_X_req = (FU_ready == '0);

    always_comb begin
        if (~no_X_req)
            for (cdb_idx = 0; cdb_idx < `RS_SZ; cdb_idx++)
                if (gnt[cdb_idx] & ~no_X_req)
                    cdb = {X_C_reg[cdb_idx].T,
                            X_C_reg[cdb_idx].result,
                            cdb.ppln_ctrl,
                            `TRUE
                        };
        else
            cdb.valid = `FALSE;
    end

    //////////////////////////////////////////////////
    //                                              //
    //                  ROB stage                   //
    //                                              //
    //////////////////////////////////////////////////

    rob rob_0(
        // Inputs
        .clock(clock), .reset(reset),
        .r(D_S_reg.r), 
        .T1(mt_T1.T), .T2(mt_T2.T),
        .cdb(cdb),
        .dispatch_valid(D_S_reg.valid & ~rs_busy),

        // Outputs
        .T(T),
        .retire_T_out(rob_retire_T),
        .ppln_ctrl(ppln_ctrl),
        .full(rob_full), .empty(), .retire(rob_retire),
        .regfile_write_idx_out(rob_regfile_idx),
        .V1(rob_V1), .V2(rob_V2), .regfile_write_data(rob_regfile_data),

        // debug
        .rob_table_out(rob_table_out)
    );    

    //////////////////////////////////////////////////
    //                                              //
    //               Pipeline Outputs               //
    //                                              //
    //////////////////////////////////////////////////

    // assign pipeline_completed_insts = {3'b0, mem_wb_reg.valid}; // commit one valid instruction
    // assign pipeline_error_status = mem_wb_reg.illegal        ? ILLEGAL_INST :
    //                                mem_wb_reg.halt           ? HALTED_ON_WFI :
    //                                (mem2proc_response==4'h0) ? LOAD_ACCESS_FAULT : NO_ERROR;

    // assign pipeline_commit_wr_en   = wb_regfile_en;
    // assign pipeline_commit_wr_idx  = wb_regfile_idx;
    // assign pipeline_commit_wr_data = wb_regfile_data;
    // assign pipeline_commit_NPC     = mem_wb_reg.NPC;

endmodule // pipeline
