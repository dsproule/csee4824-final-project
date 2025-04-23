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
  X_C_PACKET load_fwd_packet [1:0];
  logic [`XLEN-1:0] proc2Dmem_addr_store, proc2Dmem_data_store;
  MEM_ACCESS mem_access_store;
  ROB_T store_T;

  logic [`XLEN-1:0] proc2Dmem_addr_load, proc2Dmem_data_load;
  MEM_ACCESS mem_access_load;
  ROB_T load_T;
  logic load_data_valid;

  logic mem_write_en;
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
    .load_fwd_packet(load_fwd_packet),
    .mem_write_en(mem_write_en),
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

  task check(input string msg, input logic cond);
    if (!cond) begin
      $display("ERROR at cycle %0t: %s", clock_count, msg);
      $finish;
    end else begin
      $display("PASS at cycle %0t: %s", clock_count, msg);
    end
  endtask

task print_sq;
  $display("\n(SQ_TABLE) full: %1b empty: %1b \ttime: %0d", sq_full, sq_empty, clock_count);
  $display("--------------------------------------------------------------------------------");
  $display("Idx | Valid |   T   |     Addr     |     Data     | Addr_Valid | Data_Valid | Retired");
  $display("--------------------------------------------------------------------------------");
  for (int i = 0; i < `SQ_SZ; i++) begin
    $display("%3d |   %1b   | %4d  |   %h   |   %h   |     %1b      |     %1b      |   %1b",
             i, dut.sq[i].valid, dut.sq[i].T, dut.sq[i].addr, dut.sq[i].data,
             dut.sq[i].addr_valid, dut.sq[i].data_valid, dut.sq[i].retired);
  end
  $display("--------------------------------------------------------------------------------\n");
endtask

task print_lq;
  $display("\n(LQ_TABLE) full: %1b empty: %1b \ttime: %0d", lq_full, lq_empty, clock_count);
  $display("----------------------------------------------------------------------------------------------------------");
  $display("Idx | Valid |   T   |     Addr     |     Data     | Addr_Valid |     State     | Dep_SQ_T");
  $display("----------------------------------------------------------------------------------------------------------");
  for (int i = 0; i < `LQ_SZ; i++) begin
    string state_str;
    case (dut.lq[i].state)
      NONE:      state_str = "NONE";
      DATA_READY:state_str = "DATA_READY";
      WAITING:   state_str = "WAITING";
      FORWARDED: state_str = "FORWARDED";
      default:   state_str = "???";
    endcase
    $display("%3d |   %1b   | %4d  |   %h   |   %h   |     %1b      | %11s   |    %2d",
             i, dut.lq[i].valid, dut.lq[i].T, dut.lq[i].addr, dut.lq[i].data,
             dut.lq[i].addr_valid, state_str, dut.lq[i].dep_sq_T);
  end
  $display("----------------------------------------------------------------------------------------------------------\n");
endtask

task print_lsq;
  print_lq();
  print_sq();
endtask

  initial begin
    $display("----- LSQ Testbench Start -----");
    reset = 1;
    sq_alloc = 0; lq_alloc = 0; store_X = 0; load_X = 0; retire_en = 0;

    @(negedge clock); reset = 0;

    // Allocate store
    @(negedge clock);
    sq_alloc = 1; T = 1;

    @(posedge clock); #1; // print_sq();
    sq_alloc = 0;

    @(negedge clock);
    store_X = 1;
    S_X_store.V1 = 32'h1000;
    S_X_store.mem_offset = 0;
    S_X_store.V2 = 32'hABCD1234;
    S_X_store.mem_size = 2'b10;
    S_X_store.rd_unsigned = 0;
    S_X_store.T = 1;

    @(posedge clock); #1; // print_sq();

    @(negedge clock);
    store_X = 0;

    // Allocate load
    @(negedge clock);
    lq_alloc = 1; T = 2;

    @(posedge clock); #1; // print_lq();
    lq_alloc = 0;

    @(negedge clock);
    load_X = 1;
    S_X_load.V1 = 32'h1000;
    S_X_load.mem_offset = 0;
    S_X_load.mem_size = 2'b10;
    S_X_load.rd_unsigned = 0;
    S_X_load.T = 2;

    @(posedge clock); #1; // print_lq();
    print_lsq();
    check("Forwarded correctly", load_fwd_packet[0].valid && load_fwd_packet[0].result == 32'hABCD1234);

    @(negedge clock);
    load_X = 0;

    // Retire store
    @(negedge clock);
    retire_T = 1;
    retire_en = 1;

    @(posedge clock); #1;
    // $display("mem_write: %d, data: %h", mem_write_en, proc2Dmem_data_store);
    retire_en = 0;
    check("Store retired to memory", mem_write_en && proc2Dmem_data_store == 32'hABCD1234);

    //lsq should be empty here
    check("Should be empty",lq_empty && sq_empty);

    //test store update forwarding
    @(negedge clock);
    sq_alloc = 1; T = 1;
    @(negedge clock);
    T = 3;
    @(negedge clock);
    sq_alloc = 0; lq_alloc = 1; T = 4;
    @(negedge clock);  T = 5;
    @(negedge clock);
    lq_alloc = 0;

    load_X = 1;
    S_X_load.V1 = 32'h2000;
    S_X_load.mem_offset = 0;
    S_X_load.mem_size = 2'b10;
    S_X_load.rd_unsigned = 0;
    S_X_load.T = 5;

    //should forward to T = 5

    store_X = 1;
    S_X_store.V1 = 32'h2000;
    S_X_store.mem_offset = 0;
    S_X_store.V2 = 32'hdeadbeef;
    S_X_store.mem_size = 2'b10;
    S_X_store.rd_unsigned = 0;
    S_X_store.T = 3;

    @(posedge clock); #1;
    print_lsq();
    //check("Forwarded correctly", load_fwd_packet[0].valid && load_fwd_packet[0].result == 32'hdeadbeef && load_fwd_packet[0].T == 5);


    // MULTIPLE THINGS AT ONCE TEST
    
    
    $display("----- LSQ Testbench Complete -----");
    $finish;
  end

endmodule