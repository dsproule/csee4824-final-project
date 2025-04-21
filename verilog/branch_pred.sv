`include "verilog/sys_defs.svh"
`include "verilog/ISA.svh"

// decide branch taken or not
module BHT(
    input   logic           clk,
    input   logic           reset,  
    input   logic [7:0]     pc_index,
    input   logic           update_en,
    input   logic           update_take_branch,
    output  logic [1:0]     take_branch
);

    logic [1:0] bht [0:255];
    integer i;
    logic [7:0] bhr;
    logic [7:0] entry;

    assign entry = bhr ^ pc_index;

    always_ff @(posedge clk) begin
        if(reset) begin
            for (i = 0; i < 256; i=i+1) begin
                bht[i] <= 2'b00;
            end
            bhr <= 8'b0;
        end
        else if(update_en) begin
            if (update_take_branch && (bht[entry] != 2'b11))
                bht[entry] <= bht[entry] + 1;
            else if (!update_take_branch && (bht[pc_index] != 2'b00))
                bht[entry] <= bht[entry] - 1;

            bhr <= {bhr[6:0] , update_take_branch};
        end
    end

    always_comb begin
        take_branch = bht[pc_index][1];
    end
endmodule

// a small branch target cache 
module BTB (
    input   logic           clk,
    input   logic           reset,
    input   logic [31:0]    pc,
    input   logic           update_en,
    input   logic [31:0]    update_target_addr,
    output  logic           hit,
    output  logic [31:0]    predicted_target
);
    logic [31:0] btb_pc [0:255];
    logic [31:0] btb_target [0:255];

    integer i;

    always_ff @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 256; i = i + 1) begin
                btb_pc[i] <= 32'h0;
                btb_target[i] <= 32'h0;
            end
        end else if (update_en) begin
            btb_pc[pc[9:2]] <= pc;
            btb_target[pc[9:2]] <= update_target_addr;
        end
    end

    always_comb begin
        if (btb_pc[pc[9:2]] == pc) begin
            hit = 1;
            predicted_target = btb_target[pc[9:2]];
        end else begin
            hit = 0;
            predicted_target = 32'h0;
        end
    end
endmodule

module addr_calc(
    input   logic [`XLEN-1:0] pc,
    input   INST        inst,
    output  logic       valid_o,
    output  logic [`XLEN-1:0] target_addr            
);

    logic [6:0] opcode;
    logic [31:0] imm_jal;
    logic [31:0] imm_branch;

    assign opcode = instr[6:0];
    // JAL immediate decoding (J-type)
    assign imm_jal = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    // Branch immediate decoding (B-type)
    assign imm_branch = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

    // Detect JAL and Branch (BEQ/BNE/BLT/...)
    wire is_jal     = (opcode == 7'b1101111); // JAL
    wire is_branch  = (opcode == 7'b1100011); // Branch type

    assign valid_o = is_jal || is_branch;

    assign target_addr = is_jal     ? (pc_in + imm_jal) :
                         is_branch  ? (pc_in + imm_branch) :
                         32'b0;

endmodule

module branch_pred(
    // from current instruction
    input   logic       clk,
    input   logic       reset,
    input   logic [`XLEN-1:0] pc,
    input   INST        inst,
    // for model update (from cdb?)
    input   logic       update_en,
    input   logic       update_take_branch,
    input   logic [`XLEN-1:0] update_address,    

    // output
    output  logic       take_branch,
    output  logic [`XLEN-1:0] next_addr
);

    logic bht_take_branch;
    logic btb_hit;
    logic [`XLEN-1:0] btb_target, addr_calc_target;
    logic is_imm;
    
    assign take_branch = bht_take_branch & (btb_hit | is_imm);
    assign next_addr = (~bht_take_branch) ? (32'b0) : (is_imm ? (addr_calc_target) : (btb_hit ? (btb_target) : (32'b0)));

    BHT bht_inst(
        .clk(clk),
        .reset(reset),  
        .pc_index(pc[7:0]),
        .update_en(update_en),
        .update_take_branch(update_take_branch),
        .take_branch(bht_take_branch)
    );

    BTB btb_inst(
        .clk(clk),
        .reset(reset),
        .pc(pc),
        .update_en(update_en),
        .update_target_addr(update_address),
        .hit(btb_hit),
        .predicted_target(btb_target)
    );

    addr_calc addr_calc_inst(
        .pc(pc),
        .inst(inst),
        .valid_o(is_imm),
        .target_addr(addr_calc_target)    
    );

endmodule