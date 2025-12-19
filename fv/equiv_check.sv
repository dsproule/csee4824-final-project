`timescale 1ns/1ps
`include "verilog/sys_defs.svh"
`include "verilog/ISA.svh"

module equiv_check(
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
    input  logic [3:0]           dut_mem2proc_tag,

    // REF -> MEM
    output logic [1:0]           ref_proc2mem_command,
    output logic [`XLEN-1:0]     ref_proc2mem_addr,
    output logic [63:0]          ref_proc2mem_data,
`ifndef CACHE_MODE
    output MEM_SIZE              ref_proc2mem_size,
`endif

    // MEM -> REF
    input  logic [3:0]           ref_mem2proc_response,
    input  logic [63:0]          ref_mem2proc_data,
    input  logic [3:0]           ref_mem2proc_tag
);

    logic [3:0]       dut_pipeline_completed_insts;
    EXCEPTION_CODE    dut_pipeline_error_status;
    logic [4:0]       dut_pipeline_commit_wr_idx;
    logic [`XLEN-1:0] dut_pipeline_commit_wr_data;
    logic             dut_pipeline_commit_wr_en;
    logic [`XLEN-1:0] dut_pipeline_commit_NPC;

    logic [3:0]       ref_pipeline_completed_insts;
    EXCEPTION_CODE    ref_pipeline_error_status;
    logic [4:0]       ref_pipeline_commit_wr_idx;
    logic [`XLEN-1:0] ref_pipeline_commit_wr_data;
    logic             ref_pipeline_commit_wr_en;
    logic [`XLEN-1:0] ref_pipeline_commit_NPC;

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

    // ----------------------------
    // Instantiate REF + its mem
    // ----------------------------
    inorder_pipeline gold_ref (
        .clock(clock),
        .reset(reset),

        .mem2proc_response(ref_mem2proc_response),
        .mem2proc_data    (ref_mem2proc_data),
        .mem2proc_tag     (ref_mem2proc_tag),

        .proc2mem_command (ref_proc2mem_command),
        .proc2mem_addr    (ref_proc2mem_addr),
        .proc2mem_data    (ref_proc2mem_data),
`ifndef CACHE_MODE
        .proc2mem_size    (ref_proc2mem_size),
`endif

        .pipeline_completed_insts(ref_pipeline_completed_insts),
        .pipeline_error_status   (ref_pipeline_error_status),
        .pipeline_commit_wr_idx  (ref_pipeline_commit_wr_idx),
        .pipeline_commit_wr_data (ref_pipeline_commit_wr_data),
        .pipeline_commit_wr_en   (ref_pipeline_commit_wr_en),
        .pipeline_commit_NPC     (ref_pipeline_commit_NPC)
    );

    // --------------------------------------------------------------------
    // Assumptions: reg/control only
    // --------------------------------------------------------------------

    assume property (@(posedge clock) disable iff (reset)
        (dut_pipeline_completed_insts <= 1) &&
        (ref_pipeline_completed_insts <= 1)
    );

    // MEMORY CONSTRAINTS

    // No stores at all (read-only memory model for now).
    assume property (@(posedge clock) disable iff (reset)
        (dut_proc2mem_command != BUS_STORE) &&
        (ref_proc2mem_command != BUS_STORE)
    );

    // assume addr[`XLEN-3:3] < 10, and lower 3 bits always 0. Always aligned
    valid_inst_addr: assume property (@(posedge clock) disable iff (reset)
        (dut_proc2mem_addr[`XLEN-3:3] < 10) &&
        (dut_proc2mem_addr[2:0] == 3'b0) &&
        (ref_proc2mem_addr[`XLEN-3:3] < 10) &&
        (ref_proc2mem_addr[2:0] == 3'b0)
    );

    // Valid instruction opcode constraints
    // Also constrain instruction opcodes to reg/control subset.
    // Do it only when a memory return is actually presenting data (tag != 0).
    property p_valid_inst_dut;
        @(posedge clock) disable iff (reset)
            (dut_mem2proc_tag != 0) |-> (
                (dut_mem2proc_data[6:0]   inside {
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

    property p_valid_inst_ref;
        @(posedge clock) disable iff (reset)
            (ref_mem2proc_tag != 0) |-> (ref_mem2proc_data[6:0] inside {
                `RV32_OP,
                `RV32_OP_IMM,
                `RV32_BRANCH,
                `RV32_JAL_OP,
                `RV32_JALR_OP,
                `RV32_LUI,
                `RV32_AUIPC
            }) && (ref_mem2proc_data[38:32] inside {
                `RV32_OP,
                `RV32_OP_IMM,
                `RV32_BRANCH,
                `RV32_JAL_OP,
                `RV32_JALR_OP,
                `RV32_LUI,
                `RV32_AUIPC
            });
    endproperty
    assume property (p_valid_inst_ref);

    //processor requestion bus load will only present a response after `MEM_LATENCY_IN_CYCLES for OoO and the same cycle for ref
    assume property (@(posedge clock) disable iff (reset)
        (dut_proc2mem_command == BUS_LOAD) |-> ##[`MEM_LATENCY_IN_CYCLES]
            (dut_mem2proc_tag != 0)
    );

    //reference has magical memory that always returns next cycle
    assume property (@(posedge clock) disable iff (reset)
        (ref_proc2mem_command == BUS_LOAD) |-> ##0
        (ref_mem2proc_tag != 0 && 
        ref_mem2proc_data == imem[$past(ref_proc2mem_addr[`XLEN-3:3])])
    );

    //Make a mini instruction memory table of 10 words max that is shared.
    logic [63:0] imem [0:9];
    



    // --------------------------------------------------------------------
    // Commit-order matching (FIFO)
    // --------------------------------------------------------------------

    localparam int FIFO_DEPTH = `ROB_SZ;
    localparam int FIFO_W = $clog2(FIFO_DEPTH+1);

    typedef struct packed {
        logic [`XLEN-1:0] npc;
        logic             wr_en;
        logic [4:0]       rd;
        logic [`XLEN-1:0] data;
        EXCEPTION_CODE    err;
    } commit_pkt_t;

    commit_pkt_t dut_fifo [0:FIFO_DEPTH-1];
    commit_pkt_t ref_fifo [0:FIFO_DEPTH-1];

    logic [FIFO_W-1:0] dut_wptr, dut_rptr, dut_count;
    logic [FIFO_W-1:0] ref_wptr, ref_rptr, ref_count;

    wire dut_commit = (dut_pipeline_completed_insts == 1);
    wire ref_commit = (ref_pipeline_completed_insts == 1);

    // No overflow (if this fires, either increase depth or fix a progress issue)
    assume property (@(posedge clock) disable iff (reset)
        !(dut_commit && (dut_count == FIFO_DEPTH))
    );
    assume property (@(posedge clock) disable iff (reset)
        !(ref_commit && (ref_count == FIFO_DEPTH))
    );

    always_ff @(posedge clock) begin
        if (reset) begin
            dut_wptr  <= '0; dut_rptr  <= '0; dut_count <= '0;
            ref_wptr  <= '0; ref_rptr  <= '0; ref_count <= '0;
        end else begin
            // push DUT
            if (dut_commit) begin
                dut_fifo[dut_wptr] <= '{
                    npc : dut_pipeline_commit_NPC,
                    wr_en: dut_pipeline_commit_wr_en,
                    rd  : dut_pipeline_commit_wr_idx,
                    data: dut_pipeline_commit_wr_data,
                    err : dut_pipeline_error_status
                };
                dut_wptr  <= (dut_wptr == FIFO_DEPTH-1) ? '0 : (dut_wptr + 1);
                dut_count <= dut_count + 1;
            end

            // push REF
            if (ref_commit) begin
                ref_fifo[ref_wptr] <= '{
                    npc : ref_pipeline_commit_NPC,
                    wr_en: ref_pipeline_commit_wr_en,
                    rd  : ref_pipeline_commit_wr_idx,
                    data: ref_pipeline_commit_wr_data,
                    err : ref_pipeline_error_status
                };
                ref_wptr  <= (ref_wptr == FIFO_DEPTH-1) ? '0 : (ref_wptr + 1);
                ref_count <= ref_count + 1;
            end

            // pop when both have something to compare
            if ((dut_count != 0) && (ref_count != 0)) begin
                dut_rptr  <= (dut_rptr == FIFO_DEPTH-1) ? '0 : (dut_rptr + 1);
                ref_rptr  <= (ref_rptr == FIFO_DEPTH-1) ? '0 : (ref_rptr + 1);
                dut_count <= dut_count - 1;
                ref_count <= ref_count - 1;
            end
        end
    end

    wire have_both = (dut_count != 0) && (ref_count != 0);

    // Main equivalence assertion at commit order
    assert property (@(posedge clock) disable iff (reset)
        have_both |-> (
            (dut_fifo[dut_rptr].npc   == ref_fifo[ref_rptr].npc)   &&
            (dut_fifo[dut_rptr].err   == ref_fifo[ref_rptr].err)   &&
            (dut_fifo[dut_rptr].wr_en == ref_fifo[ref_rptr].wr_en) &&
            (!dut_fifo[dut_rptr].wr_en ||
                ((dut_fifo[dut_rptr].rd   == ref_fifo[ref_rptr].rd) &&
                 (dut_fifo[dut_rptr].data == ref_fifo[ref_rptr].data)))
        )
    );

endmodule
