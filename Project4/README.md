# Project 4 — Pipelined RISC-V Processor

A five-stage (IF / ID / EX / MEM / WB) pipelined implementation of an RV32I
subset (plus `mul` from RV32M), in VHDL. Hazard detection stalls in ID; no
forwarding. Branches resolve in EX and take effect in MEM, giving the textbook
three-cycle branch penalty (H&P 7e, App. C, Fig. C.19/C.20).

## Files

| File                | Purpose                                                  |
| ------------------- | -------------------------------------------------------- |
| `processor.vhd`     | Top-level: pipeline registers, stage logic, memory glue  |
| `alu.vhd`           | Combinational ALU + immediate generator + branch compare |
| `regfile.vhd`       | 32-entry register file; `x0` hard-wired to zero          |
| `memory.vhd`        | PD3 byte-addressable RAM model (used 4× per memory)      |
| `hazard_control.vhd`| RAW stall detection + branch/jump flush logic            |
| `processor_tb.vhd`  | Testbench wrapper: clock, reset, dump handshake          |
| `testbench.tcl`     | ModelSim/Questa script (compile + run)                   |
| `program.txt`       | Sample program — factorial (replace with grader's input) |
| `riscv_assembler/`  | Bundled Python assembler (use to produce `program.txt`)  |

## How to run

From this directory:

```sh
vsim -do testbench.tcl
```

The script compiles the VHDL sources in dependency order, elaborates
`processor_tb`, runs simulation until the testbench self-terminates, and
quits. After the run you should see two new files in this directory:

- `register_file.txt` — 32 lines, one 32-bit binary word per register (x0..x31)
- `memory.txt`        — 8192 lines, one word per 4-byte slot of data memory

The clock is 1 GHz (1 ns period). Reset is asserted for 2000 cycles to give
the loader process time to push `program.txt` into instruction memory, then
the processor runs for 10 000 cycles before the dump phase begins.

## Assembling new programs

The bundled Python assembler under `riscv_assembler/` produces the binary
text format expected by `processor.vhd`'s loader (one 32-bit word per line,
MSB first, in ascending address order):

```sh
cd riscv_assembler
python3 -c "import sys; sys.path.insert(0,'.'); \
    from convert import AssemblyConverter as AC; \
    AC(output_mode='f')('factorial.s', '../program.txt')"
```

The assembler emits standard RISC-V machine code as documented on the
Reference Data card; in particular, branch (B-type) and jump (J-type)
immediates use the standard scrambled encoding with the LSB implicit. The
ALU's immediate generator decodes them the same way, so the two halves stay
in sync.

> **Note:** the assembler accepts the subset listed in
> `riscv_assembler/README.md` (numbered registers `x0..x31`, ABI names like
> `a0`/`t0`/`ra`, labels, comments, the `mv`/`not`/`neg`/`j`/`li` pseudo-ops).
> If you write programs by hand, stick to that subset.

## Implemented instructions

23 RV32I + `mul` from RV32M:

```
add  sub  mul  or   and  sll  srl  sra  slt
addi xori ori  andi slti
lw   sw
beq  bne  blt  bge
jal  jalr
lui  auipc
```

A handful of extras (`sltu`, `slli`/`srli`/`srai`, `lb`/`lh`/`lbu`/`lhu`,
`sb`/`sh`, `bltu`/`bgeu`) are also wired up in `alu.vhd` since the encoding
fell out cleanly — they aren't required for grading but won't break anything
if a test happens to use them.
