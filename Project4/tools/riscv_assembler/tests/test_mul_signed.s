# test_mul_signed.s
# ----------------------------------------------------------------------------
# `mul` returns the low 32 bits of (rs1 * rs2) and is supposed to give the
# same answer regardless of the sign interpretation -- so we don't need a
# separate signed/unsigned variant for the low half. This test pokes at
# negative operands and at a result big enough that you'd notice if the
# multiplier silently zero-extended its inputs.
#
# Expected:
#   x3 = -15           (-3 * 5)
#   x6 = -90000        (-300 * 300)
#   x9 = 12345000      (12345 * 1000)

main:
    addi x1, x0, -3
    addi x2, x0, 5
    mul  x3, x1, x2          # -3 * 5 = -15

    addi x4, x0, -300
    addi x5, x0, 300
    mul  x6, x4, x5          # -300 * 300 = -90000

    # Build 12345 in x7 with the lui+addi idiom (3*4096 = 12288, +57 = 12345)
    lui  x7, 3
    addi x7, x7, 57
    addi x8, x0, 1000
    mul  x9, x7, x8          # 12345 * 1000 = 12345000
halt:
    jal  x0, halt
