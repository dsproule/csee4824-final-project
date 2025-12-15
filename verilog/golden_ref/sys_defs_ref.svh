/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename : sys_defs_ref.svh                                     //
//                                                                     //
//   Description : Packet typedefs used only by the in-order pipeline  //
//                 (golden reference).                                 //
//                                                                     //
//   NOTE: This file assumes verilog/sys_defs.svh is already included. //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __SYS_DEFS_REF_SVH__
`define __SYS_DEFS_REF_SVH__

////////////////////////////////
// ---- In-order Packets ---- //
////////////////////////////////

/**
 * ID -> EX
 */
typedef struct packed {
    INST              inst;
    logic [`XLEN-1:0] PC;
    logic [`XLEN-1:0] NPC;

    logic [`XLEN-1:0] rs1_value;
    logic [`XLEN-1:0] rs2_value;

    ALU_OPA_SELECT    opa_select;
    ALU_OPB_SELECT    opb_select;

    logic [4:0]       dest_reg_idx;
    ALU_FUNC          alu_func;

    logic             rd_mem;
    logic             wr_mem;
    logic             cond_branch;
    logic             uncond_branch;
    logic             halt;
    logic             illegal;
    logic             csr_op;

    logic             valid;
} ID_EX_PACKET;

/**
 * EX -> MEM
 */
typedef struct packed {
    logic [`XLEN-1:0] alu_result;
    logic [`XLEN-1:0] NPC;

    logic             take_branch;
    logic [`XLEN-1:0] rs2_value;

    logic             rd_mem;
    logic             wr_mem;
    logic [4:0]       dest_reg_idx;

    logic             halt;
    logic             illegal;
    logic             csr_op;
    logic             rd_unsigned;

    MEM_SIZE          mem_size;
    logic             valid;
} EX_MEM_PACKET;

/**
 * MEM -> WB
 */
typedef struct packed {
    logic [`XLEN-1:0] result;
    logic [`XLEN-1:0] NPC;

    logic [4:0]       dest_reg_idx;
    logic             take_branch;
    logic             halt;
    logic             illegal;
    logic             valid;
} MEM_WB_PACKET;

`endif // __SYS_DEFS_REF_SVH__

