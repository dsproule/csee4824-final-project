`timescale 1ns/1ps
`include "verilog/sys_defs.svh"

module lsq_tb;

    // Parameters
    localparam LSQ_SZ = 4;
    localparam PTR_WIDTH = $clog2(LSQ_SZ);

    // Signals
    logic clock, reset;
    logic alloc_en;
    LSQ_ENTRY lsq_entry;

    logic retire_en;
    ROB_T retire_T;

    logic load_exec_en;
    logic [`XLEN-1:0] load_addr;
    ROB_T load_T;

    logic [`XLEN-1:0] load_data;
    logic store_load_fwd;

    logic mem_write_en;
    logic [`XLEN-1:0] proc2mem_addr;
    logic [`XLEN-1:0] proc2mem_data;

    logic full, empty;

    // Instantiate DUT
    lsq #(.LSQ_SZ(LSQ_SZ)) dut (
        .clock,
        .reset,
        .alloc_en,
        .lsq_entry,
        .retire_T,
        .retire_en,
        .load_exec_en,
        .load_addr,
        .load_T,
        .load_data,
        .store_load_fwd,
        .mem_write_en,
        .proc2mem_addr,
        .proc2mem_data,
        .full,
        .empty
    );

    // Clock generation
    always #5 clock = ~clock;

    task reset_lsq;
        begin
            reset = 1;
            #10;
            reset = 0;
            #10;
        end
    endtask

    initial begin
        $display("Starting LSQ Testbench");
        clock = 0;
        reset = 0;
        alloc_en = 0;
        retire_en = 0;
        load_exec_en = 0;
        lsq_entry = '0;

        reset_lsq();

        // ========== SECTION 1: No Forwarding ==========
        lsq_entry.valid = 1;
        lsq_entry.addr = 32'h10;
        lsq_entry.data = 32'hABCD;
        lsq_entry.is_store = 1;
        lsq_entry.ready = 1;
        lsq_entry.T = 5'd1;
        alloc_en = 1;
        #10 alloc_en = 0;

        retire_T = 5'd1;
        retire_en = 1;
        #10 retire_en = 0;

        if (!mem_write_en || proc2mem_addr !== 32'h10 || proc2mem_data !== 32'hABCD) begin
            $display("ERROR: Store did not commit correctly to memory.");
            $finish;
        end else begin
            $display("PASS: Store commit without forwarding");
        end

        // ========== SECTION 2: With Forwarding ==========
        lsq_entry.addr = 32'h20;
        lsq_entry.data = 32'hDEAD;
        lsq_entry.is_store = 1;
        lsq_entry.ready = 1;
        lsq_entry.T = 5'd2;
        alloc_en = 1;
        #10 alloc_en = 0;

        lsq_entry.addr = 32'h20;
        lsq_entry.data = 0;
        lsq_entry.is_store = 0;
        lsq_entry.ready = 0;
        lsq_entry.T = 5'd3;
        alloc_en = 1;
        #10 alloc_en = 0;

        load_exec_en = 1;
        load_addr = 32'h20;
        load_T = 5'd3;
        #10 load_exec_en = 0;

        if (!store_load_fwd || load_data !== 32'hDEAD) begin
            $display("ERROR: Store-to-load forwarding failed.");
            $finish;
        end else begin
            $display("PASS: Store-to-load forwarding succeeded");
        end

        // ========== SECTION 3: Edge Cases ==========
        load_exec_en = 1;
        load_addr = 32'h30;
        load_T = 5'd4;
        #10 load_exec_en = 0;

        if (store_load_fwd) begin
            $display("ERROR: Forwarding occurred from empty LSQ.");
            $finish;
        end else begin
            $display("PASS: No forwarding from empty LSQ");
        end

        for (int i = 0; i < LSQ_SZ; i++) begin
            lsq_entry.valid = 1;
            lsq_entry.addr = 32'h40 + i;
            lsq_entry.data = 32'h1000 + i;
            lsq_entry.is_store = 1;
            lsq_entry.ready = 1;
            lsq_entry.T = i + 5;
            alloc_en = 1;
            #10 alloc_en = 0;
        end

        if (!full) begin
            $display("ERROR: LSQ should be full after %0d allocations.", LSQ_SZ);
            $finish;
        end else begin
            $display("PASS: LSQ full condition detected correctly");
        end

        lsq_entry.addr = 32'hFF;
        lsq_entry.T = 5'd31;
        alloc_en = 1;
        #10 alloc_en = 0;

        if (full && dut.queue[dut.tail].addr == 32'hFF) begin
            $display("ERROR: Allocation occurred even though LSQ was full.");
            $finish;
        end else begin
            $display("PASS: No allocation when LSQ is full");
        end

        $display("All tests completed successfully.");
        $finish;
    end

endmodule
