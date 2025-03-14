module fifo #(
    parameter  DataWidth = 32,
    parameter  Depth     = 8,
    localparam PtrWidth  = $clog2(Depth))(
    input  logic                 clock,
    input  logic                 reset,
    input  logic                 write_en,
    input  logic [DataWidth-1:0] write_data,
    input  logic                 read_en,
    output logic [DataWidth-1:0] read_data,
    output logic                 full,
    output logic                 empty
);

    //here is where you would put wtv struct you would use
    logic [DataWidth-1:0] mem[Depth];
    logic [PtrWidth:0] wr_ptr, next_wr_ptr;
    logic [PtrWidth:0] rd_ptr, next_rd_ptr;

    always_comb begin
        next_wr_ptr = wr_ptr;
        next_rd_ptr = rd_ptr;
        if (write_en) begin
            next_wr_ptr = wr_ptr + 1;
        end
        if (read_en) begin
            next_rd_ptr = rd_ptr + 1;
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            wr_ptr <= next_wr_ptr;
            rd_ptr <= next_rd_ptr;
        end
        mem[wr_ptr[PtrWidth-1:0]] <= write_data;
    end

    assign read_data = mem[rd_ptr[PtrWidth-1:0]];

    assign empty = (wr_ptr[PtrWidth] == rd_ptr[PtrWidth]) && (wr_ptr[PtrWidth-1:0] == rd_ptr[PtrWidth-1:0]);
    assign full  = (wr_ptr[PtrWidth] != rd_ptr[PtrWidth]) && (wr_ptr[PtrWidth-1:0] == rd_ptr[PtrWidth-1:0]);

endmodule