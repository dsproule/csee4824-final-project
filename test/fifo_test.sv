`timescale 1ns/1ps

module fifo_tb;

    // Parameters
    parameter DataWidth = 32;
    parameter Depth = 8;
    
    // Testbench Signals
    logic clock;
    logic reset;
    logic write_en;
    logic [DataWidth-1:0] write_data;
    logic read_en;
    logic [DataWidth-1:0] read_data;
    logic full;
    logic empty;

    // Instantiate the FIFO
    fifo #(.DataWidth(DataWidth), .Depth(Depth)) dut (
        .clock(clock),
        .reset(reset),
        .write_en(write_en),
        .write_data(write_data),
        .read_en(read_en),
        .read_data(read_data),
        .full(full),
        .empty(empty)
    );

    // Generate Clock
    always #5 clock = ~clock;  // 10ns period

    // Display FIFO state
    task check_fifo_state();
        $display("Time: %t | Write: %b (%d) | Read: %b (%d) | Full: %b | Empty: %b", 
                 $time, write_en, write_data, read_en, read_data, full, empty);
    endtask

    initial begin
        $display("Starting FIFO Testbench...");

        // Initialize signals
        clock = 0;
        reset = 1;
        write_en = 0;
        write_data = 0;
        read_en = 0;

        // Apply Reset
        #10 reset = 0;
        $display("\nTest 1: Reset");
        check_fifo_state();
        if (!empty) begin
            $display("ERROR: FIFO should be empty after reset.");
            $finish;
        end
        $display("Passed Reset Test\n");

        // Test 2: Write to FIFO Until Full
        $display("Test 2: Writing to FIFO");
        for (int i = 1; i <= Depth; i++) begin
            if (!full) begin
                write_data = i;
                write_en = 1;
                #10;
                check_fifo_state();
            end
        end
        write_en = 0;

        if (!full) begin
            $display("ERROR: FIFO should be full after %d writes.", Depth);
            $finish;
        end
        $display("Passed Write Test\n");

        // Test 3: Read from FIFO Until Empty
        $display("Test 3: Reading from FIFO");
        for (int i = 1; i <= Depth; i++) begin
            if (!empty) begin
                read_en = 1;
                #10;
                check_fifo_state();
            end
        end
        read_en = 0;

        if (!empty) begin
            $display("ERROR: FIFO should be empty after %d reads.", Depth);
            $finish;
        end
        $display("Passed Read Test\n");

        $display("\nAll Tests Passed.");
        $finish;
    end

endmodule
