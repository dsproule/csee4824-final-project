    # TODO: Add memory loads/stores to make sure data is flowing

    /*  
        r1-10 should read 1-10 at the end
    */

       
    # structural hazards
    addi x11, x0, 2
    addi x10, x0, 10
    sw	 x10, 8(x11)
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    wfi
