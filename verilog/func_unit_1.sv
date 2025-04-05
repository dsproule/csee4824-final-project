`include "verilog/sys_defs.svh"

module func_unit_1(
    input clock, reset, retired,
    input S_X_PACKET S_X_reg,

    output X_C_PACKET X_packet
);
    PPLN_CTRL ppln_ctrl;
    logic [1:0] signs;
    logic [63:0] mult_result;
    logic new_op;

    assign X_packet.T = S_X_reg.T;
    
    // pipeline control
    assign ppln_ctrl.flush = `FALSE;
    assign ppln_ctrl.is_store = `FALSE;
    assign ppln_ctrl.is_branch = `FALSE;

    // assign ppln_ctrl.valid = S_X_reg.valid;
    assign ppln_ctrl.illegal = 0;
    assign ppln_ctrl.halt = 0;

    assign X_packet.ppln_ctrl = ppln_ctrl;

    // pass to mult signed vector
    assign signs = {
            (S_X_reg.alu_func != ALU_MULHU), 
            (S_X_reg.alu_func == ALU_MUL) | (S_X_reg.alu_func == ALU_MULH)
        };

    mult mult_1(
        .clock(clock), .reset(reset),
        .mcand({32'b0, S_X_reg.V1}), .mplier({32'b0, S_X_reg.V2}),
        .signs(signs),               //  [1] -> s_mplier, [0] -> s_mcand
        .start(S_X_reg.valid & new_op),

        .product(mult_result),
        .done(X_packet.valid)
    );

    always_ff @(posedge clock) begin
        if (reset | retired) begin
            new_op <= `TRUE;
        end else begin
            if (S_X_reg.valid)
                new_op <= `FALSE;
        end
    end

    always_comb begin
        case (S_X_reg.alu_func)
            ALU_MUL:    X_packet.result = mult_result[`XLEN-1:0];
            ALU_MULH:   X_packet.result = mult_result[2*`XLEN-1:`XLEN];
            ALU_MULHSU: X_packet.result = mult_result[2*`XLEN-1:`XLEN];
            ALU_MULHU:  X_packet.result = mult_result[2*`XLEN-1:`XLEN];
        endcase
    end

endmodule