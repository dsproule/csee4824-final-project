addi x1, x0, 347
li x2, 33546786
mul x3, x1, x2
addi x4, x0, 1000
addi x8, x0, 1008

sw x2, 0(x4)
sw x2, 0(x8)

# no offset
lb x5, 0(x4)
lh x6, 0(x4)
lw x7, 0(x4)

# slight offset but not enough to cause shift
lh x6, 1(x4)
lw x7, 3(x4)

# offset to shift to next one
lb x5, 1(x4)
lh x6, 2(x4)
lw x7, 4(x4)

# slight offset past next offset (no change from above)
lh x6, 3(x4)
lw x7, 6(x4)

# offset to next addr
lb x5, 8(x4)
lh x6, 8(x4)
lw x7, 8(x4)

wfi