-- ============================================================================
-- alu.vhd — ALU, Branch Evaluator, and Immediate Generator
-- ============================================================================
-- All combinational. Three functions:
--   1. Immediate generation (driven by ID-stage instruction)
--   2. ALU execution (driven by EX-stage operands)
--   3. Branch condition evaluation
-- Supports all 23 RV32I instructions + mul (RV32M).
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alu is
    port(
        -- Immediate generation (ID stage)
        id_ir     : in  std_logic_vector(31 downto 0);
        id_imm    : out std_logic_vector(31 downto 0);
        -- ALU + branch (EX stage)
        ex_ir     : in  std_logic_vector(31 downto 0);
        ex_a      : in  std_logic_vector(31 downto 0);   -- rs1
        ex_b      : in  std_logic_vector(31 downto 0);   -- rs2
        ex_imm    : in  std_logic_vector(31 downto 0);   -- immediate
        ex_pc     : in  unsigned(31 downto 0);
        ex_result : out std_logic_vector(31 downto 0);
        ex_cond   : out std_logic                         -- branch taken condition
    );
end alu;

architecture comb of alu is
    constant OP_LUI    : std_logic_vector(6 downto 0) := "0110111";
    constant OP_AUIPC  : std_logic_vector(6 downto 0) := "0010111";
    constant OP_JAL    : std_logic_vector(6 downto 0) := "1101111";
    constant OP_JALR   : std_logic_vector(6 downto 0) := "1100111";
    constant OP_BRANCH : std_logic_vector(6 downto 0) := "1100011";
    constant OP_LOAD   : std_logic_vector(6 downto 0) := "0000011";
    constant OP_STORE  : std_logic_vector(6 downto 0) := "0100011";
    constant OP_IMM    : std_logic_vector(6 downto 0) := "0010011";
    constant OP_REG    : std_logic_vector(6 downto 0) := "0110011";
begin

    -- ================================================================
    -- IMMEDIATE GENERATION (combinational, ID stage)
    -- ================================================================
    imm_gen: process(id_ir)
        variable ir : std_logic_vector(31 downto 0);
        variable op : std_logic_vector(6 downto 0);
        variable im : std_logic_vector(31 downto 0);
    begin
        ir := id_ir;
        op := ir(6 downto 0);
        im := (others => '0');
        case op is
            when OP_IMM | OP_LOAD | OP_JALR =>                  -- I-type
                im := (others => ir(31));
                im(11 downto 0) := ir(31 downto 20);
            when OP_STORE =>                                    -- S-type
                im := (others => ir(31));
                im(11 downto 0) := ir(31 downto 25) & ir(11 downto 7);
            when OP_BRANCH =>                                   -- B-type
                im := (others => ir(31));
                im(12 downto 0) := ir(31) & ir(7) & ir(30 downto 25) & ir(11 downto 8) & '0';
            when OP_LUI | OP_AUIPC =>                           -- U-type
                im := ir(31 downto 12) & x"000";
            when OP_JAL =>                                      -- J-type
                im := (others => ir(31));
                im(20 downto 0) := ir(31) & ir(19 downto 12) & ir(20) & ir(30 downto 21) & '0';
            when others => im := (others => '0');
        end case;
        id_imm <= im;
    end process;

    -- ================================================================
    -- ALU + BRANCH (combinational, EX stage)
    -- ================================================================
    alu_exec: process(ex_ir, ex_a, ex_b, ex_imm, ex_pc)
        variable ir     : std_logic_vector(31 downto 0);
        variable op     : std_logic_vector(6 downto 0);
        variable f3     : std_logic_vector(2 downto 0);
        variable f7     : std_logic_vector(6 downto 0);
        variable a_s, b_s, imm_s : signed(31 downto 0);
        variable r      : std_logic_vector(31 downto 0);
        variable c      : std_logic;
        variable sh     : integer;
        variable m64    : signed(63 downto 0);
    begin
        ir := ex_ir;
        op := ir(6 downto 0);
        f3 := ir(14 downto 12);
        f7 := ir(31 downto 25);
        a_s := signed(ex_a);
        b_s := signed(ex_b);
        imm_s := signed(ex_imm);
        r := (others => '0');
        c := '0';

        case op is
            when OP_REG =>
                -- Check if it's the 'M' extension (Multiplication)
                if f7 = "0000001" then                              -- MUL
                    m64 := a_s * b_s;
                    r := std_logic_vector(m64(31 downto 0));
                else
                    -- Standard integer math based on the 'funct3' field
                    case f3 is
                        when "000" =>                                   -- ADD/SUB
                            if f7(5) = '1' then
                                r := std_logic_vector(a_s - b_s);
                            else
                                r := std_logic_vector(a_s + b_s);
                            end if;
                        when "001" =>                                   -- SLL
                            sh := to_integer(unsigned(ex_b(4 downto 0)));
                            r := std_logic_vector(shift_left(unsigned(ex_a), sh));
                        when "010" =>                                   -- SLT
                            if a_s < b_s then
                                r := x"00000001";
                            end if;
                        when "011" =>                                   -- SLTU
                            if unsigned(ex_a) < unsigned(ex_b) then
                                r := x"00000001";
                            end if;
                        when "100" =>
                            r := ex_a xor ex_b;                           -- XOR
                        when "101" =>                                   -- SRL/SRA
                            sh:=to_integer(unsigned(ex_b(4 downto 0)));
                            if f7(5)='1' then
                                r := std_logic_vector(shift_right(a_s, sh));
                            else
                                r := std_logic_vector(shift_right(unsigned(ex_a), sh));
                            end if;
                        when "110" =>
                            r := ex_a or ex_b;                            -- OR
                        when "111" =>
                            r := ex_a and ex_b;                           -- AND
                        when others => null;
                end case;
            end if;

            when OP_IMM =>
                case f3 is
                    -- Same logic as OP_REG, but using 'ex_imm' instead of the second register
                    when "000" =>
                        r := std_logic_vector(a_s + imm_s);           -- ADDI
                    when "001" =>                                           -- SLLI
                        sh := to_integer(unsigned(ex_imm(4 downto 0)));
                        r := std_logic_vector(shift_left(unsigned(ex_a), sh));
                    when "010" =>                                           -- SLTI
                        if a_s < imm_s then
                            r := x"00000001";
                        end if;
                    when "011" =>                                           -- SLTIU
                        if unsigned(ex_a) < unsigned(ex_imm) then
                            r := x"00000001"; end if;
                    when "100" =>
                        r := ex_a xor ex_imm;                               -- XORI
                    when "101" =>                                           -- SRLI/SRAI
                        sh := to_integer(unsigned(ex_imm(4 downto 0)));
                        if ir(30)='1' then
                            r := std_logic_vector(shift_right(a_s, sh));
                        else
                            r := std_logic_vector(shift_right(unsigned(ex_a),sh));
                        end if;
                    when "110" =>
                        r := ex_a or ex_imm;                                -- ORI
                    when "111" =>
                        r := ex_a and ex_imm;                               -- ANDI
                    when others => null;
            end case;
            
            -- Address = Base Register + Offset (Immediate)
            -- ie) lw x1, 4(x2) -> result is the address (x2 + 4)
            when OP_LOAD|OP_STORE =>
                r := std_logic_vector(a_s + imm_s);

            when OP_BRANCH =>
                -- 1. Calculate the target address: Current PC + Offset
                r := std_logic_vector(ex_pc + unsigned(ex_imm));            -- branch target
                -- 2. Evaluate the comparison between cases and flag c for whether the branch should be taken
                case f3 is
                    when "000" =>
                        if ex_a = ex_b then
                            c := '1';
                        end if;                         --BEQ
                    when "001" =>
                        if ex_a /= ex_b then
                            c := '1';
                        end if;                         --BNE
                    when "100" =>
                        if a_s < b_s then
                            c := '1';
                        end if;                         --BLT
                    when "101" =>
                        if a_s >= b_s then
                            c := '1';
                        end if;                         --BGE
                    when "110" =>
                        if unsigned(ex_a) < unsigned(ex_b) then
                            c := '1';
                        end if;                         --BLTU
                    when "111" =>
                        if unsigned(ex_a) >= unsigned(ex_b) then
                            c := '1';
                        end if;                         --BGEU
                    when others => null; -- should never happen
                end case;

            when OP_JAL =>      --Jump and link
                r := std_logic_vector(ex_pc + unsigned(ex_imm));
            when OP_JALR =>     --Jump and link register
                r := std_logic_vector(unsigned(ex_a) + unsigned(ex_imm));
                r(0):='0';
            when OP_LUI =>      -- Load upper immediate
                r := ex_imm;
            when OP_AUIPC =>    -- Add upper immediate to pc
                r := std_logic_vector(ex_pc + unsigned(ex_imm));
            when others =>
                null;
        end case;

        ex_result <= r;
        ex_cond <= c;

    end process;
end comb;