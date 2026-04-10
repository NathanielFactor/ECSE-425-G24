# Project 4 — Pipelined RISC-V Processor

A five-stage (IF / ID / EX / MEM / WB) pipelined implementation of an RV32I
subset (plus `mul` from RV32M), written in VHDL. Hazard detection stalls in
ID; there is no forwarding. Branches resolve in EX and take effect in MEM,
giving the textbook three-cycle branch penalty described in Hennessy &
Patterson 7e Appendix C (Figures C.19 and C.20).

## Layout

```
Project4/
├── README.md              this file
├── testbench.tcl          grader entrypoint -- `vsim -do testbench.tcl`
├── program.txt            binary program loaded into instruction memory
│
├── src/                   synthesisable RTL
│   ├── processor.vhd      top level: pipeline regs, stage logic, memory glue
│   ├── alu.vhd            immediate generator + ALU + branch comparator
│   ├── regfile.vhd        32 x 32-bit architectural register file (x0 = 0)
│   ├── hazard_control.vhd RAW stall detection + branch/jump flush logic
│   └── memory.vhd         byte-wide synchronous SRAM model (from PD3)
│
├── sim/                   simulation-only
│   └── processor_tb.vhd   clock/reset/dump harness; stops after 10k cycles
│
└── tools/
    └── riscv_assembler/   bundled Python assembler + sample .s programs
```

The split between `src/` and `sim/` is intentional:

- Anything in `src/` is RTL that could, in principle, be synthesised. The
  memory model is an exception — it's a simulation behavioural model — but
  it lives in `src/` because the processor instantiates it as a component,
  not because it's real hardware.
- Anything in `sim/` is simulation-only glue. The testbench entity is the
  only thing here today; any future waveform scripts or golden-reference
  comparison harnesses would go here too.
- `tools/` is for host-side utilities that aren't involved in the
  simulation at all — the bundled Python assembler lives there.

The grader's entrypoint (`testbench.tcl`) and the program input
(`program.txt`) both sit at the `Project4/` root on purpose: `vsim -do
testbench.tcl` is run from there, and the VHDL loader opens
`"program.txt"` relative to the simulation's current working directory.

## How to run

From `Project4/`:

```sh
vsim -do testbench.tcl
```

The script compiles the RTL in dependency order (leaves first, processor,
then testbench), elaborates `processor_tb`, runs until the testbench
self-terminates, and quits. Two output files appear in this directory
when it's done:

- `register_file.txt` — 32 lines, one 32-bit binary word per register (x0..x31)
- `memory.txt`        — 8192 lines, one word per 4-byte data-memory slot

Both are overwritten on every run; neither is checked in (see the root
`.gitignore`).

The clock is 1 GHz (1 ns period). Reset is held for 2000 cycles so the
program loader has time to push `program.txt` into instruction memory,
then the processor runs for 10 000 cycles before the dump phase begins.

## Assembling new programs

The bundled assembler under `tools/riscv_assembler/` produces the binary
text format the processor expects (one 32-bit word per line, MSB first,
addresses ascending):

```sh
cd tools/riscv_assembler
python3 -c "import sys; sys.path.insert(0,'.'); \
    from convert import AssemblyConverter as AC; \
    AC(output_mode='f')('factorial.s', '../../program.txt')"
```

The assembler emits standard RISC-V machine code per the Reference Data
card — in particular, B-type and J-type immediates use the standard
scrambled encoding with the LSB implicit. The ALU's immediate generator
decodes them the same way, so the two halves stay in sync.

> **Note:** the assembler accepts the subset listed in
> `tools/riscv_assembler/README.md` (numbered registers `x0..x31`, ABI
> names like `a0`/`t0`/`ra`, labels, comments, the `mv`/`not`/`neg`/`j`/
> `li` pseudo-ops). If you write programs by hand, stick to that subset.

## Test programs

The regression suite lives under `tools/riscv_assembler/tests/` and
exercises every required instruction plus the corner cases that have
historically broken pipelined implementations. Each `.s` file has a
header comment that lists the expected register-file state on exit, so
you can spot-check a run by diff-ing the relevant lines of
`register_file.txt`.

Coverage so far (19 tests, all of which assemble cleanly with the
bundled assembler):

| File                       | What it exercises                             |
| -------------------------- | --------------------------------------------- |
| `test_alu.s`               | every R-type and I-type ALU op + `mul`        |
| `test_neg.s`               | signed arithmetic with negative operands      |
| `test_mul_signed.s`        | `mul` with negative inputs and large products |
| `test_branches.s`          | all six branch flavours, each taken           |
| `test_fwd_branch.s`        | forward branch skipping a poison instruction  |
| `test_branch_backward.s`   | backward branch loop, sum 1..10               |
| `test_jalr.s`              | jal/jalr call-and-return                      |
| `test_jalr_indirect.s`     | jalr through a computed (auipc+addi) target   |
| `test_upper_jump.s`        | upper-immediate + jump combinations           |
| `test_lui_addi_const.s`    | building 32-bit constants with lui+addi       |
| `test_auipc.s`             | auipc result vs. PC at multiple addresses     |
| `test_ldst.s`              | basic store / load round-trip                 |
| `test_mem.s`               | every load/store width + sign/zero extension  |
| `test_store_load_round.s`  | sub-word reads from a known byte pattern      |
| `test_load_use_chain.s`    | back-to-back load-use stalls                  |
| `test_hazard_stall.s`      | RAW chain + load-use hazard                   |
| `test_raw.s`               | tight RAW dependencies                        |
| `test_x0_protect.s`        | writes to x0 must be ignored on every path    |
| `test_sum.s`               | small straight-line sum                       |

Build and install one of them with the runner:

```sh
cd tools/riscv_assembler/tests
python3 build_all.py                          # assemble all, print summary
python3 build_all.py --install test_branches  # also overwrites ../../program.txt
cd ../../..
vsim -do testbench.tcl                        # run it on the processor
```

`factorial.s` (the assignment's worked example) lives one directory up
because the assignment write-up references it directly.

## Implemented instructions

The 23 from the project Appendix plus `mul` from RV32M:

```
add  sub  mul  or   and  sll  srl  sra  slt
addi xori ori  andi slti
lw   sw
beq  bne  blt  bge
jal  jalr
lui  auipc
```

A handful of extras (`sltu`, `slli`/`srli`/`srai`, `lb`/`lh`/`lbu`/`lhu`,
`sb`/`sh`, `bltu`/`bgeu`) are wired up in `alu.vhd` as well, because their
encoding fell out cleanly from the same case statements. They aren't
required for grading, but they won't break anything if a test happens to
use them.

## Design notes worth knowing

A few things that are non-obvious from just reading the code:

- **Byte-bank memories.** Both the instruction memory (4 KiB) and the data
  memory (32 KiB) are built from four parallel instances of `memory.vhd`,
  one per byte lane. Bank *k* holds byte *k* of every aligned word, so a
  word access fans out to all four banks and a sub-word access touches
  only the lane it needs. This is cleaner than a single wide port when the
  underlying memory model is byte-addressed.

- **Fetch timing.** `memory.vhd` has a 1-cycle read latency: it registers
  the address on `rising_edge` and drives `readdata` combinationally from
  the registered value. To keep IF aligned with PC, we drive `imem_addr`
  from `pc_nxt` rather than `pc`, so the address that *will* become the
  current PC next cycle is the one already sitting in the memory's
  register. `fetch_valid` is the one-bit "wait one cycle while imem
  catches up" flag that kicks in after reset and after every taken branch.

- **No forwarding, but no two-cycle stall for ALU→ALU either.** The
  register file writes on the *falling* edge, so WB and ID overlap inside
  a single cycle: WB writes in the first half, ID reads in the second.
  That means as soon as a producer reaches WB its result is visible to
  the dependent instruction in ID, and `hazard_control.vhd` only has to
  stall while the producer is still in EX/MEM. The comments in
  `regfile.vhd` and `hazard_control.vhd` walk through this in more detail.
