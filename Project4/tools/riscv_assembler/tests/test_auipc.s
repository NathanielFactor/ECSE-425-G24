# auipc returns PC + (imm<<12). Different PCs -> different results.
# expect: x1=0  x2=4100  x3=8200  x4=12

main:
    auipc x1, 0          # PC=0
    auipc x2, 1          # PC=4   -> 4 + 4096
    auipc x3, 2          # PC=8   -> 8 + 8192
    auipc x4, 0          # PC=12
halt:
    jal   x0, halt
