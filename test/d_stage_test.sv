`include "verilog/sys_defs.svh"

module testbench;
    logic clock, reset;
    D_S_PACKET D_S_reg, D_packet;
    IF_ID_PACKET IF_ID_reg;

    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end

    d_stage d_stage_0(
        .IF_ID_reg(IF_ID_reg),

        .D_packet(D_packet)
    );

    initial begin
        clock = 0;
        reset = 1;
        @(negedge clock);
        @(negedge clock);
        reset = 0;

        IF_ID_reg = {32'h00100093, `XLEN'd0, `XLEN'd4, `TRUE};
        @(negedge clock);
        $display("INST: %0h\nPC: %0h\nNPC: %0h\nr: %0h\nr1: %0h\nr2: %0h\nopa_select: %0h\nopb_select: %0h\ncond_branch: %0b, uncond_branch: %0b, alu_func: %0h\nrs_idx: %0h\nhalt: %0b, illegal: %0b, csr_op: %0b, valid: %0b", 
                    D_packet.inst, D_packet.PC, D_packet.NPC, D_packet.r, D_packet.r1, D_packet.r2, D_packet.opa_select, D_packet.opb_select, D_packet.cond_branch,D_packet.uncond_branch,D_packet.alu_func, D_packet.rs_idx, D_packet.halt, D_packet.illegal, D_packet.csr_op, D_packet.valid);

        IF_ID_reg = {32'h02210233, `XLEN'd12, `XLEN'd16, `TRUE};
        @(negedge clock);
        $display("INST: %0h\nPC: %0h\nNPC: %0h\nr: %0h\nr1: %0h\nr2: %0h\nopa_select: %0h\nopb_select: %0h\ncond_branch: %0b, uncond_branch: %0b, alu_func: %0h\nrs_idx: %0h\nhalt: %0b, illegal: %0b, csr_op: %0b, valid: %0b", 
                    D_packet.inst, D_packet.PC, D_packet.NPC, D_packet.r, D_packet.r1, D_packet.r2, D_packet.opa_select, D_packet.opb_select, D_packet.cond_branch,D_packet.uncond_branch,D_packet.alu_func, D_packet.rs_idx, D_packet.halt, D_packet.illegal, D_packet.csr_op, D_packet.valid);
        $finish;
    end

endmodule