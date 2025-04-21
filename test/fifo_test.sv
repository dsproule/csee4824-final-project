`timescale 1ns / 1ps

module testbench;

    parameter DataWidth = 8;
    parameter Depth = 4;
    localparam PtrWidth = $clog2(Depth);

    logic clock, reset;
    logic write_en, read_en;
    logic [DataWidth-1:0] write_data;
    logic [DataWidth-1:0] read_data;
    logic full, empty;

    fifo #(.DataWidth(DataWidth), .Depth(Depth)) uut (
        .clock(clock),
        .reset(reset),
        .write_en(write_en),
        .write_data(write_data),
        .read_en(read_en),
        .read_data(read_data),
        .full(full),
        .empty(empty)
    );

    logic [DataWidth-1:0] expected_data [0:Depth-1];
    int write_ptr, read_ptr;

    task automatic check(input [DataWidth-1:0] expected, input [DataWidth-1:0] actual, input string msg);
        if (expected !== actual) begin
            $display("ERROR: %s | Expected: %0d, Got: %0d", msg, expected, actual);
            $finish;
        end
    endtask

    always #5 clock = ~clock;

    initial begin
        $display("Starting FIFO Testbench...");
        clock = 0;
        reset = 1;
        write_en = 0;
        read_en = 0;
        write_data = 0;
        write_ptr = 0;
        read_ptr = 0;

        #10 reset = 0;

        // Fill FIFO
        for (int i = 0; i < Depth; i++) begin
            @(negedge clock);
            write_en = 1;
            write_data = i + 1;
            expected_data[i] = i + 1;
            write_ptr++;
        end
        @(negedge clock);
        write_en = 0;

        if (!full) begin
            $display("ERROR: FIFO should be full");
            $finish;
        end

        // Read from FIFO
        for (int i = 0; i < Depth; i++) begin
            @(negedge clock);
            read_en = 1;
            @(posedge clock);
            check(expected_data[i], read_data, $sformatf("Reading index %0d", i));
            read_ptr++;
        end
        @(negedge clock);
        read_en = 0;

        if (!empty) begin
            $display("ERROR: FIFO should be empty");
            $finish;
        end

        $display("All FIFO tests passed successfully!");
        $finish;
    end

endmodule