# test_alu.s
# Tests every R-type and I-type ALU instruction plus mul
# Expected results:
#   x1=10  x2=3   x3=13  x4=7   x5=2   x6=11  x7=9
#   x8=8   x9=2   x10=-8 x11=-1 x12=1  x13=1  x14=30
#   x15=7  x16=10 x17=15 x18=5  x19=12 x20=5  x21=-4
#   x22=1  x23=1

    addi x1,  x0,  10    # x1  = 10
    addi x2,  x0,  3     # x2  = 3

    # R-type
    add  x3,  x1,  x2    # x3  = 10 + 3  = 13
    sub  x4,  x1,  x2    # x4  = 10 - 3  = 7
    and  x5,  x1,  x2    # x5  = 10 & 3  = 2
    or   x6,  x1,  x2    # x6  = 10 | 3  = 11
    xor  x7,  x1,  x2    # x7  = 10 ^ 3  = 9
    addi x8,  x0,  1     # x8  = 1
    sll  x8,  x8,  x2    # x8  = 1 << 3  = 8
    addi x9,  x0,  16    # x9  = 16
    srl  x9,  x9,  x2    # x9  = 16 >> 3 = 2  (logical)
    addi x10, x0,  -8    # x10 = -8
    sra  x11, x10, x2    # x11 = -8 >> 3 = -1 (arithmetic)
    slt  x12, x2,  x1    # x12 = (3 < 10) = 1
    sltu x13, x2,  x1    # x13 = (3 <u 10) = 1
    mul  x14, x1,  x2    # x14 = 10 * 3  = 30

    # I-type
    addi x15, x1,  -3    # x15 = 10 - 3  = 7
    andi x16, x1,  15    # x16 = 10 & 15 = 10
    ori  x17, x2,  12    # x17 = 3 | 12  = 15
    xori x18, x1,  15    # x18 = 10 ^ 15 = 5
    slli x19, x2,  2     # x19 = 3 << 2  = 12
    srli x20, x1,  1     # x20 = 10 >> 1 = 5
    srai x21, x10, 1     # x21 = -8 >> 1 = -4 (arithmetic)
    slti  x22, x2, 10    # x22 = (3 < 10)  = 1
    sltiu x23, x2, 10    # x23 = (3 <u 10) = 1

halt:
    jal  x0, halt
