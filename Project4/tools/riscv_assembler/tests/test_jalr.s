# test_jalr.s
# JAL jumps to subroutine, JALR returns
# Expected: x10=107  x1=8 (return address)

    addi x10, x0, 0     # x10 = 0
    jal  x1, func       # jump to func, x1 = return address (= addr of next instr)
    addi x10, x10, 100  # x10 = x10 + 100  (runs after return)

halt:
    jal  x0, halt

func:
    addi x10, x10, 7    # x10 = 0 + 7 = 7
    jalr x0, x1, 0      # return to caller (jump to address in x1)
