addi x1, x0, 347
li x2, 33546786
mul x3, x1, x2
addi x4, x0, 1000

sw x2, 0(x4)
lb x5, 0(x4)
lh x6, 0(x4)
lw x7, 0(x4)
wfi