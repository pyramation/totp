-- Deploy schemas/base32/procedures/encode to pg

-- requires: schemas/base32/schema

-- https://tools.ietf.org/html/rfc4648
-- https://www.youtube.com/watch?v=Va8FLD-iuTg

BEGIN;

 -- '01000011' => 67
CREATE FUNCTION base32.binary_to_int(
  input text
) returns int as $$
DECLARE
  i int;
  buf text;
BEGIN
    buf = 'SELECT B''' || input || '''::int';
    EXECUTE buf INTO i;
    RETURN i;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

 -- ASCII decimal values Cat => [67,97,116]
CREATE FUNCTION base32.to_ascii(
  input text
) returns int[] as $$
DECLARE
  i int;
  output int[];
BEGIN
  FOR i IN 1 .. character_length(input) LOOP
    output = array_append(output, ascii(substring(input from i for 1)));
  END LOOP;
  RETURN output;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

-- 67 => '01000011'
CREATE FUNCTION base32.to_binary(
  input int
) returns text as $$
DECLARE
  i int = 1;
  j int = 0;
  output char[] = ARRAY['x', 'x', 'x', 'x', 'x', 'x', 'x', 'x'];
BEGIN
  WHILE i < 256 LOOP 
    output[8-j] = (CASE WHEN (input & i) > 0 THEN '1' ELSE '0' END)::char;
    i = i << 1;
    j = j + 1;
  END LOOP;
  RETURN array_to_string(output, '');
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

-- [67,97,116] => [01000011, 01100001, 01110100]
CREATE FUNCTION base32.to_binary(
  input int[]
) returns text[] as $$
DECLARE
  i int;
  output text[];
BEGIN
  FOR i IN 1 .. cardinality(input) LOOP
    output = array_append(output, base32.to_binary(input[i]));  
  END LOOP;
  RETURN output;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

  -- convert an input byte stream into group of 5 bytes
  -- if there are less than 5, adding padding
 
  -- [01000011, 01100001, 01110100, xxxxxxxx, xxxxxxxx]

CREATE FUNCTION base32.to_groups(
  input text[]
) returns text[] as $$
DECLARE
  i int;
  output text[];
  len int = cardinality(input);
BEGIN
  IF ( len % 5 = 0 ) THEN 
    RETURN input;
  END IF;
  FOR i IN 1 .. 5 - (len % 5) LOOP
    input = array_append(input, 'xxxxxxxx');
  END LOOP;
  RETURN input;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

  -- break these into 5 bit chunks (5 * 8 = 40 bits, when we 40/5 = 8 new elements of 5 bits each)

  -- [01000, 01101, 10000, 10111, 0100x, xxxxx, xxxxx, xxxxx]

CREATE FUNCTION base32.string_nchars(text, integer)
RETURNS text[] AS $$
SELECT ARRAY(SELECT substring($1 from n for $2)
  FROM generate_series(1, length($1), $2) n);
$$ LANGUAGE sql IMMUTABLE;

CREATE FUNCTION base32.to_chunks(
  input text[]
) returns text[] as $$
DECLARE
  i int;
  output text[];
  str text;
  len int = cardinality(input);
BEGIN
  RETURN base32.string_nchars(array_to_string(input, ''), 5);
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

  -- if a chunk has a mix of real bits (0|1) and empty (x), replace x with 0

  -- [01000, 01101, 10000, 10111, 0100x, xxxxx, xxxxx, xxxxx]
  -- [01000, 01101, 10000, 10111, 01000, xxxxx, xxxxx, xxxxx]

CREATE FUNCTION base32.fill_chunks(
  input text[]
) returns text[] as $$
DECLARE
  i int;
  output text[];
  chunk text;
  len int = cardinality(input);
BEGIN
  FOR i IN 1 .. len LOOP 
    chunk = input[i];
    IF (chunk ~* '[0-1]+') THEN 
      chunk = replace(chunk, 'x', '0');
    END IF;
    output = array_append(output, chunk);
  END LOOP;
  RETURN output;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

  -- convert to decimal value

  -- [01000, 01101, 10000, 10111, 01000, xxxxx, xxxxx, xxxxx]
  -- [0b01000, 0b01101, 0b10000, 0b10111, 0b01000, xxxxx, xxxxx, xxxxx]
  -- [ 8, 13, 16, 23, 8, '=', '=', '=' ]

CREATE FUNCTION base32.to_decimal(
  input text[]
) returns text[] as $$
DECLARE
  i int;
  output text[];
  chunk text;
  buf text;
  len int = cardinality(input);
BEGIN
  FOR i IN 1 .. len LOOP 
    chunk = input[i];
    IF (chunk ~* '[x]+') THEN 
      chunk = '=';
    ELSE
      chunk = base32.binary_to_int(input[i])::text;
    END IF;
    output = array_append(output, chunk);
  END LOOP;
  RETURN output;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;


-- Table 3: The Base 32 Alphabet

--   0 A             9 J            18 S            27 3
--   1 B            10 K            19 T            28 4
--   2 C            11 L            20 U            29 5
--   3 D            12 M            21 V            30 6
--   4 E            13 N            22 W            31 7
--   5 F            14 O            23 X
--   6 G            15 P            24 Y         (pad) =
--   7 H            16 Q            25 Z
--   8 I            17 R            26 2

CREATE FUNCTION base32.base32_alphabet(
  input int
) returns char as $$
DECLARE
  alphabet text[] = ARRAY[
    'A', 'B', 'C', 'D', 'E', 'F',
    'G', 'H', 'I', 'J', 'K', 'L',
    'M', 'N', 'O', 'P', 'Q', 'R',
    'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z', '2', '3', '4', '5',
    '6', '7'
  ]::text;
BEGIN
  RETURN alphabet[input+1];
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

-- [ 8, 13, 16, 23, 8, '=', '=', '=' ]
-- [ I, N, Q, X, I, '=', '=', '=' ]

CREATE FUNCTION base32.to_base32(
  input text[]
) returns text as $$
DECLARE
  i int;
  output text[];
  chunk text;
  buf text;
  len int = cardinality(input);
BEGIN
  FOR i IN 1 .. len LOOP 
    chunk = input[i];
    IF (chunk = '=') THEN 
      chunk = '=';
    ELSE
      chunk = base32.base32_alphabet(chunk::int);
    END IF;
    output = array_append(output, chunk);
  END LOOP;
  RETURN array_to_string(output, '');
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE FUNCTION base32.encode(
  input text
) returns text as $$
BEGIN
  IF (character_length(input) = 0) THEN 
    RETURN '';
  END IF;

  RETURN
    base32.to_base32(
      base32.to_decimal(
        base32.fill_chunks(
          base32.to_chunks(
            base32.to_groups(
              base32.to_binary(
                base32.to_ascii(
                  input
                )
              )
            )
          )
        )
      )
    );
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

COMMIT;
