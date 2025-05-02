
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

    output             req_up,
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

module rps(
    input clock, reset, en,
    input        [5:0] req,

    output logic [5:0] gnt_out,
    output req_up
);

    logic [3:0] count;
    logic [1:0] gnt_en;
    logic msb_req, lsb_req;
    logic [5:0] gnt;

    rps2 msb(.sel(count[0]), .req(req[5:4]), .en(1'b1), .gnt(gnt[5:4]), .req_up(msb_req));
    rps4 lsb(.clock(clock), .reset(reset), .req(req[3:0]), .en(1'b1), .gnt(gnt[3:0]), .count(), .req_up(lsb_req));
    rps2 top(.sel(count[2]), .req({msb_req, lsb_req}), .en(en), .gnt(gnt_en), .req_up(req_up));

    assign gnt_out[5:4] = (msb_req & gnt_en[1]) ? gnt[5:4] : 2'b0;
    assign gnt_out[3:0] = (lsb_req & gnt_en[0]) ? gnt[3:0] : 4'b0;

    always_ff @(posedge clock) begin
        if (reset)
            count <= '0;
        else
            count <= (count == 5) ? '0 : count + 1;
    end


endmodule