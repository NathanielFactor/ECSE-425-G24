# round-trip 0x12345678 through dmem and read it back at every width
# expect: x1=305419896  x10=305419896  x11=305419896
#         x12=120 (0x78)  x13=22136 (0x5678)  x14=305419896

main:
    lui  x1, 74565
    addi x1, x1, 1656        # 0x12345678

    sw   x1, 0(x0)
    lw   x10, 0(x0)

    sw   x1, 16(x0)
    lw   x11, 16(x0)

    lbu  x12, 0(x0)          # low byte
    lhu  x13, 0(x0)          # low half
    lw   x14, 0(x0)
halt:
    jal  x0, halt
