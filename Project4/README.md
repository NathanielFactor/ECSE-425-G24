# Project 4 - Pipelined RISC-V

5-stage pipelined RV32I subset + `mul` (RV32M), in VHDL. Hazard detection
stalls in ID, no forwarding. Branches resolve in EX, take effect in MEM.

## Layout

```
Project4/
├── README.md
├── testbench.tcl       run script (vsim -do testbench.tcl)
├── program.txt         binary program loaded into imem
├── src/                RTL
│   ├── processor.vhd
│   ├── alu.vhd
│   ├── regfile.vhd
│   ├── hazard_control.vhd
│   └── memory.vhd      (PD3 model)
├── sim/
│   └── processor_tb.vhd
└── tools/
    └── riscv_assembler/    bundled assembler + .s tests
```

## Run

From `Project4/`:

```sh
vsim -do testbench.tcl
```

After it finishes you'll have:

- `register_file.txt` - 32 lines, x0..x31, MSB-first binary
- `memory.txt`        - 8192 lines, one word per dmem slot

Both get overwritten each run and aren't checked in.

Clock is 1 GHz. Reset is held for 2000 cycles to let the loader push
`program.txt` into imem, then the processor runs for 10000 cycles
before the dump.

## Test programs

Under `tools/riscv_assembler/tests/`. Each `.s` has a header comment
listing the expected register state on exit.

| file | what it covers |
| ---- | -------------- |
| test_alu.s | every R/I-type ALU op + mul |
| test_neg.s | signed arithmetic with negatives |
| test_mul_signed.s | mul with negative inputs / 7-digit result |
| test_branches.s | all six branch flavours, each taken |
| test_fwd_branch.s | forward branch over a poison instr |
| test_branch_backward.s | sum 1..10 backward branch loop |
| test_jalr.s | jal/jalr call-return |
| test_jalr_indirect.s | jalr through auipc+addi target |
| test_upper_jump.s | upper-imm + jump combos |
| test_lui_addi_const.s | build 32-bit constants with lui+addi |
| test_auipc.s | auipc result vs PC at multiple addrs |
| test_ldst.s | basic store/load round-trip |
| test_mem.s | every load/store width + sign/zero ext |
| test_store_load_round.s | sub-word reads of a known byte pattern |
| test_load_use_chain.s | back-to-back load-use stalls |
| test_hazard_stall.s | RAW chain + load-use hazard |
| test_raw.s | tight RAW deps |
| test_x0_protect.s | writes to x0 ignored on every path |
| test_sum.s | small straight-line sum |

To build a test and run it on the processor:

```sh
cd tools/riscv_assembler/tests
python3 build_all.py                          # assemble all
python3 build_all.py --install test_branches  # also drops result in ../../../program.txt
cd ../../..
vsim -do testbench.tcl
```

`factorial.s` is one level up because it's the assignment's example
program.

## Instructions implemented

The 23 from the assignment Appendix plus `mul`:

```
add  sub  mul  or   and  sll  srl  sra
addi xori ori  andi slti
lw   sw
beq  bne  blt  bge
jal  jalr
lui  auipc
```

`alu.vhd` also handles `slt`, `sltu`, `slli`, `srli`, `srai`, `sltiu`,
`lb`, `lh`, `lbu`, `lhu`, `sb`, `sh`, `bltu`, `bgeu`. Not required, but
the decoding fell out of the same case statements.

## A few notes

- imem and dmem are each 4 banks of `memory.vhd` (one byte lane each).
- `memory.vhd` has 1-cycle read latency, so `imem_addr` is driven from
  `pc_nxt` (one ahead of `pc`) and `fetch_valid` covers the bubble after
  reset and after a flush.
- The regfile writes on the falling edge, so a producer in WB is visible
  to the consumer in ID the same cycle. That's why the hazard detector
  doesn't have to stall on a MEM/WB producer.
