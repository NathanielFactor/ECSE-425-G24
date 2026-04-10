# test_jalr_indirect.s
# ----------------------------------------------------------------------------
# Function-pointer style call. Instead of `jal func` (which encodes the
# target as a PC-relative immediate), we compute the target address into
# a register at run time and dispatch through `jalr`. This is what a real
# compiler emits for calls through a vtable, a function pointer, or a
# computed goto.
#
# Address layout:
#   0x00  auipc x5, 0       (x5 = 0)
#   0x04  addi  x5, x5, 24  (x5 = 24, address of `func`)
#   0x08  addi  x10, x0, 0  (x10 = 0)
#   0x0C  jalr  x1, x5, 0   (PC <- 24, x1 <- 0x10)
#   0x10  addi  x10, x10, 1 (return target -- runs after func)
#   0x14  jal   x0, halt
#   0x18  addi  x10, x0, 42 (`func`)
#   0x1C  jalr  x0, x1, 0   (return)
#
# Expected:
#   x5  = 24
#   x1  = 16    (the return address jalr stashed)
#   x10 = 43    (= 42 set by func, then +1 from the return path)

main:
    auipc x5, 0
    addi  x5, x5, 24
    addi  x10, x0, 0
    jalr  x1, x5, 0
    addi  x10, x10, 1
halt:
    jal   x0, halt

func:
    addi  x10, x0, 42
    jalr  x0, x1, 0
