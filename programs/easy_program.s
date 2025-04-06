

/* 
 * What im using for the mem tests. 'make programs/if_stage_test.mem' to compile it and 
 * then 'make if_stage.out' for the tb 
 */

addi x1, x0, 1
sw   x1, 800(x0)
addi x2, x0, 2
addi x3, x0, 800
lw   x5, 0(x3)
mul  x4, x2, x2
mul  x8, x4, x2
sw   x1, 800(x0)
lw   x5, 800(x0)
wfi