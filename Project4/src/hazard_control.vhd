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
        fetch_ir        : in  std_logic_vector(31 downto 0);
        decode_ir       : in  std_logic_vector(31 downto 0);
        execute_ir      : in  std_logic_vector(31 downto 0);
        branch_taken    : in  std_logic;
        stall           : out std_logic;
        flush           : out std_logic
    );
end hazard_control;

architecture hazards of hazard_control is
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
    function get_opcode(ir : std_logic_vector(31 downto 0)) return std_logic_vector is
        begin return ir(6 downto 0); end;
    function get_rd(ir : std_logic_vector(31 downto 0)) return integer is
        begin return to_integer(unsigned(ir(11 downto 7))); end;
    function get_rs1(ir : std_logic_vector(31 downto 0)) return integer is
        begin return to_integer(unsigned(ir(19 downto 15))); end;
    function get_rs2(ir : std_logic_vector(31 downto 0)) return integer is
        begin return to_integer(unsigned(ir(24 downto 20))); end;

    -- does this instruction write rd?
    function writes_reg(ir : std_logic_vector(31 downto 0)) return boolean is
        variable op : std_logic_vector(6 downto 0);
    begin
        op := get_opcode(ir);
        if get_rd(ir) = 0 then
            return false;
        end if;
        return op = OP_LUI or op = OP_AUIPC or op = OP_JAL or op = OP_JALR or op = OP_LOAD or op = OP_IMM or op = OP_REG;
    end;

    function reads_rs1(ir : std_logic_vector(31 downto 0)) return boolean is
        variable op : std_logic_vector(6 downto 0);
    begin
        op := get_opcode(ir);
        return op = OP_JALR or op = OP_BRANCH or op = OP_LOAD or op = OP_STORE or op = OP_IMM or op = OP_REG;
    end;

    function reads_rs2(ir : std_logic_vector(31 downto 0)) return boolean is
        variable op : std_logic_vector(6 downto 0);
    begin
        op := get_opcode(ir);
        return op = OP_BRANCH or op = OP_STORE or op = OP_REG;
    end;

begin
    -- stall if a producer in ID/EX or EX/MEM writes a reg the IF/ID instr reads
    stall_detect: process(fetch_ir, decode_ir, execute_ir)
        variable r1, r2, ex_dest, mem_dest  :   integer;
        variable do_stall   :   boolean;
    begin
        r1          :=  get_rs1(fetch_ir);
        r2          :=  get_rs2(fetch_ir);
        ex_dest     :=  get_rd(decode_ir);
        mem_dest    :=  get_rd(execute_ir);
        do_stall    :=  false;

        if writes_reg(decode_ir) then
            if reads_rs1(fetch_ir) and r1 /= 0 and r1 = ex_dest then
                do_stall := true;
            end if;
            if reads_rs2(fetch_ir) and r2 /= 0 and r2 = ex_dest then
                do_stall := true;
            end if;
        end if;

        if writes_reg(execute_ir) then
            if reads_rs1(fetch_ir) and r1 /= 0 and r1 = mem_dest then
                do_stall := true;
            end if;
            if reads_rs2(fetch_ir) and r2 /= 0 and r2 = mem_dest then
                do_stall := true;
            end if;
        end if;

        -- store-then-load: hold the load one cycle so dmem_driver can
        -- pre-issue its read without colliding with the store
        if get_opcode(decode_ir) = OP_STORE and get_opcode(fetch_ir) = OP_LOAD then
            do_stall := true;
        end if;

        if do_stall then stall <= '1'; else stall <= '0'; end if;
    end process;

    -- flush on taken branch or any jump in EX/MEM
    flush <= '1' when
        (get_opcode(execute_ir) = OP_BRANCH and branch_taken = '1')
        or get_opcode(execute_ir) = OP_JAL
        or get_opcode(execute_ir) = OP_JALR
        else '0';
end hazards;