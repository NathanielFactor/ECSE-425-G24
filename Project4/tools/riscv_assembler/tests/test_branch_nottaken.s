# test_branch_nottaken.s
# All 6 branch types tested as NOT taken; both fall-through slots must execute.
# Expected: x10=10 x11=11 x12=12 x13=13 x14=14 x15=15
#           x20=20 x21=21 x22=22 x23=23 x24=24 x25=25

    addi x1, x0, 1
    addi x2, x0, 2

    # BEQ not taken: 1 != 2
    beq  x1, x2, nt_beq_skip
    addi x10, x0, 10
    addi x20, x0, 20
    jal  x0, nt_beq_done
nt_beq_skip:
    addi x10, x0, -1107      # POISON
    addi x20, x0, -1107      # POISON
nt_beq_done:

    # BNE not taken: 1 == 1
    bne  x1, x1, nt_bne_skip
    addi x11, x0, 11
    addi x21, x0, 21
    jal  x0, nt_bne_done
nt_bne_skip:
    addi x11, x0, -1107      # POISON
    addi x21, x0, -1107      # POISON
nt_bne_done:

    # BLT not taken: 2 < 1 is false
    blt  x2, x1, nt_blt_skip
    addi x12, x0, 12
    addi x22, x0, 22
    jal  x0, nt_blt_done
nt_blt_skip:
    addi x12, x0, -1107      # POISON
    addi x22, x0, -1107      # POISON
nt_blt_done:

    # BGE not taken: 1 >= 2 is false
    bge  x1, x2, nt_bge_skip
    addi x13, x0, 13
    addi x23, x0, 23
    jal  x0, nt_bge_done
nt_bge_skip:
    addi x13, x0, -1107      # POISON
    addi x23, x0, -1107      # POISON
nt_bge_done:

    # BLTU not taken: 2 <u 1 is false
    bltu x2, x1, nt_bltu_skip
    addi x14, x0, 14
    addi x24, x0, 24
    jal  x0, nt_bltu_done
nt_bltu_skip:
    addi x14, x0, -1107      # POISON
    addi x24, x0, -1107      # POISON
nt_bltu_done:

    # BGEU not taken: 1 >=u 2 is false
    bgeu x1, x2, nt_bgeu_skip
    addi x15, x0, 15
    addi x25, x0, 25
    jal  x0, nt_bgeu_done
nt_bgeu_skip:
    addi x15, x0, -1107      # POISON
    addi x25, x0, -1107      # POISON
nt_bgeu_done:

halt:
    jal  x0, halt
