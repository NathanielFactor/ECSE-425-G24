-- ============================================================================
-- hazard_control.vhd  --  RAW stall + control-flow flush detector
-- ============================================================================
-- All-combinational helper that produces the two control bits the rest of
-- the pipeline reacts to:
--
--   stall : the instruction in IF/ID needs a register that the instruction
--           in ID/EX or EX/MEM is still computing. Holding stall high tells
--           processor.vhd to (a) freeze IF/ID, (b) re-fetch the same PC,
--           and (c) inject a NOP into ID/EX -- the classic bubble.
--
--   flush : a control-flow instruction sitting in EX/MEM has just resolved
--           "taken" (or it's an unconditional jump). The two instructions
--           speculatively fetched after it are on the wrong path and have
--           to be killed. processor.vhd squashes IF/ID, ID/EX and EX/MEM
--           when this is high, and pc_next_mux redirects PC to the target.
--
-- We do *not* implement forwarding, so a producer in ID/EX needs to drag
-- its result all the way to MEM/WB before the consumer in IF/ID can read
-- it -- that's normally two stall cycles. The trick that lets us cap it
-- at exactly that without checking MEM/WB explicitly is in regfile.vhd:
-- WB writes on the falling edge of the same cycle ID reads on the rising
-- edge, so the moment a producer reaches WB its value is visible to ID.
-- Hence we only need to stall while the producer is still in EX/MEM or
-- earlier -- exactly the two checks in the process below.
-- ============================================================================

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

    -- Helper functions to decode instructions
    function opcode(ir : std_logic_vector(31 downto 0)) return std_logic_vector is
        begin
            return ir(6 downto 0);
        end;
    -- Helper functions to decode instruction fields
    function rd_i(ir : std_logic_vector(31 downto 0)) return integer is
        begin
            return to_integer(unsigned(ir(11 downto 7)));
        end;
    -- Helper functions to decode instruction fields
    function rs1_i(ir : std_logic_vector(31 downto 0)) return integer is
        begin
            return to_integer(unsigned(ir(19 downto 15)));
        end;
    -- Helper functions to decode instruction fields
    function rs2_i(ir : std_logic_vector(31 downto 0)) return integer is
        begin
            return to_integer(unsigned(ir(24 downto 20)));
        end;
    -- Helper functions to identify instruction types and whether they write to rd
    function wr_rd(ir : std_logic_vector(31 downto 0)) return boolean is
        variable op : std_logic_vector(6 downto 0);
    begin
        op := opcode(ir);
        if rd_i(ir)=0 then
            return false;
        end if;
        return op = OP_LUI
            or op = OP_AUIPC
            or op = OP_JAL
            or op = OP_JALR
            or op = OP_LOAD
            or op = OP_IMM
            or op = OP_REG;
    end;
    -- Helper functions to identify instruction types and whether they use rs1
    function use_rs1(ir : std_logic_vector(31 downto 0)) return boolean is
        variable op : std_logic_vector(6 downto 0);
    begin
        op := opcode(ir);
        return op = OP_JALR
            or op = OP_BRANCH
            or op = OP_LOAD
            or op = OP_STORE
            or op = OP_IMM
            or op = OP_REG;
    end;
    -- Helper functions to identify instruction types and whether they use rs2
    function use_rs2(ir : std_logic_vector(31 downto 0)) return boolean is
        variable op : std_logic_vector(6 downto 0);
    begin
        op := opcode(ir);
        return op = OP_BRANCH
            or op = OP_STORE
            or op = OP_REG;
    end;

begin
    -- Stall detection.
    -- For each pipeline register that holds a "still computing" producer
    -- (ID/EX and EX/MEM), check whether its rd matches either of the
    -- registers the IF/ID instruction wants to read. The use_rs1 / use_rs2
    -- guards keep us from stalling on instructions that don't actually
    -- consume a particular source (e.g. LUI uses neither rs1 nor rs2).
    -- The `r1 /= 0` / `r2 /= 0` guards stop a fake hazard against x0,
    -- which is wired to zero in the regfile and never needs to be waited on.
    stall_detect: process(ifid_ir, idex_ir, exmem_ir)
        variable r1, r2, exd, md    :   integer;
        variable need               :   boolean;
    begin
        r1  := rs1_i(ifid_ir);
        r2  := rs2_i(ifid_ir);
        exd := rd_i(idex_ir);
        md  := rd_i(exmem_ir);
        need := false;
        -- Check for hazards with ID/EX instruction
        if wr_rd(idex_ir) then
            if use_rs1(ifid_ir) and r1 /= 0 and r1 = exd then need := true; end if;
            if use_rs2(ifid_ir) and r2 /= 0 and r2 = exd then need := true; end if;
        end if;
        -- Check for hazards with EX/MEM instruction
        if wr_rd(exmem_ir) then
            if use_rs1(ifid_ir) and r1 /= 0 and r1 = md then need := true; end if;
            if use_rs2(ifid_ir) and r2 /= 0 and r2 = md then need := true; end if;
        end if;
        -- Store-then-load stall: when a store is about to enter EX/MEM
        -- (currently in ID/EX) and a load is in IF/ID, stall one cycle.
        -- This ensures that when the load reaches ID/EX, the store has
        -- already left EX/MEM, so the dmem_driver can pre-register the
        -- load address without conflicting with the store.
        if opcode(idex_ir) = OP_STORE and opcode(ifid_ir) = OP_LOAD then
            need := true;
        end if;
        -- Set stall output based on whether a hazard was detected
        if need then
            stall <= '1';
        else
            stall <= '0';
        end if;
    end process;

    -- Flush detection.
    -- Keyed on the EX/MEM stage rather than EX, because that's the
    -- moment processor.vhd is *about to* push the wrong-path instruction
    -- into the next latch -- catching it here squashes IF/ID, ID/EX and
    -- EX/MEM in one shot, which is the three bubbles the assignment
    -- specifies for a taken branch.
    flush <= '1' when
        -- Flush if EX/MEM instruction is a taken branch or a jump
        (opcode(exmem_ir) = OP_BRANCH and exmem_cond = '1') or opcode(exmem_ir) = OP_JAL or opcode(exmem_ir) = OP_JALR
        else '0';
end comb;