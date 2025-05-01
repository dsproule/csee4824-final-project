`include "verilog/sys_defs.svh"

module func_unit_3(
    input clock, reset, committed, wr_valid,
    input [63:0] Dmem2proc_data,
    input S_X_PACKET S_X_reg,

    output [`XLEN-1:0] proc2Dmem_addr,
    output [63:0]      proc2Dcache_data,
    output X_C_PACKET  X_packet
);

    logic [`XLEN-1:0] rawDmem_addr;
    logic [3:0]       line_offset;
    logic [5:0]       shift;
    logic [63:0]      Dmem_data;
    mem_proc_states   mem_state;

    // should be word-aligned. If a value is invalid proc_resp will be 0
    assign rawDmem_addr   = S_X_reg.V1 + S_X_reg.mem_offset;
    assign proc2Dmem_addr = {rawDmem_addr[`XLEN-1:3], 3'b0};
    assign line_offset    = rawDmem_addr[2:0];

    always_comb begin
        Dmem_data = Dmem2proc_data;
        case (S_X_reg.mem_size)
            BYTE: begin
                shift = (line_offset) << 3;
                case (shift)
                    0: Dmem_data[7:0] = S_X_reg.V2[7:0];
                    8: Dmem_data[15:8] = S_X_reg.V2[7:0];
                    16: Dmem_data[23:16] = S_X_reg.V2[7:0];
                    24: Dmem_data[31:24] = S_X_reg.V2[7:0];
                    32: Dmem_data[39:32] = S_X_reg.V2[7:0];
                    40: Dmem_data[47:40] = S_X_reg.V2[7:0];
                    48: Dmem_data[55:48] = S_X_reg.V2[7:0];
                    56: Dmem_data[63:56] = S_X_reg.V2[7:0];
                endcase
            end
            HALF: begin
                shift = (line_offset >> 1) << 4;
                case (shift)
                    0: Dmem_data[15:0] = S_X_reg.V2[15:0];
                    16: Dmem_data[31:16] = S_X_reg.V2[15:0];
                    32: Dmem_data[47:32] = S_X_reg.V2[15:0];
                    48: Dmem_data[63:48] = S_X_reg.V2[15:0];
                endcase
            end
            WORD: begin
                shift = (line_offset[2] << 2) << 3;
                case (shift)
                    0: Dmem_data[31:0] = S_X_reg.V2[31:0];
                    32: Dmem_data[63:32] = S_X_reg.V2[31:0];
                endcase
            end
            default: begin
                shift = '0;
            end
        endcase
    end

    assign proc2Dcache_data = Dmem_data;

    always_comb begin
        if (wr_valid) begin
            X_packet.T         = S_X_reg.T;
            X_packet.result    = '0;
            
            X_packet.ppln_ctrl = '0;
            X_packet.valid     = `TRUE;
            X_packet.ppln_ctrl.is_store = `TRUE;
        end else begin
            X_packet           = '0;
        end
    end

endmodule   // func_unit_3
