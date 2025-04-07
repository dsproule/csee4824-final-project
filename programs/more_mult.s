

/* 
 * What im using for the mem tests. 'make programs/if_stage_test.mem' to compile it and 
 * then 'make if_stage.out' for the tb 
 */

addi x1, x0, 2

mul x6, x1, x1 
mul x7, x6, x1 
mul x8, x7, x1 
mul x9, x8, x1 
mul x10, x9, x1 
mul x11, x10, x1 
mul x12, x11, x1 
mul x13, x12, x1 
wfi
