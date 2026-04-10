# test_store_load_round.s
# ----------------------------------------------------------------------------
# Round-trip a 32-bit pattern through data memory and read it back at every
# width. The pattern 0x12345678 is chosen so each sub-word slice is a
# different non-trivial value -- if the byte lanes are wired up backwards
# we'll see it immediately.
#
# After the program runs:
#   mem[0..3]   = 0x12 0x34 0x56 0x78  (little-endian: byte0=0x78)
#   mem[16..19] = same pattern
#
# Expected register file:
#   x1  = 305419896    (= 0x12345678)
#   x10 = 305419896    (lw from offset 0)
#   x11 = 305419896    (lw from offset 16)
#   x12 = 120          (= 0x78,  lbu of byte 0)
#   x13 = 22136        (= 0x5678, lhu of low half)
#   x14 = 305419896    (lw of full word, sanity)

main:
    # Build 0x12345678 in x1: lui 0x12345 + addi 0x678
    #   0x12345 = 74565 ; lui 74565 -> 0x12345000
    #   0x678   = 1656  ; positive 12-bit, no sign-correction needed
    lui  x1, 74565
    addi x1, x1, 1656

    # Word round-trip at offset 0
    sw   x1, 0(x0)
    lw   x10, 0(x0)

    # Word round-trip at offset 16 (different alignment)
    sw   x1, 16(x0)
    lw   x11, 16(x0)

    # Sub-word reads from offset 0
    lbu  x12, 0(x0)          # low byte  = 0x78 = 120
    lhu  x13, 0(x0)          # low half  = 0x5678 = 22136
    lw   x14, 0(x0)          # full word = 0x12345678
halt:
    jal  x0, halt
