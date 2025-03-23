`timescale 1ns/1ps

`include "verilog/sys_defs.svh"

module testbench;

    logic clock, reset, done, correct;
    logic [63:0] value, cycles;
    logic [31:0] result, target;
    
    task wait_until_done_reset(logic [63:0] val, logic [31:0] targ);
        reset = 1;
        @(negedge clock);
        @(negedge clock);
        value = val;
        target = targ;
        @(negedge clock);
        reset = 0;
        cycles = 0;
        forever begin : wait_loop
            @(posedge done);
            @(negedge clock);
            if (done) begin
                $display("Took %1d cycles to complete sqrt(%1d) = %4d", cycles, val, result);
                disable wait_until_done_reset;
            end
        end
    endtask

    task wait_until_done_no_reset(logic [63:0] V1, logic [63:0] V2, logic [31:0] targ, ALU_FUNC alu_func);
        // load up S_X_reg
        @(negedge clock);
        S_X_reg.V1 = V1;
        S_X_reg.V2 = V2;
        S_X_reg.valid = `TRUE;
        S_X_reg.alu_func = alu_func;
        forever begin : wait_loop
            @(posedge done);
            @(negedge clock);
            if (done) begin
                $display("Took %1d cycles to complete. (no reset)", cycles);
                disable wait_until_done_no_reset;
            end
        end
    endtask

    assign correct = (done == 1 && target == X_C_packet.result);

    initial begin
        forever begin : clcok_gen
            #5 clock = ~clock;
            if (clock == 1)
                cycles = cycles + 1;
        end
    end

    always @(posedge clock) begin
        #(`CLOCK_PERIOD*0.2); // a short wait to let signals stabilize
        if (!correct && done) begin
            $display("@@@ Incorrect");
            $display("Module returned a value of (%3d) when it was supposed to give (%3d)", result, target);
            $finish;
        end
    end

    S_X_PACKET S_X_reg;
    X_C_PACKET X_C_packet;
    
    func_unit_1 FU_1(
        .clock(clock), .reset(reset),
        .S_X_reg(S_X_reg),

        .X_C_packet(X_C_packet)
    );

    initial begin
        $dumpfile("ISR.vcd");
        $dumpvars(0, testbench);
        clock = 0;
        reset = 1;

        $display("\n");
        // normal cases
        wait_until_done_no_reset(64'd2, 64'd2, 32'd4, ALU_MUL);
        // wait_until_done_reset(64'd4, 32'd2);
        // wait_until_done_reset(64'd9, 32'd3);
        // wait_until_done_reset(64'd16, 32'd4);        
        // wait_until_done_reset(64'd25, 32'd5);
        // // under cases
        // wait_until_done_reset(64'd24, 32'd4);
        // wait_until_done_reset(64'd15, 32'd3);
        // wait_until_done_reset(64'd2, 32'd1);
        // // edge cases
        // wait_until_done_reset(64'd1, 32'd1);
        // wait_until_done_reset(64'd0, 32'd0);
        // wait_until_done_reset(64'hFFFFFFFFFFFFFFFF, 32'hFFFFFFFF);

        // // change value during execution
        // reset = 1;
        // @(negedge clock);
        // @(negedge clock);
        // value = 64'd35;
        // target = 32'd5;
        // @(negedge clock);
        // cycles = 0;
        // reset = 0;
        // #(`CLOCK_PERIOD*20);
        // value = 64'd1;
        // @(negedge clock);
        // @(negedge clock);
        // @(negedge clock);
        // @(negedge clock);
        
        $display("@@@ Passed\n");
        $finish;
    end

endmodule
