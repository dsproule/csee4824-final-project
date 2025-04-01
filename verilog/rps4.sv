
module rps2 (
    input              sel,
    input        [1:0] req,
    input              en,

    output logic [1:0] gnt,
    output logic       req_up
);

    // P1 TODO: create a two-bit rotating priority selector using logic
    assign req_up = req[0] | req[1];
    assign gnt[1] = (sel) ? (en & req[1]) : (en & req[1] & ~req[0]);
    assign gnt[0] = (sel) ? (en & req[0] & ~req[1]) : (en & req[0]);

endmodule


module rps4 (
    input              clock,
    input              reset,
    input        [3:0] req,
    input              en,

    output logic [3:0] gnt,
    output logic [1:0] count
);
    // P1 TODO: create a 4-bit rotating priority selector using rps2 modules
    rps2 p0(.sel(count[0]), .req(req[3:2]), .en(en0), .gnt(gnt[3:2]), .req_up(req_up0));
    rps2 p1(.sel(count[0]), .req(req[1:0]), .en(en1), .gnt(gnt[1:0]), .req_up(req_up1));

    rps2 p2(.sel(count[1]), .req({req_up0, req_up1}), .en(en), .gnt({en0, en1}), .req_up(req_up2));

    // P1 TODO: add the sequential counter here
	always_ff @(posedge clock) begin
        if(reset) begin
            count <= 2'b0;
        end
        else begin
            count <= count + 2'b01;
        end
	end

endmodule
