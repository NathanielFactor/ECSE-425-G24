# test_branches.s
# Tests all 6 branch types, each taken (skips a poison instruction)
# Expected: x5=1  x6=1  x7=1  x8=1  x10=1  x11=1

    addi x1, x0, 5       # x1 = 5
    addi x2, x0, 5       # x2 = 5
    addi x3, x0, 3       # x3 = 3
    addi x4, x0, -1      # x4 = -1 (0xFFFFFFFF, large unsigned)

    beq  x1, x2, beq_ok  # x1 == x2  -> taken
    addi x9, x0, -1107   # POISON
beq_ok:
    addi x5, x0, 1       # x5 = 1

    bne  x1, x3, bne_ok  # x1 != x3  -> taken
    addi x9, x0, -1107   # POISON
bne_ok:
    addi x6, x0, 1       # x6 = 1

    blt  x3, x1, blt_ok  # x3 < x1 (signed) -> taken
    addi x9, x0, -1107   # POISON
blt_ok:
    addi x7, x0, 1       # x7 = 1

    bge  x1, x3, bge_ok  # x1 >= x3 (signed) -> taken
    addi x9, x0, -1107   # POISON
bge_ok:
    addi x8, x0, 1       # x8 = 1

    bltu x3, x1, bltu_ok # x3 <u x1 -> taken
    addi x9, x0, -1107   # POISON
bltu_ok:
    addi x10, x0, 1      # x10 = 1

    bgeu x4, x3, bgeu_ok # x4 >=u x3 (0xFFFFFFFF >= 3) -> taken
    addi x9, x0, -1107   # POISON
bgeu_ok:
    addi x11, x0, 1      # x11 = 1

halt:
    jal  x0, halt
