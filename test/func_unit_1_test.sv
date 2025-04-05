`timescale 1ns/1ps

`include "verilog/sys_defs.svh"

module testbench;

    logic clock, reset, done, correct, retired;
    logic [63:0] value, cycles;
    logic [31:0] result, target;

    S_X_PACKET S_X_reg;
    X_C_PACKET X_packet;

    /* Call this to run a test */
    task wait_until_done_no_reset(logic [31:0] V1, logic [31:0] V2, logic [31:0] targ, ALU_FUNC alu_func);
        // load up S_X_reg
        @(negedge clock);
        S_X_reg.V1 = V1;
        S_X_reg.V2 = V2;
        target = targ;
        S_X_reg.valid = `TRUE;
        S_X_reg.alu_func = alu_func;
        target = targ;
        @(negedge clock);
        //S_X_reg.valid = `FALSE;
        forever begin : wait_loop
            @(posedge clock);
            if (done) begin
                $display("%0d x %0d = %0d", $signed(V1), $signed(V2), $signed(X_packet.result));
                disable wait_until_done_no_reset;
            end
        end
    endtask

    assign done = X_packet.valid;
    assign correct = ((done == 1) & (target == X_packet.result));

    initial begin
        forever begin : clock_gen
            #5 clock = ~clock;
            if (clock == 1)
                cycles = cycles + 1;
        end
    end

    always @(posedge clock) begin
        #(`CLOCK_PERIOD*0.2); // a short wait to let signals stabilize
        if (!correct && done) begin
            $display("@@@ Incorrect");
            $display("Module returned a value of (%0d) when it was supposed to give (%0d)", $signed(result), $signed(target));
            $finish;
        end
    end
    
    func_unit_1 FU_1(
        .clock(clock), .reset(reset), .retired(retired),
        .S_X_reg(S_X_reg),

        .X_packet(X_packet)
    );

    logic signed [63:0] tmp;
    initial begin
        clock = 0;
        reset = 1;

        $display("Mult TB\n----------------------------------\n");
        // normal cases
        @(negedge clock);
        @(negedge clock);
        reset = 0;
        // signed tests 
        wait_until_done_no_reset(32'd2, 32'd2, 32'd4, ALU_MUL);
        retired = 1;
        @(negedge clock);
        retired = 0;
        wait_until_done_no_reset(32'd3, 32'd5, 32'd15, ALU_MUL);
        retired = 1;
        @(negedge clock);
        retired = 0;
        wait_until_done_no_reset(32'd0, 32'd2, 32'd0, ALU_MUL);
        retired = 1;
        @(negedge clock);
        retired = 0;
        wait_until_done_no_reset(32'd44589, 32'd345, 32'd15383205, ALU_MUL);
        retired = 1;
        @(negedge clock);
        retired = 0;
        wait_until_done_no_reset(-32'd1, 32'd2, -32'd2, ALU_MUL);
        retired = 1;
        @(negedge clock);
        retired = 0;

        // Could check other ALU modes for thoroughness but fine as is
        wait_until_done_no_reset(32'd2, 32'd2, 32'd0, ALU_MULHSU);      // will look crazy because upper 32 bits taken (0)
        retired = 1;
        @(negedge clock);
        retired = 0;
        wait_until_done_no_reset(32'd4454589, 32'd355545, 32'd368, ALU_MULHSU);

        retired = 1;
        @(negedge clock);
        retired = 0;

        $display("\n@@@ Passed\n");
        $finish;
    end

endmodule
