li x1, 0xabcdef98 # word
li x2, 0x1234 # halfword
li x3, 0x67 # byte

addi x4, x0, 0x100

sw x2, 0(x4)

# no offset
sw x1, 0(x4)
sh x2, 0(x4)
sb x3, 0(x4)
 
# slight offset but not enough to cause shift
sw x1, 3(x4)
sh x2, 1(x4)

addi x4, x4, 0x100

# offset to shift to next one
sw x1, 4(x4)#
sh x2, 2(x4)
sb x3, 1(x4)

# slight offset past next offset (no change from above)
sw x1, 6(x4)
sh x2, 3(x4)

# offset to next addr
sw x1, 8(x4)
sh x2, 8(x4)
sb x3, 8(x4)

addi x1, x0, 347
li x2, 33546786
mul x3, x1, x2
addi x4, x0, 1000
addi x8, x0, 1008

# store word on clean offsets
sw x2, 0(x4)
lw x5, 0(x4)

# store on msb 4 bytes
sw x2, 4(x4)
lw x5, 4(x4)

# sw on next one
sw x2, 8(x4)
lw x5, 8(x4)

# test store variants
sb x2, 0(x4)
sb x2, 1(x4)
sh x2, 2(x4)
lw x5, 0(x4)

# fill out variety of 8 bytes
sb x2, 6(x4)
sb x2, 7(x4)
sh x2, 4(x4)
lw x5, 4(x4)

# offset rollover
sw x0, 8(x4)
sb x2, 8(x4)
sh x2, 10(x4)
lw x5, 8(x4)

# in between stores
sw x2, 2(x4)

wfi