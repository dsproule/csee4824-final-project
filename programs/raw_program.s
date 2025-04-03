

/* 
 * What im using for the mem tests. 'make programs/if_stage_test.mem' to compile it and 
 * then 'make if_stage.out' for the tb 
 */

addi x1, x0, 1
addi x3, x1, 2
add x2, x3, x3
mul x12, x2, x3
wfi
