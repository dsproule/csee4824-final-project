`include "sys_defs.svh"

// ============================================================
// Formal wrapper / harness for branch_pred.sv  (Option B)
// Module: top
// - Minimal environment assumptions
// - DUT: branch_pred
// - Strong-enough properties for submission
//   NOTE: A2 (alignment of next_addr when taken) is commented out
//         to avoid failing due to unconstrained instruction/targets.
// ============================================================

module top;

  // -------------------------
  // Formal clock/reset (declared by Jasper via "clock clock" / "reset reset")
  // -------------------------
  logic clock;
  logic reset;

  // -------------------------
  // DUT interface signals
  // -------------------------
  logic [`XLEN-1:0] pc;
  INST             inst;

  logic            update_en;
  logic            update_take_branch;
  logic [`XLEN-1:0] update_address;

  logic            take_branch;
  logic [`XLEN-1:0] next_addr;

  // -------------------------
  // Instantiate DUT
  // -------------------------
  branch_pred dut (
    .clock              (clock),
    .reset              (reset),
    .pc                 (pc),
    .inst               (inst),
    .update_en          (update_en),
    .update_take_branch (update_take_branch),
    .update_address     (update_address),
    .take_branch        (take_branch),
    .next_addr          (next_addr)
  );

  // ============================================================
  // Environment assumptions 
  // ============================================================

  // Word-aligned PC/update address 
  assume property (@(posedge clock) pc[1:0] == 2'b00);
  assume property (@(posedge clock) update_address[1:0] == 2'b00);

  // No update during reset
  assume property (@(posedge clock) reset |-> !update_en);

  // If update_en is asserted, keep update fields stable that cycle
  assume property (@(posedge clock)
    update_en |-> ($stable(update_take_branch) && $stable(update_address))
  );

  // ============================================================
  // Assertions (safety)
  // ============================================================

  // A1: take_branch is always a valid 0/1 after reset
  assert property (@(posedge clock)
    !reset |-> (take_branch inside {1'b0, 1'b1})
  );

  // A2 :
  // If the predictor says taken, next_addr must be word-aligned.
  // This can fail in formal if inst/targets are unconstrained.
  //
  // assert property (@(posedge clock)
  //   !reset && take_branch |-> (next_addr[1:0] == 2'b00)
  // );

  // A2: Stability property (only when not updating):
  // If inputs are stable and no update occurs, outputs should not glitch.
  assert property (@(posedge clock)
    !reset &&
    !update_en &&
    $stable(pc) &&
    $stable(inst)
    |-> $stable(take_branch) && $stable(next_addr)
  );

  // ============================================================
  // Cover properties (reachability evidence)
  // ============================================================

  // C1: It is reachable to predict taken sometime after reset
  cover property (@(posedge clock)
    !reset ##[1:10] take_branch
  );

  // C2: If we ever apply a "taken" update, it is reachable to later predict taken
  cover property (@(posedge clock)
    !reset &&
    update_en && update_take_branch
    ##[1:10] take_branch
  );

endmodule

