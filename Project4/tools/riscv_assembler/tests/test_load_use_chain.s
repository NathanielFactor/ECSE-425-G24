# back-to-back load-use stalls.
# stores 11/22/33 then loads them, each immediately consumed.
# expect: x10=11  x11=22  x12=22  x13=33  x14=33  x15=66

main:
    addi x1, x0, 11
    addi x2, x0, 22
    addi x3, x0, 33
    sw   x1, 0(x0)
    sw   x2, 4(x0)
    sw   x3, 8(x0)

    lw   x10, 0(x0)
    add  x11, x10, x10     # uses x10 immediately

    lw   x12, 4(x0)
    add  x13, x12, x10

    lw   x14, 8(x0)
    add  x15, x14, x13
halt:
    jal  x0, halt
