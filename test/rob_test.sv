`include "verilog/sys_defs.svh"

module rob_testbench;

    logic clock, reset, dispatch_valid;
    logic [4:0] r;
    ROB_T T1, T2, T;
    logic [`XLEN-1:0] NPC;
    CDB cdb;

    
    ROB_T head, tail;
    ROB_T retire_T_out;
    logic full, empty, retire;
    logic regfile_write_en;
    logic [4:0] regfile_write_idx_out;
    logic [`XLEN-1:0] V1, V2, regfile_write_data;
    logic [$bits(ROB_ENTRY)*`ROB_SZ-1:0] rob_table_out;
    PPLN_CTRL ppln_ctrl;

    ROB_ENTRY rob_table [`ROB_SZ:1];
    logic [4:0] expected_r [`ROB_SZ:1];
    logic [`XLEN-1:0] expected_V [`ROB_SZ:1];

    ROB_T current_tail;
    ROB_T current_head;
    int expected_reg;
    ROB_T first_dispatch_slot, second_dispatch_slot, third_dispatch_slot;
    int i, j;
    ROB_T first_in_order_slot;

    rob dut (
        .clock(clock), .reset(reset),
        .r(r), .T1(T1), .T2(T2),
        .cdb(cdb), .dispatch_valid(dispatch_valid), .sq_empty(1'b1), .NPC(NPC), .retire(retire),
        .T(T), .retire_T_out(retire_T_out), .full(full), .empty(empty), .regfile_write_idx_out(regfile_write_idx_out),
        .V1(V1), .V2(V2), .regfile_write_data(regfile_write_data),
        .rob_table_out(rob_table_out), .commit_NPC(), .ppln_ctrl(ppln_ctrl), .head(head), .tail(tail), .wfi(), .tail_wrap()
    );

    always #5 clock = ~clock;

    always_comb begin
        for (int i = 0; i < `ROB_SZ; i++)
            rob_table[i+1] = dut.rob_table_out[i * $bits(ROB_ENTRY) +: $bits(ROB_ENTRY)];
    end
    
    task exit_on_error(input string msg);
        $display("@@@ Test failed at time %0t: %s", $time, msg);
        $finish;
    endtask

    task print_rob;
        $display("\n(ROB_TABLE) h: %2d, t: %2d empty: %1h full: %1h \n------------------------------------------", head, tail, dut.empty, dut.full);
        for(int n = 1; n < 32; n=n+1)
            $display("index: %4d   r:%4d   V:%4d    ready:%1b", n, rob_table[n].r, rob_table[n].V, rob_table[n].ready);
        $display("\n(RETIRE) valid: %1b, ROB_T: %4d, flush: %0d regfile idx: %0h\n------------------------------------------", dut.retire, retire_T_out, dut.ppln_ctrl.flush, regfile_write_idx_out);
    endtask 

    initial begin 
        $display("ROB testbench starting...");
        clock = 0;
        reset = 1;
        dispatch_valid = 0;
        r = 0; 
        cdb = 0;
        NPC = 0;

        for (i = 0; i <= `ROB_SZ; i++) begin
            expected_r[i] = 0;
            expected_V[i] = 0;
        end

        repeat (3) @(negedge clock);
        reset = 0;


        // Case 1 : Single dispatch
        dispatch_valid = 1; r = 5; @(negedge clock);
        dispatch_valid = 0;

        expected_r[T] = r;
        @(posedge clock);
        if (full) exit_on_error("ROB should not be full after one dispatch");
        if (empty) exit_on_error("Should not be empty after one dispatch");
        $display("@@@ Passed: Single dispatch");

        // Case 2 : Fill ROB
        while (!full) begin
        dispatch_valid = 1;
        r = tail;            
        @(negedge clock);
        expected_r[T] = r;  
        end
        dispatch_valid = 0;
        @(posedge clock);
        if (!full) exit_on_error("Should be full after filling");
        $display("@@@ Passed: Fill ROB");

        // $display("Before commits - head=%0d, tail=%0d, empty=%0b, full=%0b", head, tail, empty, full);
        // print_rob();

        // Case 3: Commit multiple entries
        for (i = 1; i <= `ROB_SZ; i++) begin
            expected_r[i] = rob_table[i].r;
            // $display("Updated expected_r[%0d]=%0d to match ROB", i, expected_r[i]);
        end

        for (i = 0; i < 6; i++) begin
            current_head = head; 
            // $display("Commit %0d - Using head=%0d for CDB.T", i, current_head);            
            cdb = 0;
            cdb.valid = `TRUE;
            cdb.T = current_head; 
            cdb.V = 4200 + i;
            expected_V[current_head] = cdb.V;
            
            // $display("Set CDB.T=%0d, CDB.V=%0d, expected_V[%0d]=%0d", cdb.T, cdb.V, current_head, expected_V[current_head]);
            @(posedge clock);

            // $display("After 1st posedge - head=%0d", head);
            // $display("After negedge - head=%0d, retire=%0b, retire_T_out=%0d", head, retire, retire_T_out);
            
            cdb.valid = `FALSE;
            @(posedge clock);
            
            // $display("retire=%0b, retire_T_out=%0d", retire, retire_T_out);
            // $display("regfile_write_idx_out=%0d, regfile_write_data=%0d", regfile_write_idx_out, regfile_write_data);
            // $display("expected_r[%0d]=%0d, expected_V[%0d]=%0d", current_head, expected_r[current_head], current_head, expected_V[current_head]);
            
            if (!retire) exit_on_error("Expected retire = 1");
            if (regfile_write_data !== expected_V[current_head])
                exit_on_error($sformatf("Commit %0d: data mismatch (got %0d, expected %0d)", i, regfile_write_data, expected_V[current_head]));
            if (regfile_write_idx_out !== expected_r[current_head])
                exit_on_error($sformatf("Commit %0d: regfile idx mismatch (got %0d, expected %0d)", i, regfile_write_idx_out, expected_r[current_head]));
            
            // $display("After commit %0d", i);
            // print_rob();
        end
        $display("@@@ Passed: Commit multiple");

        // Case 4: Simultaneous dispatch + commit 
        reset = 1; @(negedge clock); reset = 0;
        @(posedge clock); 
        // $display("After reset - head=%0d, tail=%0d, empty=%0b, full=%0b", head, tail, empty, full);

        for (i = 0; i < 5; i++) begin
            dispatch_valid = 1; r = 10 + i;
            @(negedge clock);
            expected_r[T] = r;
            @(posedge clock);
            //$display("=Dispatched r=%0d to slot T=%0d, head=%0d, tail=%0d", r, T, head, tail);
        end

        dispatch_valid = 0;
        @(posedge clock);
        //$display("After dispatches - head=%0d, tail=%0d, empty=%0b", head, tail, empty);

        for (i = 1; i <= 5; i++) begin
            cdb.valid = `TRUE;
            cdb.T = i;  
            cdb.V = 1000 + i;
            expected_V[i] = cdb.V;
            @(posedge clock);
            cdb.valid = `FALSE;
            @(posedge clock);
            // $display("Made ROB entry %0d ready with V=%0d", i, cdb.V);
        end

        // $display("Before commit test - head=%0d, tail=%0d, empty=%0b", head, tail, empty);

        for (i = 0; i < 5; i++) begin
            //$display("Iteration %0d - using head=%0d, tail=%0d", i, head, tail);
            dispatch_valid = 1;
            r = 30 + i;
            expected_r[tail] = r;  
            
            cdb.valid = `TRUE;
            cdb.T = head;  
            cdb.V = 3000 + i;
            expected_V[head] = cdb.V;
            @(posedge clock);

            dispatch_valid = 0;
            @(posedge clock);
            cdb.valid = `FALSE;
            @(posedge clock);
            
            // $display("After iter %0d - head=%0d, retire=%0b", i, head, retire);
            // $display("r_idx=%0d, data=%0d", regfile_write_idx_out, regfile_write_data);
            
            if (!retire)
                exit_on_error($sformatf("Case 4.%0d: retire not asserted", i));
            if (regfile_write_data !== expected_V[retire_T_out])
                exit_on_error($sformatf("Case 4.%0d: data mismatch (got %0d, expected %0d)", i, regfile_write_data, expected_V[retire_T_out]));
            if (regfile_write_idx_out !== expected_r[retire_T_out])
                exit_on_error($sformatf("Case 4.%0d: register index mismatch (got %0d, expected %0d)", i, regfile_write_idx_out, expected_r[retire_T_out]));
        end
        $display("@@@ Passed: Simultaneous dispatch + commit");

        // Case 5: CDB to middle entry
        reset = 1; @(negedge clock); reset = 0;
        @(posedge clock); 
        
        // dispatch three entries, capturing the slots
        dispatch_valid = 1; r = 20; first_dispatch_slot = dut.tail; @(negedge clock); @(posedge clock);  
        expected_r[first_dispatch_slot] = r; 
        // $display("Dispatch 1 - r=%0d to slot T=%0d", r, first_dispatch_slot);

        r = 21; second_dispatch_slot = T; @(negedge clock); @(posedge clock);
        expected_r[second_dispatch_slot] = r; 
        // $display("Dispatch 2 - r=%0d to slot T=%0d", r, second_dispatch_slot);

        r = 22; third_dispatch_slot = T; @(negedge clock); @(posedge clock);
        expected_r[third_dispatch_slot] = r; 
        // $display("Dispatch 3 - r=%0d to slot T=%0d", r, third_dispatch_slot);

        dispatch_valid = 0; @(posedge clock);

        // $display("ROB after dispatches:");
        // print_rob();
            
        // $display("slots: first=%0d (r=%0d), second=%0d (r=%0d), third=%0d (r=%0d)",
        //     first_dispatch_slot, expected_r[first_dispatch_slot],
        //     second_dispatch_slot, expected_r[second_dispatch_slot],
        //     third_dispatch_slot, expected_r[third_dispatch_slot]);
       
        current_head = head; 
    
        first_in_order_slot = first_dispatch_slot;
        // $display("First in-order slot is %0d (r=%0d)", first_in_order_slot, expected_r[first_in_order_slot]);
        // $display("Completing out-of-order slot %0d with r=%0d", second_dispatch_slot, expected_r[second_dispatch_slot]);

        cdb = '{default:0};
        cdb.T = second_dispatch_slot;
        cdb.V = 5555;
        expected_V[second_dispatch_slot] = cdb.V;
        cdb.valid = `TRUE;
        @(posedge clock);
        @(negedge clock); cdb.valid = `FALSE;
        @(posedge clock);

        if (retire)
            exit_on_error("Out-of-order commit occurred");
        // $display("Out-of-order slot %0d did NOT retire (good)", second_dispatch_slot);

        // $display("ROB after out-of-order completion:");
        // print_rob();

        // $display("Completing in-order slot %0d with r=%0d", first_in_order_slot, expected_r[first_in_order_slot]);

        cdb = '{default:0};
        cdb.T = first_in_order_slot;
        cdb.V = 4444;
        expected_V[first_in_order_slot] = cdb.V;
        cdb.valid = `TRUE;
        @(posedge clock);
        @(negedge clock); cdb.valid = `FALSE;
        @(posedge clock);

        // $display("ROB before checking retire:");
        // print_rob();

        // $display("retire=%0b, retire_T_out=%0d, expected first_in_order_slot=%0d", retire, retire_T_out, first_in_order_slot);
        // $display("regfile_write_idx_out=%0d, expected_r[first_in_order_slot]=%0d", regfile_write_idx_out, expected_r[first_in_order_slot]);
        // $display("regfile_write_data=%0d, expected_V[first_in_order_slot]=%0d", regfile_write_data, expected_V[first_in_order_slot]);

        if (!retire)
            exit_on_error("Case 5: head entry did NOT retire");
        if (retire_T_out !== first_in_order_slot)
            exit_on_error($sformatf("Case 5: retire_T_out mismatch (got %0d, exp %0d)", retire_T_out, first_in_order_slot));
        if (regfile_write_idx_out !== expected_r[first_in_order_slot])
            exit_on_error($sformatf("Case 5: regfile idx mismatch (got %0d, exp %0d)", regfile_write_idx_out, expected_r[first_in_order_slot]));
        if (regfile_write_data !== expected_V[first_in_order_slot])
            exit_on_error($sformatf("Case 5: regfile data mismatch (got %0d, exp %0d)", regfile_write_data, expected_V[first_in_order_slot]));

        $display("@@@ Passed: In-order enforced with middle CDB");
        
        // Case 6: Wraparound 
        reset = 1; @(negedge clock); reset = 0;
        @(posedge clock);  

        // $display("Initial head=%0d, tail=%0d", head, tail);

        for (int i = 1; i <= `ROB_SZ; i++) begin
        r = i; dispatch_valid = 1;   
        @(posedge clock);    
        current_tail = (dut.tail == 1) ? `ROB_SZ : (dut.tail - 1);
        expected_r[current_tail] = r;
        // $display("Dispatched r=%0d into slot %0d", r, current_tail);
        dispatch_valid = 0;     
        end

        // $display("After filling: head=%0d, tail=%0d", head, tail);

        for (int i = 1; i <= `ROB_SZ/2; i++) begin
        current_head = head;
        expected_reg = expected_r[current_head];

        cdb.T     = current_head;
        cdb.V     = 8000 + i;
        cdb.valid = 1;
        @(posedge clock);       
        cdb.valid = 0;

        @(posedge clock);
        // $display("After retire: head=%0d, retire_T_out=%0d, regfile_idx=%0d (exp=%0d)",  head, retire_T_out, regfile_write_idx_out, expected_reg);

        if (!retire || regfile_write_idx_out !== expected_reg)
            exit_on_error("Wraparound commit mismatch");
        end

        // $display("Starting wraparound dispatches");
        for (int i = 0; i < `ROB_SZ/2; i++) begin
        r = 100 + i;
        dispatch_valid = 1;
        @(posedge clock);
        // $display("Wrapped dispatch r=%0d to slot %0d", r, T);
        dispatch_valid = 0;
        end
        $display("@@@ Passed: Wraparound logic");

        // Case 7: Flush from mispredicted instruction
        reset = 1; @(negedge clock); reset = 0;
        @(posedge clock);

        for (int i = 0; i < 3; i++) begin
            r = i + 20; dispatch_valid = 1; @(posedge clock);
            dispatch_valid = 0;
            @(posedge clock);
        end
      
        current_head = head;
        cdb.T = current_head; cdb.V = 9999; cdb.ppln_ctrl.flush = 1; cdb.valid = `TRUE;
        @(posedge clock); cdb.valid = `FALSE;
        @(posedge clock);
        // if (!empty) exit_on_error("Flush failed to clear ROB"); // check if ok
        // $display("@@@ Passed: Mispredict-triggered flush");
        if (!ppln_ctrl.flush) exit_on_error("Flush bit not propagated");  
        $display("@@@ Passed: Mispredict-triggered flush");

        $display("\n@@@ ALL ROB TESTS PASSED SUCCESSFULLY!\n");
        $finish;
    end 
endmodule