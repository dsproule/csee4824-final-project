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
    input   INST        inst,
    output  logic       valid_o,
    output  logic [`XLEN-1:0] target_addr            
);

endmodule

module branch_pred(
    // from current instruction
    input   logic       clk,
    input   logic       reset,
    input   logic [`XLEN-1:0] pc,
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
    logic [`XLEN-1:0] btb_target;

    assign take_branch = bht_take_branch && btb_hit;
    assign next_addr = btb_target;

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

endmodule