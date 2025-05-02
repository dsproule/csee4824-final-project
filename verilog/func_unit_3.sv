`include "verilog/sys_defs.svh"

module func_unit_3(
    input [63:0] Dmem2proc_data,
    input MEM_ACCESS mem_access,
    input logic [`XLEN-1:0] proc2Dmem_data,

    output [63:0]      proc2Dcache_data
);

    logic [5:0]       shift;
    logic [63:0]      Dmem_data;

    always_comb begin
        Dmem_data = Dmem2proc_data;
        case (mem_access.mem_size)
            BYTE: begin
                shift = (mem_access.line_offset) << 3;
                case (shift)
                    0: Dmem_data[7:0] = proc2Dmem_data[7:0];
                    8: Dmem_data[15:8] = proc2Dmem_data[7:0];
                    16: Dmem_data[23:16] = proc2Dmem_data[7:0];
                    24: Dmem_data[31:24] = proc2Dmem_data[7:0];
                    32: Dmem_data[39:32] = proc2Dmem_data[7:0];
                    40: Dmem_data[47:40] = proc2Dmem_data[7:0];
                    48: Dmem_data[55:48] = proc2Dmem_data[7:0];
                    56: Dmem_data[63:56] = proc2Dmem_data[7:0];
                endcase
            end
            HALF: begin
                shift = (mem_access.line_offset >> 1) << 4;
                case (shift)
                    0: Dmem_data[15:0] = proc2Dmem_data[15:0];
                    16: Dmem_data[31:16] = proc2Dmem_data[15:0];
                    32: Dmem_data[47:32] = proc2Dmem_data[15:0];
                    48: Dmem_data[63:48] = proc2Dmem_data[15:0];
                endcase
            end
            WORD: begin
                shift = (mem_access.line_offset[2] << 2) << 3;
                case (shift)
                    0: Dmem_data[31:0] = proc2Dmem_data[31:0];
                    32: Dmem_data[63:32] = proc2Dmem_data[31:0];
                endcase
            end
            default: begin
                shift = '0;
            end
        endcase
    end

    assign proc2Dcache_data = Dmem_data;

endmodule   // func_unit_3
