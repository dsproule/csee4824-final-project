`timescale 1ns/1ps
`include "verilog/sys_defs.svh"
`include "verilog/ISA.svh"

module ooo_check(
    input  logic                 clock,
    input  logic                 reset,

    // DUT -> MEM (requests driven by DUT/pipeline)
    output logic [1:0]           dut_proc2mem_command,
    output logic [`XLEN-1:0]     dut_proc2mem_addr,
    output logic [63:0]          dut_proc2mem_data,
`ifndef CACHE_MODE
    output MEM_SIZE              dut_proc2mem_size,
`endif

    // MEM -> DUT (responses returned to DUT)
    input  logic [3:0]           dut_mem2proc_response,
    input  logic [63:0]          dut_mem2proc_data,
    input  logic [3:0]           dut_mem2proc_tag
);

    logic [3:0]       dut_pipeline_completed_insts;
    EXCEPTION_CODE    dut_pipeline_error_status;
    logic [4:0]       dut_pipeline_commit_wr_idx;
    logic [`XLEN-1:0] dut_pipeline_commit_wr_data;
    logic             dut_pipeline_commit_wr_en;
    logic [`XLEN-1:0] dut_pipeline_commit_NPC;

    // ----------------------------
    // Instantiate DUT + its mem
    // ----------------------------
    pipeline dut (
        .clock(clock),
        .reset(reset),

        .mem2proc_response(dut_mem2proc_response),
        .mem2proc_data    (dut_mem2proc_data),
        .mem2proc_tag     (dut_mem2proc_tag),

        .proc2mem_command (dut_proc2mem_command),
        .proc2mem_addr    (dut_proc2mem_addr),
        .proc2mem_data    (dut_proc2mem_data),
`ifndef CACHE_MODE
        .proc2mem_size    (dut_proc2mem_size),
`endif

        .pipeline_completed_insts(dut_pipeline_completed_insts),
        .pipeline_error_status   (dut_pipeline_error_status),
        .pipeline_commit_wr_idx  (dut_pipeline_commit_wr_idx),
        .pipeline_commit_wr_data (dut_pipeline_commit_wr_data),
        .pipeline_commit_wr_en   (dut_pipeline_commit_wr_en),
        .pipeline_commit_NPC     (dut_pipeline_commit_NPC)
    );

    //10 instrctions in memory
    logic [63:0] imem [0:9];

    genvar i;
    generate
    for (i=0; i<10; i++) begin
        assume property (@(posedge clock) disable iff (reset) $stable(imem[i]));
    end
    endgenerate
    // --------------------------------------------------------------------
    // Assumptions: reg/control only (DUT-only)
    // --------------------------------------------------------------------

    assume property (@(posedge clock) disable iff (reset)
        (dut_pipeline_completed_insts <= 1)
    );

    // MEMORY CONSTRAINTS

    // No stores at all (read-only memory model for now).
    assume property (@(posedge clock) disable iff (reset)
        (dut_proc2mem_command != BUS_STORE)
    );

    // assume addr[`XLEN-3:3] < 10, and lower 3 bits always 0. Always aligned
    valid_inst_addr: assume property (@(posedge clock) disable iff (reset)
        (dut_proc2mem_addr[`XLEN-3:3] < 10) &&
        (dut_proc2mem_addr[2:0] == 3'b0)
    );

    // Valid instruction opcode constraints
    // Do it only when a memory return is actually presenting data (tag != 0).
    property p_valid_inst_dut;
        @(posedge clock) disable iff (reset)
            (dut_mem2proc_tag != 0) |-> (
                (dut_mem2proc_data[6:0] inside {
                    `RV32_OP,
                    `RV32_OP_IMM,
                    `RV32_BRANCH,
                    `RV32_JAL_OP,
                    `RV32_JALR_OP,
                    `RV32_LUI,
                    `RV32_AUIPC
                }) &&
                (dut_mem2proc_data[38:32] inside {
                    `RV32_OP,
                    `RV32_OP_IMM,
                    `RV32_BRANCH,
                    `RV32_JAL_OP,
                    `RV32_JALR_OP,
                    `RV32_LUI,
                    `RV32_AUIPC
                })
            );
    endproperty
    valid_inst: assume property (p_valid_inst_dut);

    // processor requesting bus load will only present a response after `MEM_LATENCY_IN_CYCLES for OoO
    assume property (@(posedge clock) disable iff (reset)
        (dut_proc2mem_command == BUS_LOAD) |-> ##[`MEM_LATENCY_IN_CYCLES]
            (dut_mem2proc_tag != 0)
    );

    inst_finishes: cover property (@(posedge clock) disable iff (reset)
    ##[1:50] (dut_pipeline_completed_insts == 1 &&
                dut_pipeline_commit_wr_en &&
                dut_pipeline_commit_wr_idx != 0)
    );

endmodule
