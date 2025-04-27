data = 0x1000
li	x6, 0
li	x2, data
li  x31, 0x0a
mul	x3,	x6,	x31
sw	x3, 0(x2)
lw	x4, 0(x2)
nop
wfi