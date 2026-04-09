-- ============================================================================
-- processor_tb.vhd  --  top-level simulation harness
-- ============================================================================
-- Spec-mandated behaviour, in order:
--
--   1. Drive a 1 GHz clock (1 ns period) for the entire simulation.
--   2. Hold `reset` high for 2000 cycles. The processor's load_program
--      process consumes one rising edge per word; 2000 cycles is plenty
--      of headroom for the 1024-instruction maximum the spec allows.
--   3. Drop reset and let the processor run for exactly 10000 cycles --
--      the assignment guarantees no test program will need more.
--   4. Pulse `dump` for one cycle. processor.vhd's dump_proc reacts by
--      writing register_file.txt and memory.txt, then asserting `done`.
--   5. Wait for `done`, then stop the simulation with a severity-failure
--      assert. (testbench.tcl runs `run -all`, which returns when this
--      assert fires.)
--
-- The assertion-as-stop pattern is a ModelSim/Questa idiom; std.env.finish
-- would be cleaner under VHDL-2008 but isn't supported uniformly across
-- the lab machines.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity processor_tb is
end processor_tb;

architecture tb of processor_tb is
    component processor is
        generic(
            DATA_RAM_SIZE   :   integer:=32768;
            INSTR_RAM_SIZE  :   integer:=4096);
        port(
            clock   :   in std_logic;
            reset   :   in std_logic;
            dump    :   in std_logic;
            done    :   out std_logic
        );
    end component;

    -- init signals and constants
    signal clk   : std_logic := '0';
    signal reset : std_logic := '0';
    signal dump  : std_logic := '0';
    signal done  : std_logic;
    constant CLK_PERIOD : time := 1 ns;
begin
    dut: processor
        generic map(
            DATA_RAM_SIZE => 32768,
            INSTR_RAM_SIZE => 4096)
        port map(
            clock => clk,
            reset => reset,
            dump => dump,
            done => done
        );

    clk_gen: process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    test_seq: process
    begin
        reset <= '1';
        wait for 2000 * CLK_PERIOD;   -- covers program loading
        reset <= '0';
        wait for 10000 * CLK_PERIOD;  -- run processor
        dump <= '1';
        wait for CLK_PERIOD;
        dump <= '0';
        wait until done = '1';
        wait for 2 * CLK_PERIOD;
        report "===== SIMULATION COMPLETE =====" severity note;
        assert false report "Stopping simulation." severity failure;
        wait;
    end process;
end tb;
