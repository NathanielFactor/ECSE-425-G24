-- 1 GHz clock, 2000-cycle reset (lets the loader finish), then 10000
-- cycles of execution, then a dump pulse, then stop on assert false.

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

    signal clk   : std_logic := '0';
    signal reset : std_logic := '0';
    signal dump  : std_logic := '0';
    signal done  : std_logic;
    constant CLK_PERIOD : time := 1 ns;     -- 1 GHz
begin
    cpu: processor
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
        wait for 2000 * CLK_PERIOD;   -- loader runs during reset
        reset <= '0';
        wait for 10000 * CLK_PERIOD;  -- run
        dump <= '1';
        wait for CLK_PERIOD;
        dump <= '0';
        wait until done = '1';
        wait for 2 * CLK_PERIOD;
        report "done" severity note;
        assert false report "stop" severity failure;
        wait;
    end process;
end tb;
