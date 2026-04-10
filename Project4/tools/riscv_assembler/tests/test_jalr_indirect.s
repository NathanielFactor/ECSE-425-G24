# compute func address with auipc+addi, call via jalr (function-pointer style)
# expect: x5=24  x1=16  x10=43

main:
    auipc x5, 0          # x5 = 0
    addi  x5, x5, 24     # x5 = address of func
    addi  x10, x0, 0
    jalr  x1, x5, 0      # x1 = 16, jump to x5
    addi  x10, x10, 1    # runs after return: 42 + 1
halt:
    jal   x0, halt

func:
    addi  x10, x0, 42
    jalr  x0, x1, 0      # return
