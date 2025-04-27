.section .text
.globl _start

_start:
    li x5, 0x00000001     # x5 = 1
    li x6, 0xFFFFFFFF     # x6 = -1 (signed), but 0xFFFFFFFF (unsigned)

    bltu x5, x6, branch_taken_1

    li x10, 1             # Set x10 = 1 to signal failure
    wfi

branch_taken_1:
    bltu x6, x5, branch_taken_2

    li x10, 0             # Set x10 = 0 to signal success
    wfi

branch_taken_2:
    li x10, 2             # Set x10 = 2 to signal another failure

end:
    wfi