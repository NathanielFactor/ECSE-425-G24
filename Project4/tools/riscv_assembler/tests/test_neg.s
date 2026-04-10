# test_neg.s
# Negative number arithmetic: add, sub, slt, mul with negatives
# Expected: x1=-1  x2=-100  x3=-101  x4=1  x5=1  x6=-100

    addi x1, x0, -1     # x1 = -1
    addi x2, x0, -100   # x2 = -100
    add  x3, x1, x2     # x3 = -1 + -100 = -101
    sub  x4, x0, x1     # x4 = 0 - (-1) = 1
    slt  x5, x2, x1     # x5 = (-100 < -1) ? 1 : 0 = 1
    mul  x6, x2, x4     # x6 = -100 * 1 = -100

halt:
    jal  x0, halt
