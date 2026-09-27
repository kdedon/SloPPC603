--------------------------------------------------------------------------------
-- BASE
-- Definitions
--------------------------------------------------------------------------------
-- DO 3/2009
--------------------------------------------------------------------------------
-- Base
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

PACKAGE base_pack IS
  --------------------------------------
  SUBTYPE uv     IS unsigned;
  SUBTYPE sv     IS signed;
  
  SUBTYPE uv1_0  IS unsigned(1  DOWNTO 0);
  SUBTYPE uv0_1  IS unsigned(0  TO     1);
  SUBTYPE uv3_0  IS unsigned(3  DOWNTO 0);
  SUBTYPE uv0_3  IS unsigned(0  TO     3);
  SUBTYPE uv7_0  IS unsigned(7  DOWNTO 0);
  SUBTYPE uv0_7  IS unsigned(0  TO     7);
  
  SUBTYPE uv2    IS unsigned(1   DOWNTO 0);
  SUBTYPE uv3    IS unsigned(2   DOWNTO 0);
  SUBTYPE uv4    IS unsigned(3   DOWNTO 0);
  SUBTYPE uv5    IS unsigned(4   DOWNTO 0);
  SUBTYPE uv6    IS unsigned(5   DOWNTO 0);
  SUBTYPE uv7    IS unsigned(6   DOWNTO 0);
  SUBTYPE uv8    IS unsigned(7   DOWNTO 0);
  SUBTYPE uv9    IS unsigned(8   DOWNTO 0);
  SUBTYPE uv10   IS unsigned(9   DOWNTO 0);
  SUBTYPE uv11   IS unsigned(10  DOWNTO 0);
  SUBTYPE uv12   IS unsigned(11  DOWNTO 0);
  SUBTYPE uv13   IS unsigned(12  DOWNTO 0);
  SUBTYPE uv14   IS unsigned(13  DOWNTO 0);
  SUBTYPE uv15   IS unsigned(14  DOWNTO 0);
  SUBTYPE uv16   IS unsigned(15  DOWNTO 0);
  SUBTYPE uv17   IS unsigned(16  DOWNTO 0);
  SUBTYPE uv18   IS unsigned(17  DOWNTO 0);
  SUBTYPE uv19   IS unsigned(18  DOWNTO 0);
  SUBTYPE uv20   IS unsigned(19  DOWNTO 0);
  SUBTYPE uv21   IS unsigned(20  DOWNTO 0);
  SUBTYPE uv22   IS unsigned(21  DOWNTO 0);
  SUBTYPE uv23   IS unsigned(22  DOWNTO 0);
  SUBTYPE uv24   IS unsigned(23  DOWNTO 0);
  SUBTYPE uv25   IS unsigned(24  DOWNTO 0);
  SUBTYPE uv26   IS unsigned(25  DOWNTO 0);
  SUBTYPE uv27   IS unsigned(26  DOWNTO 0);
  SUBTYPE uv28   IS unsigned(27  DOWNTO 0);
  SUBTYPE uv29   IS unsigned(28  DOWNTO 0);
  SUBTYPE uv30   IS unsigned(29  DOWNTO 0);
  SUBTYPE uv31   IS unsigned(30  DOWNTO 0);
  SUBTYPE uv32   IS unsigned(31  DOWNTO 0);
  SUBTYPE uv36   IS unsigned(35  DOWNTO 0);
  SUBTYPE uv64   IS unsigned(63  DOWNTO 0);
  SUBTYPE uv128  IS unsigned(127 DOWNTO 0);
  
  SUBTYPE sv2    IS signed(1   DOWNTO 0);
  SUBTYPE sv4    IS signed(3   DOWNTO 0);
  SUBTYPE sv8    IS signed(7   DOWNTO 0);
  SUBTYPE sv16   IS signed(15  DOWNTO 0);
  SUBTYPE sv32   IS signed(31  DOWNTO 0);
  SUBTYPE sv64   IS signed(63  DOWNTO 0);
  SUBTYPE sv128  IS signed(127 DOWNTO 0);
  
  TYPE arr_uv0_3 IS ARRAY(natural RANGE <>) OF uv0_3;
  TYPE arr_uv0_7 IS ARRAY(natural RANGE <>) OF uv0_7;
  
  TYPE arr_uv4   IS ARRAY(natural RANGE <>) OF uv4;
  TYPE arr_uv8   IS ARRAY(natural RANGE <>) OF uv8;
  TYPE arr_uv16  IS ARRAY(natural RANGE <>) OF uv16;
  TYPE arr_uv32  IS ARRAY(natural RANGE <>) OF uv32;
  TYPE arr_uv64  IS ARRAY(natural RANGE <>) OF uv64;

  SUBTYPE uint1  IS natural RANGE 0 TO 1;
  SUBTYPE uint2  IS natural RANGE 0 TO 3;
  SUBTYPE uint3  IS natural RANGE 0 TO 7;
  SUBTYPE uint4  IS natural RANGE 0 TO 15;
  SUBTYPE uint5  IS natural RANGE 0 TO 31;
  SUBTYPE uint6  IS natural RANGE 0 TO 63;
  SUBTYPE uint7  IS natural RANGE 0 TO 127;
  SUBTYPE uint8  IS natural RANGE 0 TO 255;
  SUBTYPE uint9  IS natural RANGE 0 TO 511;
  SUBTYPE uint10 IS natural RANGE 0 TO 1023;
  SUBTYPE uint11 IS natural RANGE 0 TO 2047;
  SUBTYPE uint12 IS natural RANGE 0 TO 4095;
  SUBTYPE uint13 IS natural RANGE 0 TO 8191;
  SUBTYPE uint14 IS natural RANGE 0 TO 16383;
  SUBTYPE uint15 IS natural RANGE 0 TO 32767;
  SUBTYPE uint16 IS natural RANGE 0 TO 65535;
  SUBTYPE uint17 IS natural RANGE 0 TO 131071;
  SUBTYPE uint18 IS natural RANGE 0 TO 262143;
  SUBTYPE uint19 IS natural RANGE 0 TO 524287;
  SUBTYPE uint20 IS natural RANGE 0 TO 1048575;
  SUBTYPE uint24 IS natural RANGE 0 TO 16777215;

  SUBTYPE int2  IS integer RANGE     -2 TO 1;
  SUBTYPE int3  IS integer RANGE     -4 TO 3;
  SUBTYPE int4  IS integer RANGE     -8 TO 7;
  SUBTYPE int5  IS integer RANGE    -16 TO 15;
  SUBTYPE int6  IS integer RANGE    -32 TO 31;
  SUBTYPE int7  IS integer RANGE    -64 TO 63;
  SUBTYPE int8  IS integer RANGE   -128 TO 127;
  SUBTYPE int9  IS integer RANGE   -256 TO 255;
  SUBTYPE int10 IS integer RANGE   -512 TO 511;
  SUBTYPE int11 IS integer RANGE  -1024 TO 1023;
  SUBTYPE int12 IS integer RANGE  -2048 TO 2047;
  SUBTYPE int13 IS integer RANGE  -4096 TO 4095;
  SUBTYPE int14 IS integer RANGE  -8192 TO 8191;
  SUBTYPE int15 IS integer RANGE -16384 TO 16383;
  SUBTYPE int16 IS integer RANGE -32768 TO 32767;
  SUBTYPE int17 IS integer RANGE -65536 TO 65535;
  SUBTYPE int18 IS integer RANGE -131072 TO 131071;
  SUBTYPE int19 IS integer RANGE -262144 TO 262143;
  SUBTYPE int20 IS integer RANGE -524288 TO 524287;
  
  
  -------------------------------------------------------------
  FUNCTION v_or  (CONSTANT v : unsigned) RETURN std_logic;
  FUNCTION v_and (CONSTANT v : unsigned) RETURN std_logic;
  FUNCTION vv    (CONSTANT s : std_logic;
                  CONSTANT N : natural) RETURN unsigned;
  
  --------------------------------------
  FUNCTION to_std_logic (a : boolean) RETURN std_logic;
  --------------------------------------
  FUNCTION mux (
    s : std_logic;
    a : std_logic_vector;
    b : std_logic_vector) RETURN std_logic_vector;
  --------------------------------------
  FUNCTION mux (
    s : std_logic;
    a : unsigned;
    b : unsigned) RETURN unsigned;
  --------------------------------------
  FUNCTION mux (
    s : boolean;
    a : unsigned;
    b : unsigned) RETURN unsigned;
  --------------------------------------
  FUNCTION mux (
    s : std_logic;
    a : std_logic;
    b : std_logic) RETURN std_logic;
  --------------------------------------
  FUNCTION mux (
    s : boolean;
    a : std_logic;
    b : std_logic) RETURN std_logic;
  --------------------------------------
  FUNCTION mux (
    s : boolean;
    a : boolean;
    b : boolean) RETURN boolean;
  --------------------------------------
  FUNCTION mux (
    s : boolean;
    a : integer;
    b : integer) RETURN integer;
  --------------------------------------
  FUNCTION mux (
    s : std_logic;
    a : character;
    b : character) RETURN character;
  --------------------------------------
  FUNCTION mux (
    s : boolean;
    a : character;
    b : character) RETURN character;
  --------------------------------------
  FUNCTION sext (
    e : unsigned;
    l : natural) RETURN unsigned;
  --------------------------------------
  FUNCTION sext (
    e : std_logic;
    l : natural) RETURN unsigned;
  --------------------------------------
  FUNCTION uext (
    e : unsigned;
    l : natural) RETURN unsigned;
  --------------------------------------
  FUNCTION uext (
    e : std_logic;
    l : natural) RETURN unsigned;
  --------------------------------------
END PACKAGE base_pack;
PACKAGE BODY base_pack IS
  FUNCTION vv (CONSTANT s : std_logic;
               CONSTANT N : natural) RETURN unsigned IS
    VARIABLE v : unsigned(N-1 DOWNTO 0);
  BEGIN
    v:=(OTHERS => s);
    RETURN v;
  END FUNCTION vv;
  
  -------------------------------------------------------------
  -- Vector OR (reduce)
  FUNCTION v_or (CONSTANT v : unsigned) RETURN std_logic IS
    VARIABLE r : std_logic := '0';
    VARIABLE Z : unsigned(v'range) := (OTHERS =>'0');
  BEGIN
--pragma synthesis_off
    IF 1=1 THEN
      FOR I IN v'range LOOP
        r:=r OR v(I);
      END LOOP;
      RETURN r;
    ELSE
--pragma synthesis_on
      IF v/=Z THEN
        RETURN '1';
      ELSE
        RETURN '0';
      END IF;
--pragma synthesis_off
    END IF;
--pragma synthesis_on    
  END FUNCTION v_or;
  
  -------------------------------------------------------------
  -- Vector AND (reduce)
  FUNCTION v_and (CONSTANT v : unsigned) RETURN std_logic IS
    VARIABLE r : std_logic := '1';
    VARIABLE U : unsigned(v'range) := (OTHERS =>'1');
  BEGIN
--pragma synthesis_off
    IF 1=1 THEN
      FOR I IN v'range LOOP
        r:=r AND v(I);
      END LOOP;
      RETURN r;
    ELSE
--pragma synthesis_on
      IF v/=U THEN
        RETURN '0';
      ELSE
        RETURN '1';
      END IF;
--pragma synthesis_off
    END IF;
--pragma synthesis_on
  END FUNCTION v_and;
  
  --------------------------------------
  FUNCTION to_std_logic (a : boolean) RETURN std_logic IS
  BEGIN
    IF a THEN RETURN '1';
         ELSE RETURN '0';
    END IF;
  END FUNCTION to_std_logic;
  
  --------------------------------------
  -- Sélection/Multiplexage  s=1:a, s=0:b
  FUNCTION mux (
    s : std_logic;
    a : unsigned;
    b : unsigned) RETURN unsigned IS
    VARIABLE x : unsigned(a'range) :=(OTHERS => 'X');
  BEGIN
    IF s='1' THEN
      RETURN a;
    ELSIF s='0' THEN
      RETURN b;
    ELSE
      RETURN x;
    END IF;
  END FUNCTION mux;
  
  --------------------------------------
  -- Sélection/Multiplexage  s=1:a, s=0:b
  FUNCTION mux (
    s : std_logic;
    a : std_logic_vector;
    b : std_logic_vector) RETURN std_logic_vector IS
    VARIABLE x : std_logic_vector(a'range) :=(OTHERS => 'X');
  BEGIN
    IF s='1' THEN
      RETURN a;
    ELSIF s='0' THEN
      RETURN b;
    ELSE
      RETURN x;
    END IF;
  END FUNCTION mux;
  
  --------------------------------------
  -- Sélection/Multiplexage  s=true:a, s=false:b
  FUNCTION mux (
    s : boolean;
    a : unsigned;
    b : unsigned) RETURN unsigned IS
  BEGIN
    IF s THEN
      RETURN a;
    ELSE
      RETURN b;
    END IF;
  END FUNCTION mux;
  
  --------------------------------------
  -- Sélection/Multiplexage  s=1:a, s=0:b
  FUNCTION mux (
    s : std_logic;
    a : std_logic;
    b : std_logic)
    RETURN std_logic IS
  BEGIN
    RETURN (S AND A) OR (NOT S AND B);
  END FUNCTION mux;
  
  --------------------------------------
  -- Sélection/Multiplexage  s=true:a, s=false:b
  FUNCTION mux (
    s : boolean;
    a : std_logic;
    b : std_logic)
    RETURN std_logic IS
  BEGIN
    IF s THEN
      RETURN a;
    ELSE
      RETURN b;
    END IF;
  END FUNCTION mux;
  
  --------------------------------------
  -- Sélection/Multiplexage  s=true:a, s=false:b
  FUNCTION mux (
    s : boolean;
    a : boolean;
    b : boolean)
    RETURN boolean IS
  BEGIN
    IF s THEN
      RETURN a;
    ELSE
      RETURN b;
    END IF;
  END FUNCTION mux;
  
  --------------------------------------
  -- Sélection/Multiplexage  s=1:a, s=0:b
  FUNCTION mux (
    s : boolean;
    a : integer;
    b : integer)
    RETURN integer IS
  BEGIN
    IF s THEN
      RETURN a;
    ELSE
      RETURN b;
    END IF;
  END FUNCTION mux;

  --------------------------------------
  -- Sélection/Multiplexage  s=true:a, s=false:b
  FUNCTION mux (
    s : std_logic;
    a : character;
    b : character)
    RETURN character IS
  BEGIN
    IF s='1' THEN
      RETURN a;
    ELSE
      RETURN b;
    END IF;
  END FUNCTION mux;
  
  --------------------------------------
  -- Sélection/Multiplexage  s=true:a, s=false:b
  FUNCTION mux (
    s : boolean;
    a : character;
    b : character)
    RETURN character IS
  BEGIN
    IF s THEN
      RETURN a;
    ELSE
      RETURN b;
    END IF;
  END FUNCTION mux;
  
  --------------------------------------
  -- Étend un vecteur avec extension de signe
  FUNCTION sext (
    e : unsigned;
    l : natural) RETURN unsigned IS
    VARIABLE t : unsigned(l-1 DOWNTO 0);
  BEGIN
    -- <AFAIRE> Vérifier numeric_std.resize ...
    t:=(OTHERS => e(e'left));
    t(e'length-1 DOWNTO 0):=e;
    RETURN t;
  END FUNCTION sext;
  
  --------------------------------------
  -- Étend un vecteur avec extension de signe
  FUNCTION sext (
    e : std_logic;
    l : natural) RETURN unsigned IS
    VARIABLE t : unsigned(l-1 DOWNTO 0);
  BEGIN
    -- <AFAIRE> Vérifier numeric_std.resize ...
    t:=(OTHERS => e);
    RETURN t;
  END FUNCTION sext;
  
   --------------------------------------
  -- Étend un vecteur sans extension de signe
  FUNCTION uext (
    e : unsigned;
    l : natural) RETURN unsigned IS
    VARIABLE t : unsigned(l-1 DOWNTO 0);
  BEGIN
    -- <AFAIRE> Vérifier numeric_std.resize ...
    t:=(OTHERS => '0');
    t(e'length-1 DOWNTO 0):=e;
    RETURN t;
  END FUNCTION uext;
  
  --------------------------------------
  -- Étend un vecteur sans extension de signe 
  FUNCTION uext (
    e : std_logic;
    l : natural) RETURN unsigned IS
    VARIABLE t : unsigned(l-1 DOWNTO 0);
  BEGIN
  -- <AFAIRE> Vérifier numeric_std.resize ...
    t:=(OTHERS => '0');
    t(0):=e;
    RETURN t;
  END FUNCTION uext;
  
  --------------------------------------
  -- Wait Until Rising Edge
END PACKAGE BODY;
