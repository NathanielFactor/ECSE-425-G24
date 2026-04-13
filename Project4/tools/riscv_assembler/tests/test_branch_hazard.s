# test_branch_hazard.s
# Branch operand produced by the immediately preceding instruction (stall required).
# Part A: ALU result into branch.  Part B: load-use into branch.
# Expected: x1=5 x2=3 x3=8 x4=1 x5=42 x6=0 x7=42 x8=2

    # Part A: add writes x3, branch reads x3 immediately (RAW stall)
    addi x1, x0, 5
    addi x2, x0, 3
    add  x3, x1, x2          # x3 = 8
    bne  x3, x1, bha_taken   # 8 != 5 -> taken (stall required)
    addi x9, x0, -1107       # POISON
bha_taken:
    addi x4, x0, 1           # x4 = 1

    # Part B: lw writes x7, branch reads x7 immediately (load-use stall)
    addi x5, x0, 42
    addi x6, x0, 0
    sw   x5, 0(x6)           # mem[0] = 42
    lw   x7, 0(x6)           # x7 = 42
    beq  x7, x5, bhb_taken   # 42 == 42 -> taken (load-use stall required)
    addi x9, x0, -1107       # POISON
bhb_taken:
    addi x8, x0, 2           # x8 = 2

halt:
    jal  x0, halt
