# test_raw.s
# Back-to-back RAW (read-after-write) hazard chain
# Tests that hazard stalling produces correct values
# Expected: x1=1 x2=2 x3=3 x4=4 x5=5 x6=6 x7=30 x8=26

    addi x1, x0, 1      # x1 = 1
    addi x2, x1, 1      # x2 = x1 + 1 = 2   (RAW on x1)
    addi x3, x2, 1      # x3 = x2 + 1 = 3   (RAW on x2)
    addi x4, x3, 1      # x4 = x3 + 1 = 4   (RAW on x3)
    addi x5, x4, 1      # x5 = x4 + 1 = 5   (RAW on x4)
    add  x6, x1, x5     # x6 = 1 + 5 = 6
    mul  x7, x5, x6     # x7 = 5 * 6 = 30
    sub  x8, x7, x4     # x8 = 30 - 4 = 26

halt:
    jal  x0, halt
