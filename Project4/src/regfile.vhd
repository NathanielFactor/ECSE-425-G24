-- 32 x 32-bit register file. Two combinational read ports, one write port.
-- Write fires on the falling edge so ID can read the new value the same cycle
-- (avoids needing forwarding for MEM/WB -> ID).
-- x0 is forced to zero on every read path and every cycle.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity regfile is
    port(
        clock     : in  std_logic;
        reset     : in  std_logic;
        -- Read ports (combinational)
        rs1_addr  : in  integer range 0 to 31;
        rs2_addr  : in  integer range 0 to 31;
        rs1_data  : out std_logic_vector(31 downto 0);
        rs2_data  : out std_logic_vector(31 downto 0);
        -- Write port (synchronous)
        wr_en     : in  std_logic;
        rd_addr   : in  integer range 0 to 31;
        rd_data   : in  std_logic_vector(31 downto 0);
        -- Dump port (for testbench)
        dump_addr : in  integer range 0 to 31;
        dump_data : out std_logic_vector(31 downto 0)
    );
end regfile;

architecture rtl of regfile is
    type reg_array_t is array(0 to 31) of std_logic_vector(31 downto 0);
    signal regs : reg_array_t := (others => (others => '0'));
begin
    write_port: process(clock, reset)
    begin
        if reset = '1' then
            regs <= (others => (others => '0'));
        elsif falling_edge(clock) then
            if wr_en = '1' and rd_addr /= 0 then
                regs(rd_addr) <= rd_data;
            end if;
            regs(0) <= (others => '0');     -- always
        end if;
    end process;

    rs1_data  <= (others => '0') when rs1_addr  = 0 else regs(rs1_addr);
    rs2_data  <= (others => '0') when rs2_addr  = 0 else regs(rs2_addr);
    dump_data <= (others => '0') when dump_addr = 0 else regs(dump_addr);
end rtl;