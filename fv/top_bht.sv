`include "sys_defs.svh"

module top_bht;

  logic clock;
  logic reset;

  // ---- BHT inputs (adjust names to match BHT.sv) ----
  logic [`XLEN-1:0] pc;
  logic update_en;
  logic update_take_branch;

  // ---- BHT outputs/internal ----
  // If BHT has an output prediction counter/state, declare it here
  // Example:
  // logic [1:0] bht_state;

  // Instantiate BHT (adjust port names!)
  BHT dut (
    .clock(clock),
    .reset(reset),
    .pc(pc),
    .update_en(update_en),
    .update_take_branch(update_take_branch)
    // .state(bht_state)  // if it exists
  );

  // Keep the same PC so we update the same entry
  assume property (@(posedge clock) !reset |-> $stable(pc));
  assume property (@(posedge clock) pc[1:0] == 2'b00);
  assume property (@(posedge clock) reset |-> !update_en);

  // ------------------------------------------------------------
  // BHT Saturation Temporal Checks
  // NOTE: Replace dut.<counter_signal> with actual 2-bit counter
  // ------------------------------------------------------------

  // Cover: saturate to 2'b11 after repeated taken updates
  cover property (@(posedge clock)
    !reset &&
    (update_en && update_take_branch) ##1
    (update_en && update_take_branch) ##1
    (update_en && update_take_branch) ##1
    (dut.counter == 2'b11)
  );

  // Assert: once at 2'b11, further taken updates keep it at 2'b11
  assert property (@(posedge clock)
    !reset && (dut.counter == 2'b11) && update_en && update_take_branch
    |=> (dut.counter == 2'b11)
  );

  // Cover: saturate to 2'b00 after repeated not-taken updates
  cover property (@(posedge clock)
    !reset &&
    (update_en && !update_take_branch) ##1
    (update_en && !update_take_branch) ##1
    (update_en && !update_take_branch) ##1
    (dut.counter == 2'b00)
  );

  // Assert: once at 2'b00, further not-taken keeps it at 2'b00
  assert property (@(posedge clock)
    !reset && (dut.counter == 2'b00) && update_en && !update_take_branch
    |=> (dut.counter == 2'b00)
  );

endmodule

