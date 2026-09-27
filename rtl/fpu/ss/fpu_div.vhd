--------------------------------------------------------------------------------
-- TEM : TACUS
-- Unité flottante : Divisions et Racine Carrée
--------------------------------------------------------------------------------
-- DO 6/2011
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################


-- <AVOIR> : Bugs diviseurs SRT
--                                     SIMPLE        DOUBLE

-- FDIV_MODE :
--  0 : Non Restoring      DIV/SQRT       25            54
--  1 : SRT Radix 2        DIV/SQRT       27            56
--  2 : SRT Radix 4        DIV/SQRT       14            29

-- Division/Racine SRT base 2 et base 4, carry-save,
-- d'après Peter Kornerup 'Digit Selection for SRT Division and Square Root'

--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE work.base_pack.ALL;
USE work.fpu_pack.ALL;


--------------------------------------------------------------------------------
ENTITY  fpu_div IS
  GENERIC (
    TECH        : natural);
  PORT (
    div_sd      : IN  std_logic;            -- 0=Simple 1=Double
    div_dr      : IN  std_logic;            -- 0=DIV 1=SQRT
    div_flush   : IN  std_logic;
    div_start   : IN  std_logic;
    div_end     : OUT std_logic;
    div_busy    : OUT std_logic;
    div_fs1_man : IN  unsigned(53 DOWNTO 0);
    div_fs2_man : IN  unsigned(52 DOWNTO 0);
    div_fs_man  : OUT unsigned(54 DOWNTO 0);
    div_inx     : OUT std_logic;
    
    reset_n     : IN std_logic;            -- Reset asynchrone
    clk         : IN std_logic             -- Horloge
    );
END ENTITY fpu_div;

--------------------------------------------------------------------------------

ARCHITECTURE rtl OF fpu_div IS
  SIGNAL dnr_r : unsigned(57 DOWNTO 0);
  SIGNAL dnr_q,dnr_m : unsigned(54 DOWNTO 0);
  SIGNAL dnr_quo : unsigned(54 DOWNTO 0);
  SIGNAL dnr_inx : std_logic;
  SIGNAL dnr_i : natural RANGE 0 TO 63;
  SIGNAL dnr_sd : std_logic;
  SIGNAL div_bsy : std_logic;
  CONSTANT ZERO : uv64 := (OTHERS => '0');
BEGIN
  
  ------------------------------------------------------------------------------
  -- Division et Racine "sans restoration"
  Gen_DIV_NR:IF true GENERATE

    div_busy<=div_bsy;
    
    Algo_DIV_NR:PROCESS (clk)
      VARIABLE r_v : unsigned(57 DOWNTO 0);
    BEGIN
      IF rising_edge(clk) THEN
        IF div_start='1' THEN
          dnr_i<=0;
          div_bsy<='1';
          div_end<='0';
          dnr_inx<='1';
          dnr_sd<=div_sd;
        ELSE
          dnr_i<=(dnr_i+1) MOD 64;
          IF (dnr_i=25 AND dnr_sd='0') OR (dnr_i=54 AND dnr_sd='1') THEN
            div_end<=div_bsy;
            div_bsy<='0';
          ELSE
            div_end<='0';
          END IF;
        END IF;

        IF div_bsy/='1' THEN
          dnr_m<=(OTHERS => '0');
          IF div_dr='0' THEN
            -- Division
            dnr_q<='0' & div_fs2_man & '0';
          ELSE
            -- Racine
            dnr_q<=(OTHERS => '0');
            dnr_m(54)<='1';
          END IF;
          dnr_r<="00" & div_fs1_man & "00";    -- Reste
        ELSE
          dnr_m<='0' & dnr_m(54 DOWNTO 1);
          IF dnr_r(57)='0' THEN
            r_v:=(dnr_r(56 DOWNTO 0) & '0') -
                  ('0' & dnr_q & "00") - ("00" & dnr_m & '0');
            dnr_q<=dnr_q+dnr_m;
          ELSE
            r_v:=(dnr_r(56 DOWNTO 0) & '0') +
                  ('0' & dnr_q & "00") - ("00" & dnr_m & '0');
            dnr_q<=dnr_q-dnr_m;
          END IF;
          dnr_r<=r_v;
          IF (dnr_sd='1' AND r_v=ZERO(57 DOWNTO 0)) OR
            (dnr_sd='0' AND r_v(57 DOWNTO 28)=ZERO(28 DOWNTO 0)) THEN
            dnr_inx<='0';
          END IF;
          IF dnr_sd='1' THEN
            dnr_quo<=dnr_quo(53 DOWNTO 0) & NOT r_v(57);
          ELSE
            dnr_quo<=dnr_quo(53 DOWNTO 29) & NOT r_v(57) &
                      ZERO(28 DOWNTO 0);
          END IF;
        END IF;
        
        -- <AVOIR> synchronisation valeur finale Sticky division
        IF div_flush='1' THEN
          div_bsy<='0';
        END IF;
        IF reset_n='0' THEN
          div_bsy<='0';
        END IF;
      END IF;
    END PROCESS Algo_DIV_NR;
    
    div_fs_man<=dnr_quo;
    div_inx<=dnr_inx;
    
  END GENERATE Gen_DIV_NR;
  
  ------------------------------------------------------------------------------
  -- Division et Racine SRT base 2
END ARCHITECTURE rtl;
