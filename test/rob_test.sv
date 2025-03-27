`include "verilog/sys_defs.svh"

module rob_tb;
    logic clock, reset, dispatch_valid;
    logic [4:0] r, r1, r2;
    CDB cdb;
    ROB_T T;
    logic full, empty, regfile_write_en;
    logic [4:0] regfile_write_idx;
    logic [`XLEN-1:0] V1, V2, regfile_write_data;
    integer i;

    rob rob_inst (
        .clock(clock), 
        .reset(reset), 
        .r(r), 
        .r1(r1), 
        .r2(r2), 
        .cdb(cdb),
        .dispatch_valid(dispatch_valid), 
        .T(T), 
        .full(full), 
        .empty(empty),
        .regfile_write_en(regfile_write_en), 
        .regfile_write_idx(regfile_write_idx),
        .V1(V1), 
        .V2(V2), 
        .regfile_write_data(regfile_write_data)
    );

    // Clock generation
    always begin
        #(`CLOCK_PERIOD/2.0) clock = ~clock;
    end

    task wait_until_empty;
        while (!empty) @(posedge clock);
    endtask

    initial begin
        $monitor("Time:%4.0f Full:%b Empty:%b Head:%d Tail:%d Write_en:%b Write_idx:%d Write_data:%h",
                 $time, full, empty, rob_inst.head, rob_inst.tail, regfile_write_en, regfile_write_idx, regfile_write_data);
        
        reset = 1; clock = 0; dispatch_valid = 0;
        r = 0; r1 = 0; r2 = 0; cdb.valid = 0; cdb.T = 0; cdb.V = 0;
        #(`CLOCK_PERIOD*2) reset = 0;

        $display("\nStarting ROB tests:\n");

        // Test 1: Dispatch then immediately complete each instruction
        for (i = 0; i < `ROB_SZ; i++) begin
            @(posedge clock);
            dispatch_valid = 1;
            r = $urandom_range(0, 31);
            @(posedge clock);
            dispatch_valid = 0;
            // Immediately mark the dispatched instruction as complete.
            @(posedge clock);
            cdb.valid = 1;
            // Use the just-dispatched tag. This assumes tail-1 gives the correct entry.
            cdb.T = (rob_inst.tail == 0) ? (`ROB_SZ - 1) : rob_inst.tail - 1;
            cdb.V = 'hDEAD_BEEF + cdb.T;
            @(posedge clock);
            cdb.valid = 0;
        end
        wait_until_empty();

        // Test 2: Completing instructions
        for (i = 0; i < `ROB_SZ; i++) begin
            @(posedge clock);
            cdb.valid = 1;
            cdb.T = rob_inst.head;
            cdb.V = 'hABCD0000 + cdb.T;
            @(posedge clock);
            cdb.valid = 0;
        end
        wait_until_empty();

        // Test 3: Interleaved dispatch and complete
        for (i = 0; i < 10; i++) begin
            @(posedge clock);
            dispatch_valid = 1;
            r = $urandom_range(0, 31);
            @(posedge clock);
            dispatch_valid = 0;
            @(posedge clock);
            cdb.valid = 1;
            cdb.T = rob_inst.tail - 1;
            cdb.V = 'h12340000 + cdb.T;
            @(posedge clock);
            cdb.valid = 0;
        end
        wait_until_empty();

        // Test 4: Reset mid-operation
        @(posedge clock); reset = 1;
        @(posedge clock); reset = 0;
        @(posedge clock);
        $display("Time:%4.0f After reset - Head:%d Tail:%d Full:%b Empty:%b", 
                 $time, rob_inst.head, rob_inst.tail, full, empty);

        $display("\n@@@ Passed\n");
        $finish;
    end
endmodule