`include "verilog/sys_defs.svh"

module func_unit_1(
    input clock, reset, retired,
    input S_X_PACKET S_X_reg,

    output X_C_PACKET X_packet
);
    PPLN_CTRL ppln_ctrl;
    logic [1:0] signs;
    logic [63:0] mult_result;
    logic start;

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
    assign signs = ((S_X_reg.alu_func == ALU_MUL) | (S_X_reg.alu_func == ALU_MULH)) ? 2'b11:
                    (S_X_reg.alu_func == ALU_MULHSU) ? 2'b10 : 2'b00;

    
    mult mult_1(
        .clock(clock), .reset(reset),
        .mcand({32'b0, S_X_reg.V1}), .mplier({32'b0, S_X_reg.V2}),
        .signs(signs),               //  [1] -> s_mplier, [0] -> s_mcand
        .start(start),

        .product(mult_result),
        .done(X_packet.valid)
    );

    always_comb begin
        case (S_X_reg.alu_func)
            ALU_MUL:    X_packet.result = mult_result[`XLEN-1:0];
            ALU_MULH:   X_packet.result = mult_result[2*`XLEN-1:`XLEN];
            ALU_MULHSU: X_packet.result = mult_result[2*`XLEN-1:`XLEN];
            ALU_MULHU:  X_packet.result = mult_result[2*`XLEN-1:`XLEN];
        endcase
    end

    logic can_start;
    //assign start = (S_X_reg.valid && can_start);

    always_ff @(posedge clock) begin
        can_start <= 1;
        if (S_X_reg.valid) can_start <= 0;
        if (X_packet.valid) can_start <= 1;
        
        start <= (S_X_reg.valid && can_start);
    end

endmodule