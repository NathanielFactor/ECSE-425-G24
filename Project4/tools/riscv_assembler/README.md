# Bundled RISC-V assembler

A small Python assembler for the RV32I subset our processor implements,
plus the `mul` instruction from RV32M. The output format is exactly what
`processor.vhd`'s loader process expects: one 32-bit word per line, MSB
first, addresses ascending from 0.

## Layout

```
riscv_assembler/
├── README.md              you are here
├── __init__.py            convenience entry point used by the existing
│                          examples; not needed if you import convert
│                          directly
├── convert.py             AssemblyConverter -- the public surface
├── parse.py               line tokeniser, label resolver
├── instr_arr.py           instruction tables + per-format encoders
├── data/
│   ├── instr_data.dat     opcode / funct3 / funct7 lookup table
│   └── reg_map.dat        ABI name -> xN aliases
├── factorial.s            the assignment's example program
└── tests/                 the regression test suite (see below)
    ├── build_all.py
    └── test_*.s           19 small programs, each with a header comment
                           documenting expected register state on exit
```

## Quick start

Assemble a single file from the project root:

```sh
cd Project4/tools/riscv_assembler
python3 -c "import sys; sys.path.insert(0,'.'); \
    from convert import AssemblyConverter as AC; \
    AC(output_mode='f')('factorial.s', '../../program.txt')"
```

Or use the test runner under `tests/`, which knows where to drop the
binary so a follow-up `vsim -do testbench.tcl` picks it up automatically:

```sh
cd Project4/tools/riscv_assembler/tests
python3 build_all.py                          # assemble every test, summary
python3 build_all.py test_branches            # just one
python3 build_all.py --install test_branches  # plus copy result over
                                              # ../../../program.txt
```

## Supported syntax

- Comments start with `#` and run to end-of-line. Lines that *start*
  with `#` are not allowed -- the comment must follow some code on
  that line, or the line must be entirely blank.
- Blank lines are fine. Whitespace inside a line is collapsed.
- Labels are an identifier ending with `:`, on a line by themselves.
- Numbered registers (`x0` .. `x31`) and ABI names (`zero`, `ra`, `sp`,
  `gp`, `tp`, `t0`..`t6`, `s0`..`s11`, `a0`..`a7`, `fp`) are both
  accepted -- see `data/reg_map.dat` for the full table.
- Branches and jumps take label operands; the assembler computes the
  byte offset for you.
- Loads and stores use the standard `lw rd, imm(rs1)` /
  `sw rs2, imm(rs1)` form. The "comma-separated triple" form some of
  the older test programs used does not parse.
- Pseudo-ops handled: `nop`, `mv`, `not`, `neg`, `j`, `li` (note: `li`
  is currently a thin wrapper around `lui` and does not emit the
  `addi` half, so it only works for values whose lower 12 bits are 0).

## Notes for the curious

Two upstream bugs were fixed in this fork:

- `slt`, `lh`, and `srli` were missing from the instruction tables in
  `instr_arr.py` even though their opcodes were present in
  `data/instr_data.dat`. They are now restored. (`srli` was also
  spelled `slri` in the data file -- that has been corrected too.)
- The B-type and J-type immediate encoders used to pack the byte
  offset directly into `imm[11:0]` / `imm[19:0]`, which is one bit
  off from the standard RISC-V layout (where the LSB is implicit and
  the field actually carries `imm[12:1]` / `imm[20:1]`). They now
  emit the standard scrambled encoding from the Reference Data card,
  matching the immediate generator in `Project4/src/alu.vhd`.
