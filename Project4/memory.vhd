-- ============================================================================
-- memory.vhd  --  byte-wide synchronous SRAM model (from PD3, lightly tweaked)
-- ============================================================================
-- This is the same memory primitive we built for Project 3, copied in here
-- so Project 4 can simulate without depending on a sibling directory. The
-- only behavioural change from the PD3 original is the new `init_zero`
-- generic:
--
--   init_zero = true  -- fill the array with all zeros at t < 1 ps
--                       (required for the data memory per the spec)
--   init_zero = false -- use the original PD3 placeholder pattern,
--                       ram_block(i) = to_unsigned(i,8). Useful for
--                       sanity-checking that addresses are routed right.
--
-- The processor instantiates four of these per memory (one per byte lane),
-- so a "32 KiB data memory" is really 4 x 8192-byte banks, and a word
-- access fans out to all four lanes in parallel.
--
-- Read latency is one cycle: the address is registered on rising_edge and
-- readdata is a continuous assignment from that registered address. The
-- top-level deals with this by driving address from pc_nxt instead of pc.
-- ============================================================================

--Adapted from Example 12-15 of Quartus Design and Synthesis handbook
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY memory IS
    GENERIC(
        ram_size     : INTEGER := 32768;
        mem_delay    : time    := 0 ns;
        clock_period : time    := 1 ns;
        init_zero    : boolean := true
    );
    PORT (
        clock       : IN  STD_LOGIC;
        writedata   : IN  STD_LOGIC_VECTOR (7 DOWNTO 0);
        address     : IN  INTEGER RANGE 0 TO ram_size-1;
        memwrite    : IN  STD_LOGIC;
        memread     : IN  STD_LOGIC;
        readdata    : OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
        waitrequest : OUT STD_LOGIC
    );
END memory;

ARCHITECTURE rtl OF memory IS
    TYPE MEM IS ARRAY(ram_size-1 downto 0) OF STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL ram_block: MEM;
    SIGNAL read_address_reg: INTEGER RANGE 0 to ram_size-1;
    SIGNAL write_waitreq_reg: STD_LOGIC := '1';
    SIGNAL read_waitreq_reg: STD_LOGIC := '1';

BEGIN
    --This is the main section of the SRAM model
    mem_process: PROCESS (clock)
    BEGIN
        --This is a cheap trick to initialize the SRAM in simulation
        IF(now < 1 ps)THEN
            --Initialization behavior depends on init_zero generic: true = all zeros, false = PD3 default (to_unsigned(i,8))
            IF init_zero THEN
                For i in 0 to ram_size-1 LOOP
                    ram_block(i) <= (others => '0');
                END LOOP;
            ELSE
                For i in 0 to ram_size-1 LOOP
                    -- Fix modelsim mistake
                    ram_block(i) <= std_logic_vector(to_unsigned(i,8));
                END LOOP;
            END IF;
        end if;

        --This is the actual synthesizable SRAM block
        IF (clock'event AND clock = '1') THEN
            IF (memwrite = '1') THEN
                ram_block(address) <= writedata;
            END IF;
            read_address_reg <= address;
        END IF;
    END PROCESS;
    readdata <= ram_block(read_address_reg);

    --The waitrequest signal is used to vary response time in simulation
	--Read and write should never happen at the same time.
    waitreq_w_proc: PROCESS (memwrite)
    BEGIN
        IF (memwrite'event AND memwrite = '1') THEN
            write_waitreq_reg <= '0' after mem_delay, '1' after mem_delay + clock_period;
        END IF;
    END PROCESS;

    -- Read waitrequest generation (same as PD3)
    waitreq_r_proc: PROCESS (memread)
    BEGIN
        IF (memread'event AND memread = '1') THEN
            read_waitreq_reg <= '0' after mem_delay, '1' after mem_delay + clock_period;
        END IF;
    END PROCESS;
    waitrequest <= write_waitreq_reg and read_waitreq_reg;

END rtl;