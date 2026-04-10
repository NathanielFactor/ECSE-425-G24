-- ============================================================================
-- regfile.vhd  --  32 x 32-bit RISC-V architectural register file
-- ============================================================================
-- Two combinational read ports (rs1, rs2) and one write port (rd). The write
-- happens on the *falling* edge of the clock, which is the standard trick for
-- a no-forwarding pipeline: WB writes in the first half of a cycle, ID reads
-- in the second half, so a value produced two stages ahead is visible to the
-- dependent instruction without any extra forwarding mux.
--
-- x0 is forced to zero on three independent paths: the write guard, the
-- combinational read mux, and the dump-port mux. Belt and braces -- so that
-- nothing in the pipeline can ever observe a non-zero value for x0.
-- ============================================================================

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
    -- Write port: falling-edge clocked, with the x0 guard right next to the
    -- write so it cannot drift apart from the rest of the file.
    write_port: process(clock, reset)
    begin
        if reset = '1' then
            regs <= (others => (others => '0'));
        elsif falling_edge(clock) then
            if wr_en = '1' and rd_addr /= 0 then
                regs(rd_addr) <= rd_data;
            end if;
            -- Re-pin x0 every cycle. Cheap, and it makes any accidental
            -- write to regs(0) elsewhere in the design self-correct on the
            -- next falling edge.
            regs(0) <= (others => '0');
        end if;
    end process;

    -- Read ports are pure muxes (no clock). The "= 0" branches make the x0
    -- behaviour explicit even before regs(0) has been clocked once -- this
    -- matters during the very first cycle out of reset.
    rs1_data  <= (others => '0') when rs1_addr  = 0 else regs(rs1_addr);
    rs2_data  <= (others => '0') when rs2_addr  = 0 else regs(rs2_addr);
    dump_data <= (others => '0') when dump_addr = 0 else regs(dump_addr);
end rtl;