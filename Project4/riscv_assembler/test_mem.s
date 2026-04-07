# test_mem.s
# Tests all load/store widths and sign/zero extension
# Expected:
#   x3 = -1    (lb  sign-extends 0xFF)
#   x4 = 255   (lbu zero-extends 0xFF)
#   x6 = -1    (lh  sign-extends 0xFFFF)
#   x7 = 65535 (lhu zero-extends 0xFFFF)
#   x9 = 2047  (lw  full word)

    addi x2, x0, -1      # x2 = 0xFFFFFFFF

    sb   x0, x2, 0       # mem[0]   = 0xFF  (store low byte)
    lb   x3, 0(x0)       # x3 = sign_ext(0xFF) = -1
    lbu  x4, 0(x0)       # x4 = zero_ext(0xFF) = 255

    sh   x0, x2, 4       # mem[4:5] = 0xFFFF (store low halfword)
    lh   x6, 4(x0)       # x6 = sign_ext(0xFFFF) = -1
    lhu  x7, 4(x0)       # x7 = zero_ext(0xFFFF) = 65535

    addi x8, x0, 2047    # x8 = 2047
    sw   x0, x8, 8       # mem[8:11] = 2047
    lw   x9, 8(x0)       # x9 = 2047

halt:
    jal  x0, halt
