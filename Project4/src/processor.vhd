-- ============================================================================
-- ECSE 425 Project 4 -- Five-stage pipelined RISC-V processor
-- ============================================================================
-- Implements the RV32I subset listed in the assignment Appendix plus `mul`
-- from the RV32M extension. Pipeline is the textbook IF/ID/EX/MEM/WB layout
-- from H&P 7e Appendix C, Figs. C.19/C.20: branches resolve in EX and take
-- effect in MEM, so a taken branch costs three bubbles. There is no
-- forwarding -- we rely on hazard_control.vhd to stall in ID instead, which
-- is the simpler half of the H&P discussion.
--
-- MEMORY
--   Both the instruction memory and the data memory are built from four
--   instances of the PD3 memory.vhd model arranged as byte lanes. Bank k
--   holds byte k of every aligned word, so a word access fans out to all
--   four banks in parallel and a sub-word access only touches the lanes it
--   needs. The data memory is 32 KiB, the instruction memory is 4 KiB
--   (1024 instructions, the project cap).
--
-- FETCH TIMING
--   memory.vhd has a 1-cycle read latency: the address is registered on
--   rising_edge, and readdata is combinational from the *registered* value.
--   To keep IF aligned with PC we drive imem_addr from pc_nxt rather than
--   pc -- that way the address that *will* become pc on the next edge is
--   the one currently sitting in the memory's address register, and rdata
--   is already valid when the IF/ID latch fires. fetch_valid is the one-bit
--   "wait one cycle while imem catches up" flag we set after reset and
--   after every taken branch.
-- ============================================================================
 
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity processor is
    generic(
        DATA_RAM_SIZE  : integer := 32768;
        INSTR_RAM_SIZE : integer := 4096
    );
    port(
        clock : in  std_logic;
        reset : in  std_logic;
        dump  : in  std_logic;
        done  : out std_logic
    );
end processor;

architecture arch of processor is

    -- ========================================================================
    -- COMPONENT DECLARATIONS
    -- ========================================================================
    component memory is
        generic(
            ram_size     : integer := 32768;
            mem_delay    : time    := 0 ns;
            clock_period : time    := 1 ns;
            init_zero    : boolean := true
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
    end component;

    component regfile is
        port(
            clock     : in  std_logic;
            reset     : in  std_logic;
            rs1_addr  : in  integer range 0 to 31;
            rs2_addr  : in  integer range 0 to 31;
            rs1_data  : out std_logic_vector(31 downto 0);
            rs2_data  : out std_logic_vector(31 downto 0);
            wr_en     : in  std_logic;
            rd_addr   : in  integer range 0 to 31;
            rd_data   : in  std_logic_vector(31 downto 0);
            dump_addr : in  integer range 0 to 31;
            dump_data : out std_logic_vector(31 downto 0)
        );
    end component;

    component alu is
        port(
            id_ir     : in  std_logic_vector(31 downto 0);
            id_imm    : out std_logic_vector(31 downto 0);
            ex_ir     : in  std_logic_vector(31 downto 0);
            ex_a      : in  std_logic_vector(31 downto 0);
            ex_b      : in  std_logic_vector(31 downto 0);
            ex_imm    : in  std_logic_vector(31 downto 0);
            ex_pc     : in  unsigned(31 downto 0);
            ex_result : out std_logic_vector(31 downto 0);
            ex_cond   : out std_logic
        );
    end component;

    component hazard_control is
        port(
            ifid_ir    : in  std_logic_vector(31 downto 0);
            idex_ir    : in  std_logic_vector(31 downto 0);
            exmem_ir   : in  std_logic_vector(31 downto 0);
            exmem_cond : in  std_logic;
            stall      : out std_logic;
            flush      : out std_logic
        );
    end component;

    -- ========================================================================
    -- CONSTANTS
    -- ========================================================================
    constant IMEM_BANK_SIZE : integer := INSTR_RAM_SIZE / 4;
    constant DMEM_BANK_SIZE : integer := DATA_RAM_SIZE / 4;
    constant NOP            : std_logic_vector(31 downto 0) := x"00000013";

    constant OP_JAL   : std_logic_vector(6 downto 0) := "1101111";
    constant OP_JALR  : std_logic_vector(6 downto 0) := "1100111";
    constant OP_LOAD  : std_logic_vector(6 downto 0) := "0000011";
    constant OP_STORE : std_logic_vector(6 downto 0) := "0100011";

    -- ========================================================================
    -- MEMORY BANK SIGNALS
    -- ========================================================================
    type bank_addr_imem is array(0 to 3) of integer range 0 to IMEM_BANK_SIZE-1;
    type bank_addr_dmem is array(0 to 3) of integer range 0 to DMEM_BANK_SIZE-1;
    type bank_byte      is array(0 to 3) of std_logic_vector(7 downto 0);

    -- Instruction memory: signals split into loader vs fetch sets
    -- The actual imem port signals (active at any time)
    signal imem_addr  : bank_addr_imem := (others => 0);
    signal imem_wdata : bank_byte := (others => (others => '0'));
    signal imem_we    : std_logic_vector(3 downto 0) := "0000";
    signal imem_re    : std_logic_vector(3 downto 0) := "0000";
    signal imem_rdata : bank_byte;
    signal imem_wait  : std_logic_vector(3 downto 0);

    -- Loader-side signals (only used during program loading)
    signal load_addr  : bank_addr_imem := (others => 0);
    signal load_wdata : bank_byte := (others => (others => '0'));
    signal load_we    : std_logic_vector(3 downto 0) := "0000";

    -- Data memory
    signal dmem_addr  : bank_addr_dmem := (others => 0);
    signal dmem_wdata : bank_byte := (others => (others => '0'));
    signal dmem_we    : std_logic_vector(3 downto 0) := "0000";
    signal dmem_re    : std_logic_vector(3 downto 0) := "0000";
    signal dmem_rdata : bank_byte;
    signal dmem_wait  : std_logic_vector(3 downto 0);

    -- ========================================================================
    -- PROGRAM COUNTER
    -- ========================================================================
    signal pc       : unsigned(31 downto 0) := (others => '0');
    signal pc_nxt   : unsigned(31 downto 0);
    signal fetch_valid : std_logic := '0';

    -- ========================================================================
    -- PIPELINE REGISTERS
    -- ========================================================================
    signal ifid_pc  : unsigned(31 downto 0) := (others => '0');
    signal ifid_npc : unsigned(31 downto 0) := (others => '0');
    signal ifid_ir  : std_logic_vector(31 downto 0) := NOP;

    signal idex_pc  : unsigned(31 downto 0) := (others => '0');
    signal idex_npc : unsigned(31 downto 0) := (others => '0');
    signal idex_ir  : std_logic_vector(31 downto 0) := NOP;
    signal idex_a   : std_logic_vector(31 downto 0) := (others => '0');
    signal idex_b   : std_logic_vector(31 downto 0) := (others => '0');
    signal idex_imm : std_logic_vector(31 downto 0) := (others => '0');

    signal exmem_ir   : std_logic_vector(31 downto 0) := NOP;
    signal exmem_alu  : std_logic_vector(31 downto 0) := (others => '0');
    signal exmem_b    : std_logic_vector(31 downto 0) := (others => '0');
    signal exmem_cond : std_logic := '0';
    signal exmem_npc  : unsigned(31 downto 0) := (others => '0');

    signal memwb_ir  : std_logic_vector(31 downto 0) := NOP;
    signal memwb_alu : std_logic_vector(31 downto 0) := (others => '0');
    signal memwb_lmd : std_logic_vector(31 downto 0) := (others => '0');

    -- ========================================================================
    -- CONTROL
    -- ========================================================================
    signal stall_sig : std_logic;
    signal flush_sig : std_logic;

    -- ========================================================================
    -- INTER-STAGE WIRES
    -- ========================================================================
    signal id_rs1_data : std_logic_vector(31 downto 0);
    signal id_rs2_data : std_logic_vector(31 downto 0);
    signal id_imm_data : std_logic_vector(31 downto 0);
    signal ex_alu_result  : std_logic_vector(31 downto 0);
    signal ex_branch_cond : std_logic;
    signal mem_load_data : std_logic_vector(31 downto 0);
    signal wb_wr_en   : std_logic;
    signal wb_rd_addr : integer range 0 to 31;
    signal wb_rd_data : std_logic_vector(31 downto 0);

    signal rf_dump_addr : integer range 0 to 31 := 0;
    signal rf_dump_data : std_logic_vector(31 downto 0);

    signal prog_loading : std_logic := '1';
    signal dumping      : std_logic := '0';

    -- Helper functions
    function f_opcode(ir : std_logic_vector(31 downto 0)) return std_logic_vector is
        begin return ir(6 downto 0); end function;
    function f_rd(ir : std_logic_vector(31 downto 0)) return integer is
        begin return to_integer(unsigned(ir(11 downto 7))); end function;
    function f_rs1(ir : std_logic_vector(31 downto 0)) return integer is
        begin return to_integer(unsigned(ir(19 downto 15))); end function;
    function f_rs2(ir : std_logic_vector(31 downto 0)) return integer is
        begin return to_integer(unsigned(ir(24 downto 20))); end function;
    function f_funct3(ir : std_logic_vector(31 downto 0)) return std_logic_vector is
        begin return ir(14 downto 12); end function;
    function writes_rd(ir : std_logic_vector(31 downto 0)) return boolean is
        variable op : std_logic_vector(6 downto 0);
        begin
            op := f_opcode(ir);
            if f_rd(ir) = 0 then return false; end if;
            return op = "0110111" or op = "0010111" or op = OP_JAL
                or op = OP_JALR or op = OP_LOAD or op = "0010011"
                or op = "0110011";
        end function;

begin

    -- ####################################################################
    --                 MEMORY INSTANTIATION
    -- ####################################################################

    gen_imem: for k in 0 to 3 generate
        imem_bank: memory
            generic map(
                ram_size => IMEM_BANK_SIZE,
                mem_delay => 0 ns,
                clock_period => 1 ns,
                init_zero => true)
            port map(
                clock => clock,
                writedata => imem_wdata(k),
                address => imem_addr(k),
                memwrite => imem_we(k),
                memread => imem_re(k),
                readdata => imem_rdata(k),
                waitrequest => imem_wait(k));
    end generate;

    gen_dmem: for k in 0 to 3 generate
        dmem_bank: memory
            generic map(
                ram_size => DMEM_BANK_SIZE,
                mem_delay => 0 ns,
                clock_period => 1 ns,
                init_zero => true)
            port map(
                clock => clock,
                writedata => dmem_wdata(k),
                address => dmem_addr(k),
                memwrite => dmem_we(k),
                memread => dmem_re(k),
                readdata => dmem_rdata(k),
                waitrequest => dmem_wait(k));
    end generate;

    -- ####################################################################
    --        IMEM ADDRESS MUX: loader vs runtime fetch
    -- ####################################################################
    -- During prog_loading: imem signals come from the loader process
    -- During runtime: imem_addr comes combinationally from pc
    -- This is a combinational MUX -- only one process drives imem_addr.
    imem_mux: process(prog_loading, load_addr, load_wdata, load_we, pc_nxt)
        variable widx : integer;
    begin
        if prog_loading = '1' then
            -- Loader is active
            for k in 0 to 3 loop
                imem_addr(k)  <= load_addr(k);
                imem_wdata(k) <= load_wdata(k);
                imem_we(k)    <= load_we(k);
                imem_re(k)    <= '0';
            end loop;
        else
            -- Runtime: drive address from PC_NXT (combinational).
            -- Using pc_nxt instead of pc eliminates the 1-cycle fetch lag:
            -- memory registers pc_nxt at edge N, so at edge N+1 rdata is
            -- valid for the address that pc holds at N+1.  This means every
            -- instruction appears in rdata for exactly one latch cycle,
            -- preventing the duplication bug.
            widx := to_integer(pc_nxt(11 downto 2));
            for k in 0 to 3 loop
                imem_addr(k)  <= widx;
                imem_wdata(k) <= (others => '0');
                imem_we(k)    <= '0';
                imem_re(k)    <= '1';
            end loop;
        end if;
    end process;

    -- ####################################################################
    --                 SUB-COMPONENT INSTANTIATION
    -- ####################################################################

    rf: regfile
        port map(
            clock => clock, reset => reset,
            rs1_addr => f_rs1(ifid_ir),
            rs2_addr => f_rs2(ifid_ir),
            rs1_data => id_rs1_data,
            rs2_data => id_rs2_data,
            wr_en => wb_wr_en,
            rd_addr => wb_rd_addr,
            rd_data => wb_rd_data,
            dump_addr => rf_dump_addr,
            dump_data => rf_dump_data);

    alu_unit: alu
        port map(
            id_ir => ifid_ir,
            id_imm => id_imm_data,
            ex_ir => idex_ir,
            ex_a => idex_a,
            ex_b => idex_b,
            ex_imm => idex_imm,
            ex_pc => idex_pc,
            ex_result => ex_alu_result,
            ex_cond => ex_branch_cond);

    hc: hazard_control
        port map(
            ifid_ir => ifid_ir,
            idex_ir => idex_ir,
            exmem_ir => exmem_ir,
            exmem_cond => exmem_cond,
            stall => stall_sig,
            flush => flush_sig);

    -- ####################################################################
    --                 STAGE 1: Fetch (IF) + PC Update
    -- ####################################################################
    -- pc_next_mux: pure combinational PC selector. Priority order matters:
    --   1. flush  -> redirect to the branch/jump target sitting in EX/MEM
    --   2. stall  -> hold PC at "the address we just fetched" so the next
    --                fetch is a no-op (the IF/ID latch is also frozen)
    --   3. !valid -> hold PC for one cycle after a flush/reset while imem
    --                catches up (memory has 1-cycle read latency)
    --   4. else   -> straight-line: pc + 4
    pc_next_mux: process(pc, stall_sig, flush_sig, exmem_alu, fetch_valid, ifid_npc)
    begin
        if flush_sig = '1' then
            pc_nxt <= unsigned(exmem_alu);
        elsif stall_sig = '1' then
            pc_nxt <= ifid_npc;
        elsif fetch_valid = '0' then
            pc_nxt <= pc;  -- hold PC until memory catches up
        else
            pc_nxt <= pc + 4;
        end if;
    end process;

    -- ####################################################################
    --          STAGE 4: DATA MEMORY DRIVER (load/store + dump)
    -- ####################################################################
    -- dmem_driver owns every signal that goes *into* the data memory banks
    -- (address / wdata / we / re). Keeping all writes to those signals in a
    -- single process is what lets us avoid VHDL multi-driver errors -- if you
    -- ever need to drive dmem_addr from somewhere else, route it through here
    -- instead.
    --
    -- The process has two phases:
    --   1. Run phase: while dump = '0', look at the instruction sitting in
    --      EX/MEM. If it's a store, drive the write byte-lanes; if it's a
    --      load, drive the read lanes. Loads are pre-issued one cycle early
    --      (when the load is still in EX) so the data lands on the rdata bus
    --      in time for the WB stage.
    --   2. Dump phase: walk addresses 0..8191 one per clock, driving the
    --      read lanes. The companion dump_proc reads dmem_rdata on the same
    --      edges and writes memory.txt. The two stay in lock-step via the
    --      `dumping` signal.
    dmem_driver: process
        variable op       : std_logic_vector(6 downto 0);
        variable word_idx : integer;
        variable byte_off : integer;
    begin
        wait until prog_loading = '0';

        while dump = '0' loop
            for k in 0 to 3 loop
                dmem_addr(k) <= 0;
                dmem_wdata(k) <= (others => '0');
                dmem_we(k) <= '0';
                dmem_re(k) <= '0';
            end loop;

            op := f_opcode(exmem_ir);

            if op = OP_STORE then
                word_idx := to_integer(unsigned(exmem_alu(14 downto 2)));
                byte_off := to_integer(unsigned(exmem_alu(1 downto 0)));
                case f_funct3(exmem_ir) is
                    when "000" =>
                        dmem_addr(byte_off) <= word_idx;
                        dmem_wdata(byte_off) <= exmem_b(7 downto 0);
                        dmem_we(byte_off) <= '1';
                    when "001" =>
                        dmem_addr(byte_off) <= word_idx;
                        dmem_wdata(byte_off) <= exmem_b(7 downto 0);
                        dmem_we(byte_off) <= '1';
                        dmem_addr(byte_off + 1) <= word_idx;
                        dmem_wdata(byte_off + 1) <= exmem_b(15 downto 8);
                        dmem_we(byte_off + 1) <= '1';
                    when "010" =>
                        for k in 0 to 3 loop
                            dmem_addr(k) <= word_idx;
                            dmem_wdata(k) <= exmem_b(k*8+7 downto k*8);
                            dmem_we(k) <= '1';
                        end loop;
                    when others => null;
                end case;
            else
                if f_opcode(idex_ir) = OP_LOAD then
                    word_idx := to_integer(unsigned(ex_alu_result(14 downto 2)));
                    for k in 0 to 3 loop
                        dmem_addr(k) <= word_idx;
                        dmem_re(k) <= '1';
                    end loop;
                elsif op = OP_LOAD then
                    word_idx := to_integer(unsigned(exmem_alu(14 downto 2)));
                    for k in 0 to 3 loop
                        dmem_addr(k) <= word_idx;
                        dmem_re(k) <= '1';
                    end loop;
                end if;
            end if;

            wait until rising_edge(clock);
        end loop;

        dumping <= '1';
        for i in 0 to 8191 loop
            for k in 0 to 3 loop
                dmem_addr(k) <= i;
                dmem_re(k) <= '1';
                dmem_we(k) <= '0';
            end loop;
            wait until rising_edge(clock);
        end loop;
        dumping <= '0';

        for k in 0 to 3 loop
            dmem_addr(k) <= 0;
            dmem_re(k) <= '0';
        end loop;
        wait;
    end process;

    -- ####################################################################
    -- MEM STAGE: Assemble load data
    -- ####################################################################
    -- The byte-bank memory hands us four independent 8-bit lanes. This
    -- process glues them back into a 32-bit value, applying the right
    -- sub-word selection and sign/zero extension based on funct3:
    --   000 lb  -- byte,  sign-extend
    --   001 lh  -- half,  sign-extend
    --   010 lw  -- word,  no extension needed
    --   100 lbu -- byte,  zero-extend
    --   101 lhu -- half,  zero-extend
    -- Only `lw` is required by the spec, but the others are nearly free here
    -- and the bookkeeping is identical, so we wire them up too.
    mem_load_assemble: process(exmem_ir, exmem_alu, dmem_rdata)
        variable f3       : std_logic_vector(2 downto 0);
        variable byte_off : integer;
        variable b0, b1   : std_logic_vector(7 downto 0);
        variable rdata    : std_logic_vector(31 downto 0);
    begin
        rdata := (others => '0');
        if f_opcode(exmem_ir) = OP_LOAD then
            f3 := f_funct3(exmem_ir);
            byte_off := to_integer(unsigned(exmem_alu(1 downto 0)));
            case f3 is
                when "000" =>
                    b0 := dmem_rdata(byte_off);
                    rdata := (others => b0(7));
                    rdata(7 downto 0) := b0;
                when "100" =>
                    rdata(7 downto 0) := dmem_rdata(byte_off);
                when "001" =>
                    b0 := dmem_rdata(byte_off);
                    b1 := dmem_rdata(byte_off + 1);
                    rdata := (others => b1(7));
                    rdata(15 downto 0) := b1 & b0;
                when "101" =>
                    b0 := dmem_rdata(byte_off);
                    b1 := dmem_rdata(byte_off + 1);
                    rdata(15 downto 0) := b1 & b0;
                when "010" =>
                    rdata := dmem_rdata(3) & dmem_rdata(2)
                           & dmem_rdata(1) & dmem_rdata(0);
                when others => null;
            end case;
        end if;
        mem_load_data <= rdata;
    end process;

    -- ####################################################################
    --                 STAGE 5: WRITE-BACK (WB)
    -- ####################################################################
    -- Pure mux. Picks which value the WB stage actually shoves into the
    -- register file:
    --   * loads        -> the data we just pulled out of memory (memwb_lmd)
    --   * jal/jalr     -> PC+4 of the jump itself, also stashed in memwb_lmd
    --                     by the MEM/WB latch (this is the link register)
    --   * everything else (ALU ops, lui, auipc) -> ALU result
    -- writes_rd() handles the "x0 cannot be a destination" rule, so wr_en
    -- stays low whenever rd == 0 even if the instruction would normally write.
    wb_select: process(memwb_ir, memwb_alu, memwb_lmd)
        variable op : std_logic_vector(6 downto 0);
    begin
        op := f_opcode(memwb_ir);
        wb_rd_addr <= f_rd(memwb_ir);
        wb_wr_en <= '0';
        wb_rd_data <= memwb_alu;

        if writes_rd(memwb_ir) then
            wb_wr_en <= '1';
            if op = OP_LOAD or op = OP_JAL or op = OP_JALR then
                wb_rd_data <= memwb_lmd;
            else
                wb_rd_data <= memwb_alu;
            end if;
        end if;
    end process;

    -- ####################################################################
    --                 PIPELINE REGISTER UPDATES
    -- ####################################################################
    -- This is the only process that drives any *_pc / *_ir / *_alu / *_b
    -- pipeline latch. Each per-stage block (MEM/WB, EX/MEM, ID/EX, IF/ID)
    -- bubble-or-advance based on stall_sig and flush_sig:
    --
    --   stall_sig (RAW hazard from hazard_control):
    --     * IF/ID is held in place (we re-fetch the same instruction next cycle)
    --     * ID/EX is replaced with a NOP bubble
    --     * EX/MEM and MEM/WB advance normally
    --
    --   flush_sig (taken branch / JAL / JALR sitting in EX/MEM):
    --     * IF/ID, ID/EX, EX/MEM are all squashed to NOP -- the two
    --       instructions fetched on the wrong path and the branch itself
    --       are killed (the branch's effect on the architectural PC is
    --       captured by pc_next_mux on the same edge).
    --     * fetch_valid drops to '0' so we know to insert one extra bubble
    --       while imem catches up to the redirected PC.
    pipeline_regs: process(clock, reset)
    begin
        if reset = '1' then
            pc <= (others => '0');
            fetch_valid <= '0';
            ifid_ir <= NOP; ifid_pc <= (others => '0'); ifid_npc <= (others => '0');
            idex_ir <= NOP; idex_pc <= (others => '0'); idex_npc <= (others => '0');
            idex_a <= (others => '0'); idex_b <= (others => '0'); idex_imm <= (others => '0');
            exmem_ir <= NOP; exmem_alu <= (others => '0'); exmem_b <= (others => '0');
            exmem_cond <= '0'; exmem_npc <= (others => '0');
            memwb_ir <= NOP; memwb_alu <= (others => '0'); memwb_lmd <= (others => '0');

        elsif rising_edge(clock) then

            -- ========== MEM/WB latch ==========
            memwb_ir <= exmem_ir;
            memwb_alu <= exmem_alu;
            memwb_lmd <= mem_load_data;
            if f_opcode(exmem_ir) = OP_JAL or
               f_opcode(exmem_ir) = OP_JALR then
                memwb_lmd <= std_logic_vector(exmem_npc);
            end if;

            -- ========== EX/MEM latch ==========
            if flush_sig = '1' then
                exmem_ir <= NOP;
                exmem_alu <= (others => '0');
                exmem_b <= (others => '0');
                exmem_cond <= '0';
                exmem_npc <= (others => '0');
            else
                exmem_ir <= idex_ir;
                exmem_alu <= ex_alu_result;
                exmem_b <= idex_b;
                exmem_cond <= ex_branch_cond;
                exmem_npc <= idex_npc;
            end if;

            -- ========== ID/EX latch ==========
            if flush_sig = '1' or stall_sig = '1' then
                idex_ir <= NOP;
                idex_pc <= (others => '0');
                idex_npc <= (others => '0');
                idex_a <= (others => '0');
                idex_b <= (others => '0');
                idex_imm <= (others => '0');
            else
                idex_ir <= ifid_ir;
                idex_pc <= ifid_pc;
                idex_npc <= ifid_npc;
                idex_a <= id_rs1_data;
                idex_b <= id_rs2_data;
                idex_imm <= id_imm_data;
            end if;

            -- ========== IF/ID latch ==========
            if flush_sig = '1' then
                ifid_ir <= NOP;
                ifid_pc <= (others => '0');
                ifid_npc <= (others => '0');
                fetch_valid <= '0';  -- PC just redirected; need 1 cycle for memory
            elsif stall_sig = '1' then
                null;  -- hold IF/ID
            elsif fetch_valid = '0' then
                -- First cycle after reset or flush: memory just registered
                -- the address, readdata not valid yet. Insert bubble.
                ifid_ir <= NOP;
                ifid_pc <= (others => '0');
                ifid_npc <= (others => '0');
                fetch_valid <= '1';
            else
                -- Normal fetch: imem_rdata is valid for current pc
                -- (because imem_addr is driven from pc_nxt, which was
                -- registered one cycle ago as the current pc value).
                ifid_ir(7  downto 0) <= imem_rdata(0);
                ifid_ir(15 downto 8) <= imem_rdata(1);
                ifid_ir(23 downto 16) <= imem_rdata(2);
                ifid_ir(31 downto 24) <= imem_rdata(3);
                ifid_pc <= pc;
                ifid_npc <= pc + 4;
            end if;

            -- ========== PC tracking ==========
            pc <= pc_nxt;

        end if;
    end process;

    -- ####################################################################
    --                 PROGRAM LOADING
    -- ####################################################################
    -- Drives load_addr/load_wdata/load_we (NOT imem_addr directly).
    -- The imem_mux process selects between loader and fetch signals so that
    -- only one process is ever the source of imem_addr at a time.
    --
    -- File format (must match what the bundled assembler emits):
    --   one 32-bit word per line, MSB first, characters '0'/'1', addresses
    --   ascending from 0. Lines shorter than 32 chars are skipped silently.
    -- Once EOF is reached we drop prog_loading; the imem_mux flips over to
    -- fetch mode and the pipeline starts running.
    load_program: process
        file     f    : text;
        variable lin  : line;
        variable s    : string(1 to 32);
        variable a    : integer := 0;
        variable w    : std_logic_vector(31 downto 0);
        variable ok   : boolean;
        variable widx : integer;
    begin
        prog_loading <= '1';
        file_open(f, "program.txt", READ_MODE);
        while not endfile(f) and a < INSTR_RAM_SIZE loop
            readline(f, lin);
            if lin'length >= 32 then
                read(lin, s, ok);
                if ok then
                    for k in 0 to 31 loop
                        if s(k+1) = '1' then
                            w(31-k) := '1';
                        else
                            w(31-k) := '0';
                        end if;
                    end loop;
                    widx := a / 4;
                    for k in 0 to 3 loop
                        load_addr(k) <= widx;
                        load_wdata(k) <= w(k*8+7 downto k*8);
                        load_we(k) <= '1';
                    end loop;
                    wait until rising_edge(clock);
                    for k in 0 to 3 loop
                        load_we(k) <= '0';
                    end loop;
                    a := a + 4;
                end if;
            end if;
        end loop;
        file_close(f);
        for k in 0 to 3 loop
            load_we(k)    <= '0';
            load_wdata(k) <= (others => '0');
            load_addr(k)  <= 0;
        end loop;
        prog_loading <= '0';
        wait;
    end process;

    -- ####################################################################
    --                 OUTPUT DUMP
    -- ####################################################################
    -- Two output files, in the format the grader expects:
    --   register_file.txt -- 32 lines, x0 first, MSB-first binary
    --   memory.txt        -- 8192 lines, one 32-bit word per data-mem slot
    -- The register dump runs as soon as `dump` goes high (no clock cycles
    -- needed -- the register file is combinational on dump_addr). The memory
    -- dump rendezvous-es with dmem_driver via the `dumping` signal: once
    -- dmem_driver starts walking addresses, this process samples the four
    -- byte lanes on each rising edge and concatenates them little-endian.
    dump_proc: process
        file     rf_file : text;
        file     dm_file : text;
        variable l       : line;
        variable w       : std_logic_vector(31 downto 0);
    begin
        done <= '0';
        wait until dump = '1';

        file_open(rf_file, "register_file.txt", WRITE_MODE);
        for i in 0 to 31 loop
            rf_dump_addr <= i;
            wait for 0 ns;  -- delta 1: rf_dump_addr updates to i
            wait for 0 ns;  -- delta 2: regfile concurrent assignment reacts
            w := rf_dump_data;
            for b in 31 downto 0 loop
                if w(b) = '1' then
                    write(l, character'('1'));
                else
                    write(l, character'('0'));
                end if;
            end loop;
            writeline(rf_file, l);
        end loop;
        file_close(rf_file);

        file_open(dm_file, "memory.txt", WRITE_MODE);
        wait until dumping = '1';
        for i in 0 to 8191 loop
            wait until rising_edge(clock);
            wait for 0 ns;
            w(7 downto 0) := dmem_rdata(0);
            w(15 downto 8) := dmem_rdata(1);
            w(23 downto 16) := dmem_rdata(2);
            w(31 downto 24) := dmem_rdata(3);
            for b in 31 downto 0 loop
                if w(b) = '1' then
                    write(l, character'('1'));
                else
                    write(l, character'('0'));
                end if;
            end loop;
            writeline(dm_file, l);
        end loop;
        file_close(dm_file);

        done <= '1';
        wait;
    end process;

end arch;