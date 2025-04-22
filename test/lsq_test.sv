`timescale 1ns / 1ps
`include "verilog/sys_defs.svh"

module lsq_tb;

  // Inputs
  logic clock = 0, reset;
  logic sq_alloc, lq_alloc;
  ROB_T T, retire_T;
  logic store_X, load_X, retire_en;
  S_X_PACKET S_X_store, S_X_load;

  // Outputs
  logic [`XLEN-1:0] load_data;
  logic store_load_fwd;
  logic [`XLEN-1:0] proc2Dmem_addr_store, proc2Dmem_data_store;
  MEM_ACCESS mem_access_store;
  ROB_T store_T;

  logic [`XLEN-1:0] proc2Dmem_addr_load, proc2Dmem_data_load;
  MEM_ACCESS mem_access_load;
  ROB_T load_T;
  logic load_data_valid;

  logic sq_full, sq_empty, lq_full, lq_empty;

  // Instantiate LSQ
  lsq dut (
    .clock(clock),
    .reset(reset),
    .sq_alloc(sq_alloc),
    .lq_alloc(lq_alloc),
    .T(T),
    .S_X_store(S_X_store),
    .S_X_load(S_X_load),
    .store_X(store_X),
    .load_X(load_X),
    .retire_T(retire_T),
    .retire_en(retire_en),
    .load_data(load_data),
    .store_load_fwd(store_load_fwd),
    .proc2Dmem_addr_store(proc2Dmem_addr_store),
    .proc2Dmem_data_store(proc2Dmem_data_store),
    .mem_access_store(mem_access_store),
    .store_T(store_T),
    .load_data_valid(load_data_valid),
    .proc2Dmem_addr_load(proc2Dmem_addr_load),
    .proc2Dmem_data_load(proc2Dmem_data_load),
    .mem_access_load(mem_access_load),
    .load_T(load_T),
    .sq_full(sq_full),
    .sq_empty(sq_empty),
    .lq_full(lq_full),
    .lq_empty(lq_empty)
  );

  always #5 clock = ~clock;

  int clock_count = 0;
  always @(posedge clock) clock_count++;

  // Self-checking
  task check(input string msg, input logic cond);
    if (!cond) begin
      $display("ERROR at time %0t: %s", clock_count, msg);
      $finish;
    end else begin
      $display("PASS at time %0t: %s", clock_count, msg);
    end
  endtask

  task print_sq;
    $display("\n(SQ_TABLE) full: %1b empty: %1b \ttime: %0d", sq_full, sq_empty, clock_count);
    $display("-------------------------------------------------------------------");
    for (int i = 0; i < `SQ_SZ; i++) begin
      $display("SQ[%2d]  valid: %1b  ROB_T: %3d  Addr: %8h  Data: %8h", 
               i, dut.sq[i].valid, dut.sq[i].T, dut.sq[i].addr, dut.sq[i].data);
    end
    $display("-------------------------------------------------------------------\n");
  endtask

  // Debug print for load queue
  task print_lq;
    $display("\n(LQ_TABLE) full: %1b empty: %1b \ttime: %0d", lq_full, lq_empty, clock_count);
    $display("-------------------------------------------------------------------");
    for (int i = 0; i < `LQ_SZ; i++) begin
      $display("LQ[%2d]  valid: %1b  ROB_T: %3d  Addr: %8h  Data: %8h", 
               i, dut.lq[i].valid, dut.lq[i].T, dut.lq[i].addr, dut.lq[i].data);
    end
    $display("-------------------------------------------------------------------\n");
  endtask

  initial begin
    $display("----- LSQ Testbench Start -----");
    reset = 1;
    sq_alloc = 0; lq_alloc = 0; store_X = 0; load_X = 0; retire_en = 0;

    @(negedge clock);
    reset = 0;

    // Dispatch a store
    @(negedge clock);
    sq_alloc = 1;
    T = 1;
    @(posedge clock);
    #1; print_sq();
    sq_alloc = 0;

    @(negedge clock);
    store_X = 1;
    S_X_store.V1 = 32'h1000;
    S_X_store.mem_offset = 0;
    S_X_store.V2 = 32'hDEADBEEF;
    S_X_store.mem_size = 2'b10;
    S_X_store.rd_unsigned = 0;

    @(posedge clock);
    #1; print_sq();

    // Dispatch a load to same address
    @(negedge clock);
    store_X = 0;

    lq_alloc = 1;
    T = 2;
    @(posedge clock);
    #1; print_lq();

    @(negedge clock);
    lq_alloc = 0;

    load_X = 1;
    S_X_load.V1 = 32'h1000;
    S_X_load.mem_offset = 0;
    S_X_load.mem_size = 2'b10;
    S_X_load.rd_unsigned = 0;

    @(negedge clock);
    load_X = 0;
    // print() check forwrding

    @(posedge clock);
    print_lq();
    check("Forwarded load data is correct", store_load_fwd && load_data == 32'hDEADBEEF);

    

    // Retire the store
    @(negedge clock);
    retire_T = 1;
    retire_en = 1;

    @(negedge clock);
    retire_en = 0;

    @(posedge clock);
    check("Store retired to memory", dut.mem_write_en && proc2Dmem_data_store == 32'hDEADBEEF);

    $display("----- LSQ Testbench Finished -----");
    $finish;
  end

endmodule