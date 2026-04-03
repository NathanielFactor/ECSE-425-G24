-- ============================================================================
-- memory.vhd — Adapted from PD3 memory model
-- ============================================================================
-- Modifications from PD3 original:
--   1. init_zero generic: when true, memory is initialized to all zeros
--      (required for data memory per project spec). When false, memory is
--      initialized to to_unsigned(i,8) (original PD3 behavior).
--   2. mem_delay defaults to 0 ns for single-cycle pipeline operation
--      (spec allows: "you may alter the memory model as you see fit").
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity memory is
    generic(
        ram_size     : integer := 32768;
        mem_delay    : time    := 0 ns;
        clock_period : time    := 1 ns;
        init_zero    : boolean := true      -- true = zeros, false = PD3 default
    );
    port(
        clock       : in  std_logic;
        writedata   : in  std_logic_vector(7 downto 0);
        address     : in  integer range 0 to ram_size - 1;
        memwrite    : in  std_logic;
        memread     : in  std_logic;
        readdata    : out std_logic_vector(7 downto 0);
        waitrequest : out std_logic
    );
end memory;

architecture rtl of memory is
    type mem_t is array(ram_size - 1 downto 0) of std_logic_vector(7 downto 0);
    signal ram_block         : mem_t;
    signal read_address_reg  : integer range 0 to ram_size - 1;
    signal write_waitreq_reg : std_logic := '1';
    signal read_waitreq_reg  : std_logic := '1';
begin

    mem_process: process(clock)
    begin
        -- Initialization at simulation start
        if now < 1 ps then
            if init_zero then
                for i in 0 to ram_size - 1 loop
                    ram_block(i) <= (others => '0');
                end loop;
            else
                for i in 0 to ram_size - 1 loop
                    ram_block(i) <= std_logic_vector(to_unsigned(i mod 256, 8));
                end loop;
            end if;
        end if;

        -- Synchronous write and address registration
        if clock'event and clock = '1' then
            if memwrite = '1' then
                ram_block(address) <= writedata;
            end if;
            read_address_reg <= address;
        end if;
    end process;

    -- Asynchronous read from registered address
    readdata <= ram_block(read_address_reg);

    -- Waitrequest generation (same as PD3)
    waitreq_w_proc: process(memwrite)
    begin
        if memwrite'event and memwrite = '1' then
            write_waitreq_reg <= '0' after mem_delay,
                                  '1' after mem_delay + clock_period;
        end if;
    end process;

    waitreq_r_proc: process(memread)
    begin
        if memread'event and memread = '1' then
            read_waitreq_reg <= '0' after mem_delay,
                                 '1' after mem_delay + clock_period;
        end if;
    end process;

    waitrequest <= write_waitreq_reg and read_waitreq_reg;

end rtl;
