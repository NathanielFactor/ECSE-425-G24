-- ============================================================================
-- ECSE 425 Project 4: 5-Stage Pipelined RISC-V Processor
-- ============================================================================
-- Implements RV32I subset (23 instructions) + mul from RV32M.
-- Hazard detection with stalling (no forwarding).
-- Branches resolved in EX, take effect entering MEM (3-cycle penalty).
-- Two separate memories: instruction (read-only, loaded from program.txt)
-- and data (32768 bytes, initialized to zeros).
-- Both memories use the PD3 memory model
-- (byte-addressable arrays) with single-cycle access (mem_delay = 0).

-- Name: Nathaniel Factor | 261081015
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity processor is
    generic(
        data_ram_size  : integer := 32768;   -- 32 KB data memory
        instr_ram_size : integer := 4096     -- 4 KB = 1024 instructions max
    );
    port(
        clock : in  std_logic;
        reset : in  std_logic;

        -- Testbench control: assert dump to write output files
        dump  : in  std_logic;
        done  : out std_logic
    );
end processor;

architecture arch of processor is
    -- ========================================================================
    -- OPCODE CONSTANTS (bits [6:0] of instruction)
    -- ========================================================================
    constant OP_LUI    : std_logic_vector(6 downto 0) := "0110111";  -- U-type
    constant OP_AUIPC  : std_logic_vector(6 downto 0) := "0010111";  -- U-type
    constant OP_JAL    : std_logic_vector(6 downto 0) := "1101111";  -- J-type
    constant OP_JALR   : std_logic_vector(6 downto 0) := "1100111";  -- I-type
    constant OP_BRANCH : std_logic_vector(6 downto 0) := "1100011";  -- B-type
    constant OP_LOAD   : std_logic_vector(6 downto 0) := "0000011";  -- I-type
    constant OP_STORE  : std_logic_vector(6 downto 0) := "0100011";  -- S-type
    constant OP_IMM    : std_logic_vector(6 downto 0) := "0010011";  -- I-type
    constant OP_REG    : std_logic_vector(6 downto 0) := "0110011";  -- R-type

    -- NOP encoding: addi x0, x0, 0
    constant NOP : std_logic_vector(31 downto 0) := x"00000013";
begin

end arch;