-- cache_tb.vhd
-- Author: Minkyu Park
-- Description: Testbench for cache.vhd (uses memory.vhd, waitrequest-low pulse handshake)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache_tb is
end cache_tb;

architecture behavior of cache_tb is

  component cache is
    generic(
      ram_size : INTEGER := 32768
    );
    port(
      clock : in std_logic;
      reset : in std_logic;

      -- Avalon slave 
      s_addr        : in  std_logic_vector (31 downto 0);
      s_read        : in  std_logic;
      s_readdata    : out std_logic_vector (31 downto 0);
      s_write       : in  std_logic;
      s_writedata   : in  std_logic_vector (31 downto 0);
      s_waitrequest : out std_logic;

      m_addr        : out integer range 0 to ram_size-1;
      m_read        : out std_logic;
      m_readdata    : in  std_logic_vector (7 downto 0);
      m_write       : out std_logic;
      m_writedata   : out std_logic_vector (7 downto 0);
      m_waitrequest : in  std_logic
    );
  end component;

  component memory is
    generic(
      ram_size      : INTEGER := 32768;
      mem_delay     : time    := 10 ns;
      clock_period  : time    := 1 ns
    );
    port(
      clock       : in  std_logic;
      writedata   : in  std_logic_vector (7 downto 0);
      address     : in  integer range 0 to ram_size-1;
      memwrite    : in  std_logic;
      memread     : in  std_logic;
      readdata    : out std_logic_vector (7 downto 0);
      waitrequest : out std_logic
    );
  end component;

  -- test signals
  signal reset : std_logic := '0';
  signal clk   : std_logic := '0';
  constant clk_period : time := 1 ns;

  signal s_addr        : std_logic_vector (31 downto 0) := (others => '0');
  signal s_read        : std_logic := '0';
  signal s_readdata    : std_logic_vector (31 downto 0);
  signal s_write       : std_logic := '0';
  signal s_writedata   : std_logic_vector (31 downto 0) := (others => '0');
  signal s_waitrequest : std_logic;

  -- Range
  signal m_addr : integer range 0 to 32768-1;
  signal m_read        : std_logic;
  signal m_readdata    : std_logic_vector (7 downto 0);
  signal m_write       : std_logic;
  signal m_writedata   : std_logic_vector (7 downto 0);
  signal m_waitrequest : std_logic;

  ------------------------------------------------------------------------------
  -- Address helper 
  --   tag    = s_addr(14 downto 9)  : 6 bits
  --   index  = s_addr(8 downto 4)   : 5 bits
  --   offset = s_addr(3 downto 2)   : 2 bits
  --   ignore s_addr(1 downto 0)     : word aligned "00"
  ------------------------------------------------------------------------------
  function mk_addr(tag6 : natural; index5 : natural; off2 : natural)
    return std_logic_vector
  is
    variable a : std_logic_vector(31 downto 0) := (others => '0');
  begin
    a(14 downto 9) := std_logic_vector(to_unsigned(tag6, 6));
    a(8 downto 4)  := std_logic_vector(to_unsigned(index5, 5));
    a(3 downto 2)  := std_logic_vector(to_unsigned(off2, 2));
    a(1 downto 0)  := "00";
    return a;
  end function;

begin

  -- DUT
  dut: cache
    port map(
      clock         => clk,
      reset         => reset,
      s_addr        => s_addr,
      s_read        => s_read,
      s_readdata    => s_readdata,
      s_write       => s_write,
      s_writedata   => s_writedata,
      s_waitrequest => s_waitrequest,
      m_addr        => m_addr,
      m_read        => m_read,
      m_readdata    => m_readdata,
      m_write       => m_write,
      m_writedata   => m_writedata,
      m_waitrequest => m_waitrequest
    );

  -- memory.vhd
  MEM: memory
    port map(
      clock       => clk,
      writedata   => m_writedata,
      address     => m_addr,        -- OK: m_addr will only be driven in-range by cache
      memwrite    => m_write,
      memread     => m_read,
      readdata    => m_readdata,
      waitrequest => m_waitrequest
    );

  -- clock generator
  clk_process : process
  begin
    clk <= '0';
    wait for clk_period/2;
    clk <= '1';
    wait for clk_period/2;
  end process;

  -- tests
  test_process : process

   -- Handshake (per assignment): s_waitrequest is normally '1'. A transaction completes when it pulses to '0' for 1 clock cycle, then returns to '1'. So we detect "done" on falling_edge(s_waitrequest).
    procedure wait_done is
    begin
      -- Start from idle-high
      if s_waitrequest /= '1' then
        wait until s_waitrequest = '1';
      end if;

      -- Completion pulse (low for 1 cycle)
      wait until falling_edge(s_waitrequest);
      wait until rising_edge(s_waitrequest); -- back to idle
    end procedure;

    procedure do_write(addr : std_logic_vector(31 downto 0);
                       data : std_logic_vector(31 downto 0)) is
    begin
      s_addr      <= addr;
      s_writedata <= data;
      s_write     <= '1';
      s_read      <= '0';

      wait_done;

      s_write <= '0';
      wait for clk_period;
    end procedure;

    procedure do_read(addr : std_logic_vector(31 downto 0);
                      data_out : out std_logic_vector(31 downto 0)) is
    begin
      s_addr  <= addr;
      s_read  <= '1';
      s_write <= '0';

      -- Wait for completion pulse, then sample readdata
      if s_waitrequest /= '1' then
        wait until s_waitrequest = '1';
      end if;

      wait until falling_edge(s_waitrequest);
      wait for 0 ns; 
      data_out := s_readdata;

      wait until rising_edge(s_waitrequest);

      s_read <= '0';
      wait for clk_period;
    end procedure;

    procedure do_read_check(addr : std_logic_vector(31 downto 0);
                            expected : std_logic_vector(31 downto 0);
                            msg : string) is
      variable got : std_logic_vector(31 downto 0);
    begin
      do_read(addr, got);
      assert got = expected report msg severity error;
    end procedure;

    -- Values captured from initial reads 
    variable d0, d1, d2 : std_logic_vector(31 downto 0);

    -- Addresses that collide to force evictions
    constant IDX : natural := 3;
    constant OFF : natural := 2;
    constant T0  : natural := 1;
    constant T1  : natural := 9;
    constant T2  : natural := 17;

    constant A0 : std_logic_vector(31 downto 0) := mk_addr(T0, IDX, OFF);
    constant A1 : std_logic_vector(31 downto 0) := mk_addr(T1, IDX, OFF);
    constant A2 : std_logic_vector(31 downto 0) := mk_addr(T2, IDX, OFF);

    -- Different index for independent tests
    constant IDX2 : natural := 10;
    constant B0  : std_logic_vector(31 downto 0) := mk_addr(T0, IDX2, 1);

  begin
   
    -- Reset
    s_addr      <= (others => '0');
    s_read      <= '0';
    s_write     <= '0';
    s_writedata <= (others => '0');

    reset <= '1';
    wait for 5*clk_period;
    reset <= '0';
    wait for 5*clk_period;

    -- READ cases
    -- R1) Read miss (cold)
    do_read(A0, d0);

    -- R2) Read hit (same address), should match
    do_read(A0, d1);
    assert d1 = d0 report "R2 failed: read hit didn't match previous read" severity error;

    -- R3) Read miss, valid clean (same index, different tag)
    do_read(A1, d2);

    -- R4) Read hit on A1 should match
    do_read(A1, d1);
    assert d1 = d2 report "R4 failed: A1 read hit didn't match previous read" severity error;

    -- R5) Dirty line via write, then read hit dirty must return written value
    do_write(A1, x"1111AAAA");
    do_read_check(A1, x"1111AAAA", "R5 failed: dirty read hit did not return written data");

    -- R6) Dirty eviction + writeback: access A0 to evict A1, then read A1 back
    do_read(A0, d0);
    do_read_check(A1, x"1111AAAA", "R6 failed: dirty eviction writeback lost A1 data");

    -- WRITE cases
    -- W1) Write miss (cold / allocate), then read back
    do_write(A2, x"2222BBBB");
    do_read_check(A2, x"2222BBBB", "W1 failed: write miss invalid did not store correctly");

    -- W2) Write hit dirty update, then read back
    do_write(A2, x"3333CCCC");
    do_read_check(A2, x"3333CCCC", "W2 failed: write hit dirty did not update correctly");

    -- W3) Write hit clean: allocate clean by reading, then write it
    do_read(B0, d0);
    do_write(B0, x"ABCD1234");
    do_read_check(B0, x"ABCD1234", "W3 failed: write hit clean did not work");

    -- W4) Write miss valid clean (evict clean)
    do_read(A0, d0);            -- ensure A0 allocated clean at IDX
    do_write(A1, x"DEADBEEF");  -- miss at same index, write A1
    do_read_check(A1, x"DEADBEEF", "W4 failed: write miss valid clean did not store correctly");

    -- W5) Write miss valid dirty 
    do_write(A0, x"FEEDC0DE");  -- forces eviction of dirty A1
    do_read_check(A0, x"FEEDC0DE", "W5 failed: A0 value incorrect after dirty-evict write");
    do_read_check(A1, x"DEADBEEF", "W5 failed: dirty eviction did not write back A1 correctly");

    report "ALL CACHE TESTS PASSED" severity note;
    wait;
  end process;

end behavior;