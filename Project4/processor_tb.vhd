-- ============================================================================
-- processor_tb.vhd — Testbench for Pipelined RISC-V Processor
-- ============================================================================
-- 1. Clock at 1 GHz (1 ns period), runs continuously.
-- 2. Hold reset for 2000 cycles (covers program loading phase).
-- 3. Run processor for 10,000 cycles.
-- 4. Assert dump → wait for done → stop simulation.
-- Output: register_file.txt (32 lines), memory.txt (8192 lines)
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
