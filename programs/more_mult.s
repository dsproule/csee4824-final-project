

/* 
 * What im using for the mem tests. 'make programs/if_stage_test.mem' to compile it and 
 * then 'make if_stage.out' for the tb 
 */

addi x1, x0, 2
mul x2, x1, x1
mul x3, x2, x1 
nop
nop
nop
nop
nop
nop
nop
nop
wfi
