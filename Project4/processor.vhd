-- ============================================================================
-- ECSE 425 Project 4: 5-Stage Pipelined RISC-V Processor
-- ============================================================================
-- RV32I subset (23 instructions) + mul (RV32M).
-- Hazard detection with stalling (no forwarding).
-- Branches resolved in EX, flush on taken branch/JAL/JALR.
--
-- MEMORY: Instantiates PD3 memory.vhd via a 4-bank scheme.
--   - 4 banks for instruction memory (loaded from program.txt)
--   - 4 banks for data memory (initialized to zeros)
-- Bank k stores byte k of every aligned word. Word at byte-address A
-- (A mod 4 == 0) is read from all 4 banks at word-index A/4.
--
-- TIMING: memory.vhd registers address on rising_edge, then
-- readdata = ram_block(registered_address) combinationally.
-- Therefore:
--   Cycle N:     address driven with pc/4
--   Cycle N RE:  memory registers the address; pc updates
--   After N RE:  readdata valid for instruction at old pc
--   Cycle N+1 RE: pipeline latches readdata into IF/ID
-- A 'fetch_pc' register tracks which PC the readdata belongs to.
-- ============================================================================
 
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity processor is
    generic(
        DATA_RAM_SIZE  : integer := 32768;   -- 32 KB data memory
        INSTR_RAM_SIZE : integer := 4096     -- 4 KB instruction memory
    );
    port(
        clock : in  std_logic;
        reset : in  std_logic;
        dump  : in  std_logic;               -- assert to write output files
        done  : out std_logic                -- high when dump complete
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
    constant IMEM_BANK_SIZE : integer := INSTR_RAM_SIZE / 4;  -- 1024
    constant DMEM_BANK_SIZE : integer := DATA_RAM_SIZE / 4;   -- 8192
    constant NOP            : std_logic_vector(31 downto 0) := x"00000013";

    constant OP_JAL   : std_logic_vector(6 downto 0) := "1101111";
    constant OP_JALR  : std_logic_vector(6 downto 0) := "1100111";
    constant OP_LOAD  : std_logic_vector(6 downto 0) := "0000011";
    constant OP_STORE : std_logic_vector(6 downto 0) := "0100011";

    -- ========================================================================
    -- MEMORY BANK TYPES AND SIGNALS
    -- ========================================================================
    type bank_addr_imem is array(0 to 3) of integer range 0 to IMEM_BANK_SIZE-1;
    type bank_addr_dmem is array(0 to 3) of integer range 0 to DMEM_BANK_SIZE-1;
    type bank_byte      is array(0 to 3) of std_logic_vector(7 downto 0);

    -- Instruction memory banks
    signal imem_addr  : bank_addr_imem := (others => 0);
    signal imem_wdata : bank_byte := (others => (others => '0'));
    signal imem_we    : std_logic_vector(3 downto 0) := "0000";
    signal imem_re    : std_logic_vector(3 downto 0) := "0000";
    signal imem_rdata : bank_byte;
    signal imem_wait  : std_logic_vector(3 downto 0);

    -- Data memory banks
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
    signal fetch_pc : unsigned(31 downto 0) := (others => '0');
    -- fetch_pc = PC whose address was sent to imem last cycle.
    -- After rising_edge, imem_rdata contains the instruction at fetch_pc.

    -- ========================================================================
    -- PIPELINE REGISTERS
    -- ========================================================================
    --
    -- Each pipeline register is a set of signals that get updated on
    -- rising_edge(clock) in the pipeline_regs process.
    --
    -- ---- IF/ID ----
    signal ifid_pc  : unsigned(31 downto 0) := (others => '0');  -- PC of instr
    signal ifid_npc : unsigned(31 downto 0) := (others => '0');  -- PC + 4
    signal ifid_ir  : std_logic_vector(31 downto 0) := NOP;     -- instruction

    -- ---- ID/EX ----
    signal idex_pc  : unsigned(31 downto 0) := (others => '0');
    signal idex_npc : unsigned(31 downto 0) := (others => '0');
    signal idex_ir  : std_logic_vector(31 downto 0) := NOP;
    signal idex_a   : std_logic_vector(31 downto 0) := (others => '0'); -- rs1
    signal idex_b   : std_logic_vector(31 downto 0) := (others => '0'); -- rs2
    signal idex_imm : std_logic_vector(31 downto 0) := (others => '0'); -- imm

    -- ---- EX/MEM ----
    signal exmem_ir   : std_logic_vector(31 downto 0) := NOP;
    signal exmem_alu  : std_logic_vector(31 downto 0) := (others => '0'); -- ALU out
    signal exmem_b    : std_logic_vector(31 downto 0) := (others => '0'); -- store data
    signal exmem_cond : std_logic := '0';                                  -- branch cond
    signal exmem_npc  : unsigned(31 downto 0) := (others => '0');         -- link addr

    -- ---- MEM/WB ----
    signal memwb_ir  : std_logic_vector(31 downto 0) := NOP;
    signal memwb_alu : std_logic_vector(31 downto 0) := (others => '0');
    signal memwb_lmd : std_logic_vector(31 downto 0) := (others => '0'); -- load/link

    -- ========================================================================
    -- CONTROL SIGNALS (from hazard_control)
    -- ========================================================================
    signal stall_sig : std_logic;
    signal flush_sig : std_logic;

    -- ========================================================================
    -- INTER-STAGE WIRES (connect sub-components to pipeline registers)
    -- ========================================================================
    -- ID stage outputs
    signal id_rs1_data : std_logic_vector(31 downto 0);  -- from regfile
    signal id_rs2_data : std_logic_vector(31 downto 0);  -- from regfile
    signal id_imm_data : std_logic_vector(31 downto 0);  -- from alu (imm_gen)

    -- EX stage outputs
    signal ex_alu_result  : std_logic_vector(31 downto 0); -- from alu
    signal ex_branch_cond : std_logic;                      -- from alu

    -- MEM stage: assembled load data
    signal mem_load_data : std_logic_vector(31 downto 0);

    -- WB stage outputs
    signal wb_wr_en   : std_logic;
    signal wb_rd_addr : integer range 0 to 31;
    signal wb_rd_data : std_logic_vector(31 downto 0);

    -- Register file dump port (for testbench output)
    signal rf_dump_addr : integer range 0 to 31 := 0;
    signal rf_dump_data : std_logic_vector(31 downto 0);

    -- Program loading control
    signal prog_loading : std_logic := '1';

    -- Helper function to extract opcode field
    function f_opcode(ir : std_logic_vector(31 downto 0)) return std_logic_vector is
        begin
            return ir(6 downto 0);
        end function;
    -- Helper function to extract rd field
    function f_rd(ir : std_logic_vector(31 downto 0)) return integer is
        begin
            return to_integer(unsigned(ir(11 downto 7)));
        end function;
    -- Helper function to extract rs1 field
    function f_rs1(ir : std_logic_vector(31 downto 0)) return integer is
        begin
            return to_integer(unsigned(ir(19 downto 15)));
        end function;
    -- Helper function to extract rs2 field
    function f_rs2(ir : std_logic_vector(31 downto 0)) return integer is
        begin
            return to_integer(unsigned(ir(24 downto 20)));
        end function;
    -- Helper function to extract funct3 field
    function f_funct3(ir : std_logic_vector(31 downto 0)) return std_logic_vector is
        begin
            return ir(14 downto 12);
        end function;
    -- Helper function that returns true if writing to rd
    function writes_rd(ir : std_logic_vector(31 downto 0)) return boolean is
        variable op : std_logic_vector(6 downto 0);
        begin
            op := f_opcode(ir);
            if f_rd(ir) = 0 then
                return false;
            end if;
            return op = "0110111"
                or op = "0010111"
                or op = OP_JAL
                or op = OP_JALR
                or op = OP_LOAD
                or op = "0010011"
                or op = "0110011";
        end function;

begin

    -- ####################################################################
    --                 MEMORY INSTANTIATION (8 banks total)
    -- ####################################################################

    -- 4 instruction memory banks (Bank k stores byte k of each word)
    gen_imem: for k in 0 to 3 generate
        -- Instruction Memory bank instantiation
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
                waitrequest => imem_wait(k)
                );
    end generate;

    -- 4 data memory banks (same banking scheme)
    gen_dmem: for k in 0 to 3 generate
        -- Data Memory bank instantiation
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
                waitrequest => dmem_wait(k)
                );
    end generate;

    -- ####################################################################
    --                 SUB-COMPONENT INSTANTIATION
    -- ####################################################################

    -- Register file (ID stage reads, WB stage writes)
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
            dump_data => rf_dump_data
        );

    -- ALU (imm gen in ID stage, ALU + branch in EX stage)
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
            ex_cond => ex_branch_cond
        );

    -- Hazard control (stall + flush)
    hc: hazard_control
        port map(
            ifid_ir => ifid_ir, 
            idex_ir => idex_ir,
            exmem_ir => exmem_ir, 
            exmem_cond => exmem_cond,
            stall => stall_sig, 
            flush => flush_sig
        );
        
    -- ####################################################################
    --                 STAGE 1: INSTRUCTION FETCH (IF)
    -- ####################################################################

    -- PC next mux: flush target > stall hold > sequential + 4
    pc_next_mux: process(pc, stall_sig, flush_sig, exmem_alu)
    begin
        if flush_sig = '1' then
            pc_nxt <= unsigned(exmem_alu);
        elsif stall_sig = '1' then
            pc_nxt <= pc;
        else
            pc_nxt <= pc + 4;
        end if;
    end process;

    -- Drive instruction memory address from current PC
    -- (memory registers this on rising_edge, readdata available after)
    imem_addr_driver: process(prog_loading, pc)
        variable widx : integer;
    begin
        if prog_loading = '0' then
            widx := to_integer(pc(11 downto 2));
            for k in 0 to 3 loop
                imem_addr(k) <= widx;
                imem_re(k) <= '1';
            end loop;
        end if;
    end process;

    -- ####################################################################
    --                 STAGE 4: MEMORY ACCESS (MEM)
    -- ####################################################################

    -- Data memory bank address/data driver for loads and stores
    dmem_driver: process(exmem_ir, exmem_alu, exmem_b, idex_ir, ex_alu_result, prog_loading)
        variable op       : std_logic_vector(6 downto 0);
        variable word_idx : integer;
        variable byte_off : integer;
    begin
        -- Default: all banks idle
        for k in 0 to 3 loop
            dmem_addr(k) <= 0;
            dmem_wdata(k) <= (others => '0');
            dmem_we(k) <= '0';
            dmem_re(k) <= '0';
        end loop;

        if prog_loading = '0' then
            op := f_opcode(exmem_ir);

            -- ---- STORES: write bytes to appropriate banks ----
            if op = OP_STORE then
                word_idx := to_integer(unsigned(exmem_alu(14 downto 2)));
                byte_off := to_integer(unsigned(exmem_alu(1 downto 0)));
                case f_funct3(exmem_ir) is
                    when "000" =>  -- SB: 1 byte
                        dmem_addr(byte_off) <= word_idx;
                        dmem_wdata(byte_off) <= exmem_b(7 downto 0);
                        dmem_we(byte_off) <= '1';
                    when "001" =>  -- SH: 2 bytes
                        dmem_addr(byte_off) <= word_idx;
                        dmem_wdata(byte_off) <= exmem_b(7 downto 0);
                        dmem_we(byte_off) <= '1';
                        dmem_addr(byte_off + 1) <= word_idx;
                        dmem_wdata(byte_off + 1) <= exmem_b(15 downto 8);
                        dmem_we(byte_off + 1) <= '1';
                    when "010" =>  -- SW: 4 bytes
                        for k in 0 to 3 loop
                            dmem_addr(k) <= word_idx;
                            dmem_wdata(k) <= exmem_b(k*8+7 downto k*8);
                            dmem_we(k) <= '1';
                        end loop;
                    when others => null;
                end case;

            -- ---- LOADS: pre-fetch from EX stage (1 cycle early) ----
            else
                if f_opcode(idex_ir) = OP_LOAD then
                    -- Address from EX ALU result (available combinationally)
                    word_idx := to_integer(unsigned(ex_alu_result(14 downto 2)));
                    for k in 0 to 3 loop
                        dmem_addr(k) <= word_idx;
                        dmem_re(k) <= '1';
                    end loop;
                elsif op = OP_LOAD then
                    -- Fallback: address from EX/MEM register
                    word_idx := to_integer(unsigned(exmem_alu(14 downto 2)));
                    for k in 0 to 3 loop
                        dmem_addr(k) <= word_idx;
                        dmem_re(k) <= '1';
                    end loop;
                end if;
            end if;
        end if;
    end process;

    -- Assemble 32-bit load data from memory bank outputs
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
                when "000" => -- LB: sign-extend byte
                    b0 := dmem_rdata(byte_off);
                    rdata := (others => b0(7));
                    rdata(7 downto 0) := b0;
                when "100" => -- LBU: zero-extend byte
                    rdata(7 downto 0) := dmem_rdata(byte_off);
                when "001" => -- LH: sign-extend half
                    b0 := dmem_rdata(byte_off);
                    b1 := dmem_rdata(byte_off + 1);
                    rdata := (others => b1(7));
                    rdata(15 downto 0) := b1 & b0;
                when "101" => -- LHU: zero-extend half
                    b0 := dmem_rdata(byte_off);
                    b1 := dmem_rdata(byte_off + 1);
                    rdata(15 downto 0) := b1 & b0;
                when "010" => -- LW: full word
                    rdata := dmem_rdata(3) & dmem_rdata(2) & dmem_rdata(1) & dmem_rdata(0);
                when others => null;
            end case;
        end if;
        mem_load_data <= rdata;
    end process;

    -- ####################################################################
    --                 STAGE 5: WRITE-BACK (WB)
    -- ####################################################################

    -- Select write-back data: ALU result, load data, or link address
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
                wb_rd_data <= memwb_lmd;  -- load data or link address
            else
                wb_rd_data <= memwb_alu;  -- ALU result
            end if;
        end if;
    end process;

end arch;