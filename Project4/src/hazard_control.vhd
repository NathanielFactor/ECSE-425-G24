-- Combinational hazard detector. Outputs two bits:
--   stall: RAW between IF/ID and a producer still in ID/EX or EX/MEM.
--   flush: taken branch / jal / jalr in EX/MEM.
-- We don't check MEM/WB because the regfile writes on the falling edge,
-- so a producer in WB is already visible to a reader in ID the same cycle.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hazard_control is
    port(
        ifid_ir    : in  std_logic_vector(31 downto 0);
        idex_ir    : in  std_logic_vector(31 downto 0);
        exmem_ir   : in  std_logic_vector(31 downto 0);
        exmem_cond : in  std_logic;
        stall      : out std_logic;
        flush      : out std_logic
    );
end hazard_control;

architecture comb of hazard_control is
    constant OP_LUI    : std_logic_vector(6 downto 0) := "0110111";
    constant OP_AUIPC  : std_logic_vector(6 downto 0) := "0010111";
    constant OP_JAL    : std_logic_vector(6 downto 0) := "1101111";
    constant OP_JALR   : std_logic_vector(6 downto 0) := "1100111";
    constant OP_BRANCH : std_logic_vector(6 downto 0) := "1100011";
    constant OP_LOAD   : std_logic_vector(6 downto 0) := "0000011";
    constant OP_STORE  : std_logic_vector(6 downto 0) := "0100011";
    constant OP_IMM    : std_logic_vector(6 downto 0) := "0010011";
    constant OP_REG    : std_logic_vector(6 downto 0) := "0110011";

    -- field accessors
    function opcode(ir : std_logic_vector(31 downto 0)) return std_logic_vector is
        begin return ir(6 downto 0); end;
    function rd_i(ir : std_logic_vector(31 downto 0)) return integer is
        begin return to_integer(unsigned(ir(11 downto 7))); end;
    function rs1_i(ir : std_logic_vector(31 downto 0)) return integer is
        begin return to_integer(unsigned(ir(19 downto 15))); end;
    function rs2_i(ir : std_logic_vector(31 downto 0)) return integer is
        begin return to_integer(unsigned(ir(24 downto 20))); end;

    -- does this instruction write rd?
    function wr_rd(ir : std_logic_vector(31 downto 0)) return boolean is
        variable op : std_logic_vector(6 downto 0);
    begin
        op := opcode(ir);
        if rd_i(ir) = 0 then
            return false;
        end if;
        return op = OP_LUI or op = OP_AUIPC or op = OP_JAL or op = OP_JALR
            or op = OP_LOAD or op = OP_IMM or op = OP_REG;
    end;

    function use_rs1(ir : std_logic_vector(31 downto 0)) return boolean is
        variable op : std_logic_vector(6 downto 0);
    begin
        op := opcode(ir);
        return op = OP_JALR or op = OP_BRANCH or op = OP_LOAD
            or op = OP_STORE or op = OP_IMM or op = OP_REG;
    end;

    function use_rs2(ir : std_logic_vector(31 downto 0)) return boolean is
        variable op : std_logic_vector(6 downto 0);
    begin
        op := opcode(ir);
        return op = OP_BRANCH or op = OP_STORE or op = OP_REG;
    end;

begin
    -- stall if a producer in ID/EX or EX/MEM writes a reg the IF/ID instr reads
    stall_detect: process(ifid_ir, idex_ir, exmem_ir)
        variable r1, r2, exd, md    :   integer;
        variable need               :   boolean;
    begin
        r1  := rs1_i(ifid_ir);
        r2  := rs2_i(ifid_ir);
        exd := rd_i(idex_ir);
        md  := rd_i(exmem_ir);
        need := false;

        if wr_rd(idex_ir) then
            if use_rs1(ifid_ir) and r1 /= 0 and r1 = exd then need := true; end if;
            if use_rs2(ifid_ir) and r2 /= 0 and r2 = exd then need := true; end if;
        end if;
        if wr_rd(exmem_ir) then
            if use_rs1(ifid_ir) and r1 /= 0 and r1 = md then need := true; end if;
            if use_rs2(ifid_ir) and r2 /= 0 and r2 = md then need := true; end if;
        end if;

        -- store-then-load: hold the load one cycle so dmem_driver can
        -- pre-issue its read without colliding with the store
        if opcode(idex_ir) = OP_STORE and opcode(ifid_ir) = OP_LOAD then
            need := true;
        end if;

        if need then stall <= '1'; else stall <= '0'; end if;
    end process;

    -- flush on taken branch or any jump in EX/MEM
    flush <= '1' when
        (opcode(exmem_ir) = OP_BRANCH and exmem_cond = '1')
        or opcode(exmem_ir) = OP_JAL
        or opcode(exmem_ir) = OP_JALR
        else '0';
end comb;