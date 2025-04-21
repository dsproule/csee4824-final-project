module fifo #(
    parameter DataWidth = 32,
    parameter Depth     = 8,
    localparam PtrWidth = $clog2(Depth)
)(
    input  logic                 clock,
    input  logic                 reset,
    input  logic                 write_en,
    input  logic [DataWidth-1:0] write_data, //data width is wtv struct you want
    input  logic                 read_en,
    output logic [DataWidth-1:0] read_data,
    output logic                 full,
    output logic                 empty
);

    // Internal storage
    logic [DataWidth-1:0] mem [0:Depth-1];

    // Head and tail pointers
    logic [PtrWidth-1:0] head, tail;
    logic head_wrap, tail_wrap;

    // Full/empty flags based on wrap logic
    assign full  = (head == tail) && (head_wrap != tail_wrap);
    assign empty = (head == tail) && (head_wrap == tail_wrap);

    assign read_data = mem[head]; //can read when read_en comes in

    always_ff @(posedge clock) begin
        if (reset) begin
            head <= 0;
            tail <= 0;
            head_wrap <= 0;
            tail_wrap <= 0;
        end else begin
            if (write_en && !full) begin
                mem[tail] <= write_data;
                if (tail == Depth - 1) begin
                    tail <= 0;
                    tail_wrap <= ~tail_wrap;
                end else begin
                    tail <= tail + 1;
                end
            end

            if (read_en && !empty) begin
                if (head == Depth - 1) begin
                    head <= 0;
                    head_wrap <= ~head_wrap;
                end else begin
                    head <= head + 1;
                end
            end
        end
    end

endmodule
