# test_upper_jump.s
# Tests LUI, AUIPC, JAL (skip), JALR (indirect jump)
# Expected: x1=0x12345000  x2=4100  x3=12  x4=42  x5=32  x6=28  x7=99

    lui   x1, 74565      # x1 = 74565 << 12 = 0x12345000
    auipc x2, 1          # x2 = PC + (1 << 12) = 4 + 4096 = 4100

    jal   x3, skip1      # x3 = return addr, jump over poison
    addi  x9, x0, -1107  # POISON - never runs

skip1:
    addi  x4, x0, 42     # x4 = 42

    addi  x5, x0, 32     # x5 = address of target (byte 32 = instruction 8)
    jalr  x6, x5, 0      # x6 = return addr, jump to address in x5
    addi  x9, x0, -1107  # POISON - never runs

target:
    addi  x7, x0, 99     # x7 = 99

halt:
    jal   x0, halt
