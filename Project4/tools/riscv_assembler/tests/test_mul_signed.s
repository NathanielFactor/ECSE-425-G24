# mul with negative inputs and a 7-digit result.
# expect: x3=-15  x6=-90000  x9=12345000

main:
    addi x1, x0, -3
    addi x2, x0, 5
    mul  x3, x1, x2          # -15

    addi x4, x0, -300
    addi x5, x0, 300
    mul  x6, x4, x5          # -90000

    lui  x7, 3
    addi x7, x7, 57          # 12345
    addi x8, x0, 1000
    mul  x9, x7, x8          # 12345000
halt:
    jal  x0, halt
