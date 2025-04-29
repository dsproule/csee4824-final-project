addi    x4, x0, 48
addi    x1, x0, 12
addi    x2, x0, 48
mul     x3, x1, x2
beq     x1, x4, happy
addi    x5, x0, 5
addi    x6, x0, 6
addi    x7, x0, 7
beq     x2, x4, happy
addi    x5, x0, 8
addi    x6, x0, 9
addi    x7, x0, 10
wfi

happy:
addi    x5, x0, 3
addi    x6, x0, 4
addi    x7, x0, 5
wfi
