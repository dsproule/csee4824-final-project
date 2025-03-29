
module rps2 (
    input              sel,
    input        [1:0] req,
    input              en,

    output logic [1:0] gnt,
    output logic       req_up
);

    assign req_up = req[0] | req[1];

    always_comb begin
        gnt[sel] = req[sel] & en;
       gnt[~sel] = req[~sel] & ~req[sel] & en;  
    end
    
endmodule


module rps4 (
    input              clock,
    input              reset,
    input        [3:0] req,
    input              en,

    output logic [3:0] gnt,
    output logic [1:0] count
);
  
    logic [1:0] req_ups, gnt_en, gnt_buf;
    logic low_req_buf;

    /* if sel is on wrap-around case, other req is asserted, use that instead */
    always_comb begin
        if ((count == 2 || count == 0) && req_ups == 2'b11 && req[count] == 0) begin
            gnt_en = ~gnt_buf;
            low_req_buf = ~count[0];
        end else begin
            low_req_buf = count[0];
            gnt_en = gnt_buf;
        end
    end

    rps2 msb(.sel(low_req_buf), .req(req[3:2]), .en(gnt_en[1]), .gnt(gnt[3:2]), .req_up(req_ups[1]));
    rps2 lsb(.sel(low_req_buf), .req(req[1:0]), .en(gnt_en[0]), .gnt(gnt[1:0]), .req_up(req_ups[0]));
    rps2 top(.sel(count[1]), .req(req_ups), .en(en), .gnt(gnt_buf), .req_up(req_up));

	always_ff @(posedge clock) begin
        if (reset)
            count <= 2'b00;
        else
            count <= count + 1'b1;

	end

endmodule // rps4
