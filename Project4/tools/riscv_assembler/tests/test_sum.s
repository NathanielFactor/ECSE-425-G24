# test_sum.s
# Compute 1 + 2 + 3 + ... + 10
# Expected: x2 = 55

    addi x1, x0, 10     # x1 = 10 (counter)
    addi x2, x0, 0      # x2 = 0  (accumulator)

loop:
    add  x2, x2, x1     # x2 = x2 + x1
    addi x1, x1, -1     # x1 = x1 - 1
    bne  x1, x0, loop   # if x1 != 0, repeat

halt:
    jal  x0, halt       # infinite loop
