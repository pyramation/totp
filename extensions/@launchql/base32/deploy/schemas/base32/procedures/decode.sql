-- Deploy schemas/base32/procedures/decode to pg

-- requires: schemas/base32/schema
-- requires: schemas/base32/procedures/encode 

BEGIN;

-- 'I' => '8'
CREATE FUNCTION base32.base32_alphabet_to_decimal(
  input text
) returns text as $$
DECLARE
  alphabet text = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  alpha int;
BEGIN
  alpha = position(input in alphabet) - 1;
  IF (alpha < 0) THEN 
    RETURN '=';
  END IF;
  RETURN alpha::text;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

-- INQXI===  =>  ['8', '13', '16', '23', '8', '=', '=', '=']
CREATE FUNCTION base32.base32_to_decimal(
  input text 
) returns text[] as $$
DECLARE
  i int;
  output text[];
BEGIN
  input = upper(input);
  FOR i IN 1 .. character_length(input) LOOP
    output = array_append(output, base32.base32_alphabet_to_decimal(substring(input from i for 1)));
  END LOOP;
  RETURN output;
END;
$$
LANGUAGE 'plpgsql' STABLE;

-- ['8', '13', '16', '23', '8', '=', '=', '=']
-- [ '01000', '01101', '10000', '10111', '01000', 'xxxxx', 'xxxxx', 'xxxxx' ]
CREATE FUNCTION base32.decimal_to_chunks(
  input text[]
) returns text[] as $$
DECLARE
  i int;
  part text;
  output text[];
BEGIN
  FOR i IN 1 .. cardinality(input) LOOP
    part = input[i];
    IF (part = '=') THEN 
      output = array_append(output, 'xxxxx');
    ELSE
      output = array_append(output, right(base32.to_binary(part::int), 5));
    END IF;
  END LOOP;
  RETURN output;
END;
$$
LANGUAGE 'plpgsql' STABLE;

CREATE FUNCTION base32.base32_alphabet_to_decimal_int(
  input text
) returns int as $$
DECLARE
  alphabet text = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  alpha int;
BEGIN
  alpha = position(input in alphabet) - 1;
  RETURN alpha;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

-- this emulates the >>> (unsigned right shift)
-- https://stackoverflow.com/questions/41134337/unsigned-right-shift-zero-fill-right-shift-in-php-java-javascript-equiv
CREATE FUNCTION base32.zero_fill(
  a int, b int
) returns bigint as $$
DECLARE
  bin text;
  m int;
BEGIN

  IF (b >= 32 OR b < -32) THEN 
    m = b/32;
    b = b-(m*32);
  END IF;

  IF (b < 0) THEN
    b = 32 + b;
  END IF;

  IF (b = 0) THEN
      return ((a>>1)&2147483647)*2::bigint+((a>>b)&1);
  END IF;

  IF (a < 0) THEN
    a = (a >> 1); 
    a = a & 2147483647; -- 0x7fffffff
    a = a | 1073741824; -- 0x40000000
    a = (a >> (b - 1)); 
  ELSE
    a = (a >> b); 
  END IF; 

  RETURN a;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE FUNCTION base32.valid(
  input text
) returns boolean as $$
BEGIN 
  IF (upper(input) ~* '^[A-Z2-7]+=*$') THEN 
    RETURN true;
  END IF;
  RETURN false;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE FUNCTION base32.decode(
  input text
) returns text as $$
DECLARE
  i int;
  arr int[];
  output text[];
  len int;
  num int;

  value int = 0;
  index int = 0;
  bits int = 0;
BEGIN
  len = character_length(input);
  IF (len = 0) THEN 
    RETURN '';
  END IF;

  IF (NOT base32.valid(input)) THEN 
    RAISE EXCEPTION 'INVALID_BASE32';
  END IF;

  input = replace(input, '=', '');
  input = upper(input);
  len = character_length(input);
  num = len * 5 / 8;

  select array(select * from generate_series(1,num))
  INTO arr;
  
  FOR i IN 1 .. len LOOP
    value = (value << 5) | base32.base32_alphabet_to_decimal_int(substring(input from i for 1));
    bits = bits + 5;
    IF (bits >= 8) THEN
      arr[index] = base32.zero_fill(value, (bits - 8)) & 255; -- arr[index] = (value >>> (bits - 8)) & 255;
      index = index + 1;
      bits = bits - 8;
    END IF;
  END LOOP;

  len = cardinality(arr);
  FOR i IN 0 .. len-2 LOOP
     output = array_append(output, chr(arr[i]));
  END LOOP;

  RETURN array_to_string(output, '');
END;
$$
LANGUAGE 'plpgsql' STABLE;

COMMIT;