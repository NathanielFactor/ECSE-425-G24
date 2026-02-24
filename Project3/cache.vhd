library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache is
generic(
	ram_size : INTEGER := 32768
);
port(
	clock : in std_logic;
	reset : in std_logic;
	
	-- Avalon interface --
	s_addr : in std_logic_vector (31 downto 0);
	s_read : in std_logic;
	s_readdata : out std_logic_vector (31 downto 0);
	s_write : in std_logic;
	s_writedata : in std_logic_vector (31 downto 0);
	s_waitrequest : out std_logic; 
    
	m_addr : out integer range 0 to ram_size-1;
	m_read : out std_logic;
	m_readdata : in std_logic_vector (7 downto 0);
	m_write : out std_logic;
	m_writedata : out std_logic_vector (7 downto 0);
	m_waitrequest : in std_logic
);
end cache;

architecture arch of cache is

	constant NUM_BLOCKS    : integer := 32;
	constant WORDS_PER_BLK : integer := 4;
	constant BYTES_PER_BLK : integer := 16;
	constant TAG_BITS      : integer := 6;

	type block_store_t is array (0 to NUM_BLOCKS-1) of std_logic_vector(127 downto 0);
	type tag_store_t   is array (0 to NUM_BLOCKS-1) of std_logic_vector(TAG_BITS-1 downto 0);

	signal blocks : block_store_t;
	signal tags   : tag_store_t;
	signal valid  : std_logic_vector(NUM_BLOCKS-1 downto 0) := (others => '0');
	signal dirty  : std_logic_vector(NUM_BLOCKS-1 downto 0) := (others => '0');


	type state_t is (IDLE, COMPARE_TAG, WRITEBACK, WRITEBACK_WAIT,
	                 ALLOCATE, ALLOCATE_WAIT, DELIVER);
	signal state : state_t := IDLE;

	signal byte_counter : integer range 0 to BYTES_PER_BLK-1 := 0;

	signal reg_tag    : std_logic_vector(TAG_BITS-1 downto 0);
	signal reg_index  : integer range 0 to NUM_BLOCKS-1;
	signal reg_offset : integer range 0 to WORDS_PER_BLK-1;
	signal reg_write  : std_logic;
	signal reg_wdata  : std_logic_vector(31 downto 0);

	signal wb_base_addr   : integer range 0 to ram_size-1;
	signal alloc_base_addr: integer range 0 to ram_size-1;

	signal line_buf : std_logic_vector(127 downto 0) := (others => '0');

begin
	cache_fsm: process(clock, reset)
		variable v_line : std_logic_vector(127 downto 0);
		variable word_hi, word_lo : integer;
	begin
		if reset = '1' then
			state <= IDLE;
			s_waitrequest <= '1';
			m_read <= '0';
			m_write <= '0';
			m_addr <= 0;
			m_writedata <= (others => '0');
			s_readdata <= (others => '0');
			byte_counter <= 0;
			valid <= (others => '0');
			dirty <= (others => '0');
			line_buf <= (others => '0');

		elsif rising_edge(clock) then
			case state is

				when IDLE =>
					s_waitrequest <= '1';
					m_read <= '0';
					m_write <= '0';

					if s_read = '1' or s_write = '1' then
						reg_tag    <= s_addr(14 downto 9);
						reg_index  <= to_integer(unsigned(s_addr(8 downto 4)));
						reg_offset <= to_integer(unsigned(s_addr(3 downto 2)));
						reg_write  <= s_write;
						reg_wdata  <= s_writedata;
						state <= COMPARE_TAG;
					end if;

				when COMPARE_TAG =>
					word_lo := reg_offset * 32;
					word_hi := word_lo + 31;
					if valid(reg_index) = '1' and tags(reg_index) = reg_tag then
						if reg_write = '1' then
							v_line := blocks(reg_index);
							v_line(word_hi downto word_lo) := reg_wdata;
							blocks(reg_index) <= v_line;
							dirty(reg_index) <= '1';
						else
							s_readdata <= blocks(reg_index)(word_hi downto word_lo);
						end if;
						s_waitrequest <= '0';
						state <= DELIVER;

					else
						alloc_base_addr <= to_integer(
							unsigned(reg_tag) & 
							to_unsigned(reg_index, 5) & 
							"0000"
						);
						if valid(reg_index) = '1' and dirty(reg_index) = '1' then
							wb_base_addr <= to_integer(
								unsigned(tags(reg_index)) & 
								to_unsigned(reg_index, 5) & 
								"0000"
							);
							line_buf <= blocks(reg_index);
							byte_counter <= 0;
							state <= WRITEBACK;
						else
							byte_counter <= 0;
							state <= ALLOCATE;
						end if;
					end if;

				when WRITEBACK =>
					m_addr <= wb_base_addr + byte_counter;
					m_writedata <= line_buf(
						(byte_counter * 8 + 7) downto (byte_counter * 8)
					);
					m_write <= '1';
					state <= WRITEBACK_WAIT;

				when WRITEBACK_WAIT =>
					if m_waitrequest = '0' then
						m_write <= '0';
						if byte_counter = BYTES_PER_BLK - 1 then
							byte_counter <= 0;
							state <= ALLOCATE;
						else
							byte_counter <= byte_counter + 1;
							state <= WRITEBACK;
						end if;
					end if;

				when ALLOCATE =>
					m_addr <= alloc_base_addr + byte_counter;
					m_read <= '1';
					state <= ALLOCATE_WAIT;

				when ALLOCATE_WAIT =>
					if m_waitrequest = '0' then
						m_read <= '0';
						v_line := line_buf;
						v_line(
							(byte_counter * 8 + 7) downto (byte_counter * 8)
						) := m_readdata;
						line_buf <= v_line;

						if byte_counter = BYTES_PER_BLK - 1 then
							tags(reg_index)  <= reg_tag;
							valid(reg_index) <= '1';
							word_lo := reg_offset * 32;
							word_hi := word_lo + 31;

							if reg_write = '1' then
								v_line(word_hi downto word_lo) := reg_wdata;
								dirty(reg_index) <= '1';
							else
								dirty(reg_index) <= '0';
								s_readdata <= v_line(word_hi downto word_lo);
							end if;

							blocks(reg_index) <= v_line;
							s_waitrequest <= '0';
							state <= DELIVER;
						else
							byte_counter <= byte_counter + 1;
							state <= ALLOCATE;
						end if;
					end if;

				when DELIVER =>
					s_waitrequest <= '1';
					state <= IDLE;

				when others =>
					state <= IDLE;

			end case;
		end if;
	end process;

end arch;