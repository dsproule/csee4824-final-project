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
    wfi
