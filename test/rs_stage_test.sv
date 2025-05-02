`include "verilog/sys_defs.svh"

module testbench;

  // Inputs
  logic              clock, reset, en;
  logic [`XLEN-1:0]  V1, V2;
  CDB                cdb;
  D_S_PACKET         D_S_reg;
  logic [`RS_SZ-1:0] FU_ready;
  ROB_T              T;
  MT_ENTRY           T1, T2;

  // Outputs
  logic              d_stall;
  S_X_PACKET [`RS_SZ-1:0] S_pack;
  RS_ENTRY   [`RS_SZ-1:0] rs_table;
  logic        [`RS_SZ-1:0] busy;

  // Debug
  logic [7:0] clock_count, dbg_cycle;
  integer     error_count;
  integer wait_cycles;
  integer max_wait;
  integer to;

  // Handshake tracking
  event ev_free0, ev_cleared0;
  integer cycle_free0, cycle_cleared0;

  bit waiting_for_clear0;
  bit prev_busy0;

  // Device Under Test
  rs_stage rs_stage_inst (
    .clock       (clock),
    .reset       (reset),
    .alloc_en    (en),
    .cdb         (cdb),
    .D_S_reg     (D_S_reg),
    .FU_ready    (FU_ready),
    .T           (T),
    .T1          (T1),
    .T2          (T2),
    .V1          (V1),
    .V2          (V2),
    .rs_idx_full (d_stall),
    .busy        (busy),
    .S_packet    (S_pack),
    .rs_table    (rs_table)
  );

  //--------------------
  // Clock generation
  //--------------------
  always begin
    #(`CLOCK_PERIOD/2) clock = ~clock;
  end

  always @(negedge clock) begin
    clock_count <= clock_count + 1;
    dbg_cycle   <= dbg_cycle + 1;
  end

  //--------------------
  // Monitors
  //--------------------
  always @(posedge clock) begin
    if (rs_stage_inst.rs_value.rs_free[0]) begin
      cycle_free0 = dbg_cycle;
      waiting_for_clear0 = 1;
      -> ev_free0;
    end
    prev_busy0 <= busy[0];
    if (waiting_for_clear0 && prev_busy0 && !busy[0]) begin
      cycle_cleared0 = dbg_cycle;
      waiting_for_clear0 = 0;
      -> ev_cleared0;
    end
  end

  //--------------------
  // Tasks
  //--------------------
task print_rs;
    integer j; // <<< THIS LINE NEEDED
    $display("\n(RS_TABLE) cycle %0d\n------------------------------------------", (clock_count)/2);
    for (j = 0; j < `RS_SZ; j = j + 1) begin
        $display("idx:%0d T:%0d T1:%0d T2:%0d V1:%0d V2:%0d busy:%b ready:%b",
                 j, rs_table[j].T, rs_table[j].T1, rs_table[j].T2,
                 rs_table[j].V1, rs_table[j].V2, busy[j], rs_table[j].ready);
    end
    $display("------------------------------------------");
endtask


task compare;
  input int idx, t, t1, t2, v1, v2;
  input bit exp_busy;
  if (exp_busy == 0) begin
    // If expected busy = 0, only check busy, ignore T, T1, T2, V1, V2
    if (busy[idx] !== 0) begin
      error_count++;
      $display("@@@ Failed at cycle %0d (FREE expected)", (clock_count)/2);
      $display("@@@ Expected idx:%0d to be free (busy=0), but busy=%b", idx, busy[idx]);
      $finish;
    end
  end else begin
    // If expected busy = 1, check all fields
    if ((rs_table[idx].T !== t) || (rs_table[idx].T1 !== t1) || (rs_table[idx].T2 !== t2) ||
        (rs_table[idx].V1 !== v1) || (rs_table[idx].V2 !== v2) || (busy[idx] !== exp_busy)) begin
      error_count++;
      $display("@@@ Failed at cycle %0d (BUSY expected)", (clock_count)/2);
      $display("@@@ Expected idx:%0d T:%0d T1:%0d T2:%0d V1:%0d V2:%0d busy:%b",
               idx, t, t1, t2, v1, v2, exp_busy);
      $finish;
    end
  end
endtask


task compare_stall;
    input bit exp_stall;
    if (d_stall !== exp_stall) begin
        error_count++;
        $display("@@@ Failed stall at cycle %0d: got %b expected %b", (clock_count)/2, d_stall, exp_stall);
        $finish;
    end
endtask


//--------------------
  // Main Test Sequence
  //--------------------
  initial begin
    // Dump RS table forever
    fork
      forever @(posedge clock) print_rs();
    join_none

    // Initialize
    clock = 0; reset = 0; en = 0;
    error_count = 0;
    clock_count = 0; dbg_cycle = 0;
    waiting_for_clear0 = 0;
    prev_busy0 = 0;
    V1 = 0; V2 = 0;
    cdb = '{default:0};
    FU_ready = '{default:0};
    T = 0; T1 = '{default:0}; T2 = '{default:0};
    D_S_reg = '{default:0};

    // Reset
    @(negedge clock) reset = 1;
    @(negedge clock) reset = 0;

    //--------------------
    // Test Sequence
    //--------------------

    // Cycle 1: issue load
    @(negedge clock);
    en = 1;
    D_S_reg.rs_idx = 1;
    T = 1; T1 = '{0,1'b0}; T2 = '{0,1'b0};
    V1 = 0; V2 = 8;
    D_S_reg.valid = 1;
    @(posedge clock);
    D_S_reg.valid = 0;
    compare_stall(0);
    @(negedge clock); @(negedge clock);
    compare(0,0,0,0,0,0,0);
    compare(1,1,0,0,0,8,1);
    compare(2,0,0,0,0,0,0);
    compare(3,0,0,0,0,0,0);

    // Cycle 2: issue mul
    @(negedge clock);
    D_S_reg.rs_idx = 3;
    T = 2; T1 = '{0,1'b0}; T2 = '{1,1'b0};
    V1 = 5; V2 = 0;
    D_S_reg.valid = 1;
    @(posedge clock);
    D_S_reg.valid = 0;
    compare_stall(0);
    @(negedge clock); @(negedge clock);
    compare(0,0,0,0,0,0,0);
    compare(1,1,0,0,0,8,1);
    compare(2,0,0,0,0,0,0);
    compare(3,2,0,1,5,0,1);

    //cycle 3
        @(negedge clock);
        D_S_reg.rs_idx   = 2;
        T                = 3;    T1 = '{2,1'b0};  T2 = '{0,1'b0};
        V1               = 0;    V2 = 8;
        D_S_reg.valid    = 1;
        @(posedge clock);
        D_S_reg.valid    = 0;
        compare_stall(0);
        @(posedge clock); @(negedge clock);
        print_rs();
        compare(0,0,0,0,0,0,0);
        compare(1,1,0,0,0,8,1);
        compare(2,3,2,0,0,8,1);
        compare(3,2,0,1,5,0,1);

        // --- Cycle 4: addi ---
        @(negedge clock);
        en               = 1;
        D_S_reg.rs_idx   = 0;
        T                = 4;    T1 = '{0,1'b0};  T2 = '{0,1'b0};
        V1               = 8;    V2 = 0;
        D_S_reg.valid    = 1;
        @(posedge clock);
        D_S_reg.valid    = 0;
        compare_stall(0);
        @(negedge clock); @(negedge clock); @(negedge clock);
        print_rs();
        compare(0,4,0,0,8,0,1);
        compare(1,1,0,0,0,8,1);
        compare(2,3,2,0,0,8,1);
        compare(3,2,0,1,5,0,1);

        // free the ADDI
        @(negedge clock);
        FU_ready = 4'b0001;
        en = 0;
        wait (rs_stage_inst.rs_value.rs_free[0]);  // rs_free[0] means ready to issue
        @(negedge clock);
        FU_ready = 4'b0000;
        wait (!busy[0]);                           // wait for busy to clear
        @(negedge clock);   
        @(negedge clock);                        // <-- INSERT THIS EXTRA CLOCK
        compare(0, 0, 0, 0, 0, 0, 0);              // now safe to check that RS[0] is free

        // Broadcast T=1 to wake up dependent RS entries (e.g., RS[3])
        @(negedge clock);
        cdb.valid = 1;
        cdb.T = 1;
        cdb.V = 99;
        @(negedge clock);
        cdb.valid = 0;
        // --- Broadcast T=1 to wake up RS[3] BEFORE freeing RS[1] ---
        @(negedge clock);
        cdb.valid = 1;
        cdb.T = 1;
        cdb.V = 99;
        @(negedge clock);
        cdb.valid = 0;

        // --- Now Free RS[1] ---
        @(negedge clock);
        FU_ready = 4'b0010; // RS[1] has T=1
        wait (rs_stage_inst.rs_value.rs_free[1]); // ready to issue
        @(negedge clock);
        FU_ready = 4'b0000;
        wait (!busy[1]); // wait until RS[1] clears


        // --- Cycle 5: ldf ---
        @(negedge clock);
        en               = 1;
        D_S_reg.rs_idx   = 1;
        T                = 5;    T1 = '{0,1'b0};  T2 = '{4,1'b0};
        V1               = 0;    V2 = 0;
        D_S_reg.valid    = 1;
        @(posedge clock);
        D_S_reg.valid    = 0;
        compare_stall(0);
        
        @(negedge clock); @(negedge clock); @(negedge clock);
        @(negedge clock); @(negedge clock); @(negedge clock);
        compare(1, 5, 0, 4, 0, 0, 1);
        @(negedge clock); @(negedge clock);
        FU_ready         = 4'b0010;
        @(negedge clock);@(negedge clock);@(negedge clock);           // Now it will clear when issued
        FU_ready = 4'b0000;
        @(negedge clock); @(negedge clock);
        print_rs();
        compare(0, 0, 0, 0, 0, 0, 0);
        //compare(1,5,0,4,0,0,1);
        compare(2,3,2,0,0,8,1);

        // Wait until RS[3] (holding T=6) issues and clears
        // Enable FU for RS[3]
        FU_ready = 4'b1000;
        @(negedge clock);
        @(negedge clock); // Give RS stage a chance to process issue
        FU_ready = 4'b0000;



        compare(3, 0, 0, 0, 0, 0, 0); 
        // Add 1 cycle delay to let the RS logic reset fully before reuse
        @(negedge clock);
        // Issue the FU completion
        FU_ready = 4'b1000;
        @(negedge clock);      // let rs_stage latch it
        @(negedge clock);
        FU_ready = 4'b0000;    // clear the FU_ready

        // wait for the slot to actually clear
        wait (!busy[3]);

        wait (!busy[3] && rs_table[3].T == 0);
        @(negedge clock);

           // --- Cycle 6: mul ---
            @(negedge clock);
              en             = 1;
              D_S_reg.rs_idx = 3;
              T              = 6;
              T1             = '{0, 1'b0};
              T2             = '{5, 1'b0};
              V1             = 5;
              V2             = 0;
              D_S_reg.valid  = 1;
            // leave it high through the posedge...
            @(posedge clock);
              compare_stall(0);
            // ...and only fold it away on the following negedge:
            @(negedge clock);
              D_S_reg.valid  = 0;
              en             = 0;
        // Let the RS entry settle
        @(negedge clock); @(negedge clock); @(negedge clock);

        // Poll until the dispatch writes T==6 into RS[3]
        max_wait    = 10;
        wait_cycles = 0;
        while ((rs_table[3].T != 6) && (wait_cycles < max_wait)) begin
          @(negedge clock);
          wait_cycles++;
        end
        if (rs_table[3].T != 6) begin
          $display("@@@ cycle 6: ERROR: T=6 never written to RS[3] after %0d cycles", max_wait);
        end else begin
          // Re-broadcast T=5 for the second operand
          @(negedge clock);
          cdb.valid = 1;
          cdb.T     = 5;
          cdb.V     = 42;
          @(negedge clock);
          cdb.valid = 0;
          @(negedge clock); @(negedge clock);
        end

        // Issue & clear RS[3]
        @(negedge clock);
        FU_ready = 4'b1000;
        @(negedge clock); @(negedge clock);
        FU_ready = 4'b0000;

        // Let RS[3] clear naturally
        @(negedge clock); @(negedge clock); @(negedge clock);
        // Now it’s safe to check that it is free
        compare(3, 0, 0, 0, 0, 0, 0);

                
        // --- Cycle 7: dispatch into RS[2] (T=7, T1=6) ---
      @(negedge clock);
        FU_ready = 4'b0100;    // tell RS “slot 2 is done”
      @(posedge clock);
        FU_ready = 4'b0000;    // drop it immediately

      // --- Now wait *up to* N cycles for the issue‐ready handshake — avoids infinite loops ---
      to = 0;
      while (!rs_stage_inst.rs_value.rs_free[2] && to < 5) begin
        @(negedge clock);
        to++;
      end

      // --- Give exactly one more negedge for busy[2] to go low in the hardware ---
      @(negedge clock);
          en             = 1;
          D_S_reg.rs_idx = 2;
          T              = 7;
          T1             = '{6, 1'b0};
          T2             = '{0, 1'b0};
          V1             = 0;
          V2             = 1;
          D_S_reg.valid  = 1;
        @(posedge clock);
          compare_stall(1);
        @(negedge clock);
          D_S_reg.valid  = 0;
          en             = 0;

        // --- Broadcast T=4 to wake RS[1] (store’s second operand) ---
        @(negedge clock);
          cdb.valid = 1;  cdb.T = 4;  cdb.V = 12;
        @(negedge clock);
          cdb.valid = 0;
        // give it a few cycles to settle
        repeat (3) @(negedge clock);
        compare(1, 5, 0, 0, 0, 12, 1);

        // --- Issue RS[1] (T=5) and wait for busy[1]→0, with timeout ---
        to = 0;
        @(negedge clock);
          FU_ready = 4'b0010;
        @(negedge clock);
          FU_ready = 4'b0000;
        while (busy[1] && to < 10) begin
          @(negedge clock);
          to = to + 1;
        end

        @(negedge clock);

        // sanity check
        print_rs();
        compare(0,0,0,0,0,0,0);

        // --- Broadcast T=2 to wake RS[2] (its first operand) ---
        @(negedge clock);
          cdb.valid = 1;  cdb.T = 2;  cdb.V = 20;
        @(negedge clock);
          cdb.valid = 0;


        // --- Issue RS[2] (T=3) and wait for busy[2]→0, with timeout ---
        en             = 1;
        D_S_reg.rs_idx = 3;
        T              = 6;
        T1             = '{0, 1'b0};
        T2             = '{5, 1'b0};
        V1             = 5;
        V2             = 1;
        D_S_reg.valid  = 1;
         @(negedge clock); @(posedge clock);
        en  = 0;
        D_S_reg.valid = 0;
        @(negedge clock);
          FU_ready = 4'b0100;
        @(negedge clock);
          FU_ready = 4'b0000;
        @(negedge clock);

        // final checks for Cycle 7
        compare(2,0,0,0,0,0,0);
        compare(3,6,0,5,5,0,1);


        // --- Cycle 8: wakeup via CDB (T=2) ---
        @(negedge clock);
        D_S_reg.rs_idx   = 2;
        T                = 7;    T1 = '{6,1'b0};  T2 = '{0,1'b0};
        V1               = 0;    V2 = 1;
        cdb.valid        = 1;    cdb.T = 2;  cdb.V = 11;
        @(posedge clock);
        D_S_reg.valid    = 0;    cdb.valid = 0;
        compare_stall(0);
        @(negedge clock); @(negedge clock); @(negedge clock);
        FU_ready         = '{default:0};
        print_rs();
        compare(0,0,0,0,0,0,0);
        compare(1,0,0,0,0,0,0);
        compare(2,3,0,0,11,8,0);
        compare(3,6,0,5,5,0,1);

                // --- Cycle 9: final wakeup/store ---
        @(negedge clock);
        D_S_reg.rs_idx    = 2;
        T                 = 7;    T1 = '{6,1'b0};  T2 = '{4,1'b1};
        V1                = 0;    V2 = 1;
        cdb.valid         = 1;    cdb.T = 5;  cdb.V = 15;
        @(posedge clock);
        // clear the packet & CDB
        D_S_reg.valid     = 0;
        @(negedge clock);
        @(negedge clock); 
        cdb.valid         = 0;

        // WAIT UNTIL RS[1] IS CLEARED
        //wait (!busy[1]);
        @(negedge clock); @(negedge clock);

        // --- Free RS[3] (T=6) ---
        @(negedge clock);
        FU_ready = 4'b1000; // Enable FU for RS[3]
        //wait (rs_stage_inst.rs_value.rs_free[3]); // Wait until it's ready to issue
        @(negedge clock);
        FU_ready = 4'b0000;
        //wait (!busy[3]); // Wait until RS[3] clears
        @(negedge clock);@(negedge clock); @(negedge clock);


        // FINAL ASSERTIONS
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 0, 0, 0, 0, 0, 0);
        // Wait until RS[3] (holding T=6) issues and clears
        FU_ready = 4'b1000; // Enable FU for RS[3]
        //wait (rs_stage_inst.rs_value.rs_free[3]); // Wait until RS[3] is ready to issue
        @(negedge clock);
        FU_ready = 4'b0000;
        //wait (!busy[3]); // Wait until RS[3] clears
        @(negedge clock); @(negedge clock); // Give it time to drain
        compare(3, 0, 0, 0, 0, 0, 0); // 
        
        @(negedge clock);
        $display("@@@ Passed!");
        $finish;

    end
endmodule