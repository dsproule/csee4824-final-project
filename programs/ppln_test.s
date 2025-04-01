
    /*  
        r1-10 should read 1-10 at the end
    */

       
    # test struct hazard
    addi x1, x0,  1
    addi x2, x1,  2
    nop
    mul	x13, x12, x3
    addi x4, x0,  4
    addi x5, x0,  5
    
    wfi
