/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  stage_if.sv                                         //
//                                                                     //
//  Description :  instruction fetch (IF) stage of the pipeline;       //
//                 fetch instruction, compute next PC location, and    //
//                 send them down the pipeline.                        //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

module if_stage (
    input             clock, reset, gnt,
    input             take_branch,
    input [`XLEN-1:0] branch_target,
    input [63:0]      Imem2proc_data,
    input [3:0]       Imem2proc_response, Imem2proc_tag,

    output logic mem_req,
    output IF_ID_PACKET IF_packet,
    output logic [1:0]  proc2Imem_command,
    output logic [`XLEN-1:0] proc2Imem_addr
);

    typedef enum logic {NEW_ADDR, WAIT_FOR_TAG} IF_states;
    
    logic [`XLEN-1:0] PC_reg;
    logic nextImem_tag;
    IF_states IF_state;

    // word-aligned mem
    assign proc2Imem_addr = {PC_reg[`XLEN-1:3], 3'b0};

    always_ff @(posedge clock) begin
        if (reset | take_branch) begin
            // place initial request
            PC_reg <= (take_branch) ? branch_target : `XLEN'h0;
            proc2Imem_command <= BUS_LOAD;
            mem_req <= `TRUE;
            IF_state <= NEW_ADDR;
        end else begin
            IF_packet.inst <= `NOP;
            IF_packet.valid <= `FALSE;

            case (IF_state)
                NEW_ADDR: begin
                    nextImem_tag <= Imem2proc_response;
                    if (gnt) begin
                        mem_req <= `FALSE;
                        proc2Imem_command <= BUS_NONE;
                        IF_state <= WAIT_FOR_TAG;
                    end
                end
                WAIT_FOR_TAG: begin
                    if (Imem2proc_tag == nextImem_tag) begin
                        IF_packet <= {
                                (PC_reg[2]) ? Imem2proc_data[63:32] : Imem2proc_data[31:0], 
                                PC_reg,
                                PC_reg + 4,
                                `TRUE
                            };

                        // request for new memory
                        PC_reg <= PC_reg + 4;
                        mem_req <= `TRUE;
                        proc2Imem_command <= BUS_LOAD;
                        IF_state <= NEW_ADDR;
                    end
                end
            endcase
        end
    end    

endmodule // if_stage
