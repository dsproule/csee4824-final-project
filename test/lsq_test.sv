`timescale 1ns / 1ps
`include "verilog/sys_defs.svh"

module lsq_tb;

  logic clock = 0, reset;
  logic sq_alloc, lq_alloc;
  ROB_T T, retire_T;
  logic store_X, load_X, retire_en;
  S_X_PACKET S_X_store, S_X_load;

  X_C_PACKET load_fwd_packet;
  logic [`XLEN-1:0] proc2Dmem_addr_store, proc2Dmem_data_store;
  MEM_ACCESS mem_access_store;
  ROB_T store_T;

  logic [`XLEN-1:0] proc2Dmem_addr_load;
  MEM_ACCESS mem_access_load;
  ROB_T load_T;

  logic mem_write_en, mem_read_en;
  logic sq_full, sq_empty, lq_full, lq_empty;

  lsq dut (
    .clock(clock), .reset(reset),
    .sq_alloc(sq_alloc), .lq_alloc(lq_alloc),
    .T(T),
    .S_X_store(S_X_store), .S_X_load(S_X_load),
    .store_X(store_X), .load_X(load_X),
    .retire_T(retire_T), .retire_en(retire_en),
    .load_fwd_packet(load_fwd_packet),
    .mem_write_en(mem_write_en),
    .proc2Dmem_addr_store(proc2Dmem_addr_store),
    .proc2Dmem_data_store(proc2Dmem_data_store),
    .mem_access_store(mem_access_store),
    .store_T(store_T),
    .proc2Dmem_addr_load(proc2Dmem_addr_load),
    .mem_access_load(mem_access_load),
    .mem_read_en(mem_read_en),
    .load_T(load_T),
    .sq_full(sq_full), .sq_empty(sq_empty), .lq_full(lq_full), .lq_empty(lq_empty)
  );

  always #5 clock = ~clock;
  int clock_count = 0;
  always @(posedge clock) clock_count++;

  

 task print_sq;
    $display("\n(SQ_TABLE) full: %1b empty: %1b head: %d tail: %d \ttime: %0d", sq_full, sq_empty, dut.sq_head, dut.sq_tail, clock_count);
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
    $display("\n(LQ_TABLE) full: %1b empty: %1b head: %d tail: %d  \ttime: %0d", lq_full, lq_empty, dut.lq_head, dut.sq_tail, clock_count);
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

  task check(input string msg, input logic cond);
    if (!cond) begin
      $display("ERROR at cycle %0t: %s", clock_count, msg);
      print_lsq();
      $finish;
    end else begin
      $display("PASS at cycle %0t: %s", clock_count, msg);
    end
  endtask

  initial begin
    $display("----- LSQ Testbench Start -----");
    reset = 1; @(negedge clock); reset = 0;

    // === Basic forwarding case ===
    @(negedge clock); sq_alloc = 1; T = 1;
    @(negedge clock); sq_alloc = 0; store_X = 1;
    S_X_store = '{T:1, V1:32'h1000, mem_offset:0, V2:32'hCAFEFEED, mem_size:2'b10, rd_unsigned:0, default:0};
    @(negedge clock); store_X = 0;

    @(negedge clock); lq_alloc = 1; T = 2;
    @(negedge clock); lq_alloc = 0;
    @(negedge clock); load_X = 1;
    S_X_load = '{T:2, V1:32'h1000, mem_offset:0, mem_size:2'b10, rd_unsigned:0, default:0};
    @(negedge clock); load_X = 0;

    @(posedge clock); #1;
    check("Basic Forward Appears", load_fwd_packet.valid && load_fwd_packet.result == 32'hCAFEFEED);

    @(negedge clock); retire_T = 1; retire_en = 1;
    @(posedge clock); #1;
    retire_en = 0;
    check("Basic Store Committed", mem_write_en && proc2Dmem_data_store == 32'hCAFEFEED);
    check("Queue empty after commit", lq_empty && sq_empty);

    // === Dependent forwarding: store writes late ===
    @(negedge clock); sq_alloc = 1; T = 2;
    @(negedge clock); T = 3;
    @(negedge clock); sq_alloc = 0;
    @(negedge clock); lq_alloc = 1; T = 4;
    @(negedge clock); lq_alloc = 0;
    @(negedge clock); load_X = 1;
    S_X_load = '{T:4, V1:32'h2000, mem_offset:0, mem_size:2'b10, rd_unsigned:0, default:0};
    @(negedge clock); load_X = 0;

    @(negedge clock); store_X = 1;
    S_X_store = '{T:2, V1:32'h2000, mem_offset:0, V2:32'hDEADBEEF, mem_size:2'b10, rd_unsigned:0, default:0};
    
    @(posedge clock); #1;
    check("Forward Does Not Appear Early", !load_fwd_packet.valid);

    @(negedge clock); S_X_store = '{T:3, V1:32'h3000, mem_offset:0, V2:32'hBAADBAAD, mem_size:2'b10, rd_unsigned:0, default:0};
    @(posedge clock); #1;
    store_X = 0;
    check("Delayed Forward Appears", load_fwd_packet.valid && load_fwd_packet.result == 32'hDEADBEEF && !mem_write_en);

    @(negedge clock); retire_T = 2; retire_en = 1;
    @(posedge clock); #1;
    retire_en = 0;
    check("Delayed Store Committed", mem_write_en && proc2Dmem_data_store == 32'hDEADBEEF && !load_fwd_packet.valid);
    
    @(negedge clock); lq_alloc = 1; T = 6;

    @(negedge clock); lq_alloc = 0; load_X = 1;
    S_X_load = '{T:6, V1:32'h1238, mem_offset:0, mem_size:2'b10, rd_unsigned:0, default:0};
    @(negedge clock); retire_T = 6; retire_en = 1; load_X = 0;
    @(posedge clock); #1;
    check("Load Cache Req", mem_read_en && proc2Dmem_addr_load == 32'h1238);
    
    @(negedge clock); retire_T = 3;
    @(posedge clock); #1;
    retire_en = 0;
    check("Final Empty State", lq_empty && sq_empty);

    $display("----- LSQ Testbench Complete -----");
    $finish;
  end
endmodule
