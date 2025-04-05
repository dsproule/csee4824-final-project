    # TODO: Add memory loads/stores to make sure data is flowing

    /*  
        r1-10 should read 1-10 at the end
    */

       
    # structural hazards
    addi x11, x0, 11
    addi x10, x0, 10
    sw	 x10, 4(x11)
    sw	 x10, 0(x11)
    sw	 x10, 0(x11)
    addi x1, x0, 1
    addi x2, x0, 2
    sw	 x10, 0(x11)
    sw	 x10, 0(x11)
    addi x3, x0, 3
    addi x4, x0, 4
    addi x5, x0, 5
    nop
    addi x6, x0, 6

    # branch pred (these will get skipped unless your branch pred doesnt work)
    beq  x0, x0, .branch_jump
    addi x2, x0, 5
    addi x3, x0, 6
    addi x4, x0, 7
    addi x5, x0, 8
    addi x6, x0, 9

.branch_jump:
    # data forwarding mem_reg
    add  x7, x1, x2      # x7 = 3
    add  x7, x7, x2      # x7 = 5
    addi x7, x7, 2       # x7 = 7

    # data forwarding wb_reg
    li  x8, 4
    nop
    addi x8, x8, 4

    li   x9, 5
    addi x9, x9, 4
    
    # lw stall
    li x11, 0x1000
    li x1, 1
    addi x10, x0, 10     # doesn't ask for the pass back correctly to sw
    sw x10, 0(x11)       # mem[0x1000] = a    
    lw x9, 0(x11)
    sub x9, x9, x1
    addi x12, x0, 12
    
    wfi
