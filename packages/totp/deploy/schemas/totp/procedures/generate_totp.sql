-- Deploy schemas/totp/procedures/generate_totp to pg
-- requires: schemas/totp/schema
-- requires: schemas/totp/procedures/urlencode

BEGIN;

-- https://www.youtube.com/watch?v=VOYxF12K1vE
-- https://tools.ietf.org/html/rfc6238
-- http://blog.tinisles.com/2011/10/google-authenticator-one-time-password-algorithm-in-javascript/

CREATE FUNCTION totp.t_unix (
  timestamptz
)
  RETURNS bigint
  AS $$
SELECT floor(EXTRACT(epoch FROM $1))::bigint;
$$
LANGUAGE sql IMMUTABLE;

CREATE FUNCTION totp.n (
  t timestamptz,
  step bigint default 30
)
  RETURNS bigint
  AS $$
SELECT floor(totp.t_unix(t) / step)::bigint;
$$
LANGUAGE sql IMMUTABLE;

CREATE FUNCTION totp.n_hex (
  n bigint
)
  RETURNS text
  AS $$
DECLARE
 missing_padding int;
 hext text;
BEGIN
  hext = to_hex(n);
  RETURN lpad(hext, 16, '0');
END;
$$
LANGUAGE plpgsql
IMMUTABLE;

CREATE FUNCTION totp.generate_totp_time_key (
  totp_interval int DEFAULT 30,
  from_time timestamptz DEFAULT NOW()
)
  RETURNS text
  AS $$
  SELECT totp.n_hex( totp.n ( from_time, totp_interval ) );
$$
LANGUAGE 'sql'
IMMUTABLE;

 -- '0000000003114810' -> '\x0000000003114810'::bytea
CREATE FUNCTION totp.n_hex_to_8_bytes(
  input text
) returns bytea as $$
DECLARE
  b bytea;
  buf text;
BEGIN
    buf = 'SELECT ''\x' || input || '''::bytea';
    EXECUTE buf INTO b;
    RETURN b;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE FUNCTION totp.hmac_as_20_bytes(
  n_hex bytea,
  v_secret bytea,
  v_algo text default 'sha1'
) returns bytea as $$
DECLARE
  v_hmac bytea;
BEGIN
  RETURN hmac(n_hex, v_secret, v_algo);
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE FUNCTION totp.get_offset (
  hmac_as_20_bytes bytea
) returns int as $$
DECLARE
  v_hmac bytea;
  v_str text;
  buf text;
  ch text;
  i int;
BEGIN

    -- get last char (or last 4 bits as int)
    ch = right(hmac_as_20_bytes::text, 1); 
    buf = 'SELECT x''' || ch || '''::int';
    EXECUTE buf INTO i;
    RETURN i;

    -- TEST BELOW FOR MORE CASES for now I'm doing the simpler version

    -- 160 bits in 20 bytes... so get last 4 bits:
    -- you may wonder why these numbers?
    -- e.g., 0x9A => A => 0b1010 => 10 (int)
    -- it's not x x x x 1 0 1 0 ...
    -- it's actually 
        --  A                   9
    -- [0] [1] [0] [1] [ ] [ ] [ ] [ ] 
    v_str = concat(
      '0000',
      get_bit( hmac_as_20_bytes, 155),
      get_bit( hmac_as_20_bytes, 154),
      get_bit( hmac_as_20_bytes, 153),
      get_bit( hmac_as_20_bytes, 152)
    );

    buf = 'SELECT B''' || v_str || '''::int';
    EXECUTE buf INTO i;

    RETURN i;

END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;



CREATE FUNCTION totp.get_first_4_bytes_from_offset (
  hmac_as_20_bytes bytea,
  v_offset int
) returns int[] as $$
DECLARE
  a int;
  b int;
  c int;
  d int;
BEGIN

  a = get_byte(hmac_as_20_bytes, v_offset);
  b = get_byte(hmac_as_20_bytes, v_offset + 1);
  c = get_byte(hmac_as_20_bytes, v_offset + 2);
  d = get_byte(hmac_as_20_bytes, v_offset + 3);

  RETURN ARRAY[a,b,c,d]::int[];

END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE FUNCTION totp.apply_binary_to_bytes (
  four_bytes int[]
) returns int[] as $$
BEGIN
  four_bytes[1] = four_bytes[1] & 127; -- x'7f';
  four_bytes[2] = four_bytes[2] & 255; -- x'ff';
  four_bytes[3] = four_bytes[3] & 255; -- x'ff';
  four_bytes[4] = four_bytes[4] & 255; -- x'ff';

  RETURN four_bytes;

END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE FUNCTION totp.compact_bytes_to_int (
  four_bytes int[]
) returns int as $$
DECLARE 
  buf text;
  i int;
BEGIN
  buf = 
   to_hex(four_bytes[1]) ||
   to_hex(four_bytes[2]) ||
   to_hex(four_bytes[3]) ||
   to_hex(four_bytes[4]);

  buf = 'SELECT x''' || buf || '''::int';
  EXECUTE buf INTO i;
  RETURN i;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE FUNCTION totp.calculate_token (
  calcd_int int,
  totp_length int default 6
) returns text as $$
DECLARE 
  buf text;
  i int;
  s text;
  missing_padding int;
BEGIN
   i = calcd_int % (10^totp_length)::int;
   s = i::text;

   -- if token size < totp_len, padd with zeros
   missing_padding = character_length(s) % totp_length;
   if missing_padding != 0 THEN
     s = lpad('', (totp_length - missing_padding), '0') || s;
   END IF;

   RETURN s;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;


CREATE FUNCTION totp.generate (
  totp_secret text,
  totp_interval int default 30,
  totp_length int default 6,
  time_from timestamptz DEFAULT NOW(),
  algo text default 'sha1'
) returns text as $$
DECLARE 
  v_bytes_int int;
  n int;
  v_hmc bytea;
  v_offset int;

  v_secret bytea;
BEGIN
  n = totp.n(
    time_from,
    totp_interval
  );

  v_secret = totp_secret::bytea;

  v_hmc = totp.hmac_as_20_bytes( 
    totp.n_hex_to_8_bytes(
      totp.n_hex(n)
    ),
    v_secret,
    algo
  );

  v_offset = totp.get_offset(
    v_hmc
  );

  v_bytes_int = totp.compact_bytes_to_int( 
    totp.apply_binary_to_bytes(
      totp.get_first_4_bytes_from_offset(
        v_hmc,
        v_offset
      )
    )
  );

  RETURN totp.calculate_token(
    v_bytes_int,
    totp_length
  );

END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE FUNCTION totp.verify (
  totp_secret text,
  check_totp text,
  totp_interval int default 30,
  totp_length int default 6,
  time_from timestamptz DEFAULT NOW(),
  algo text default 'sha1'
)
  RETURNS boolean
  AS $$
  SELECT totp.generate (
    totp_secret,
    totp_interval,
    totp_length,
    time_from,
    algo) = check_totp;
$$
LANGUAGE 'sql';

CREATE FUNCTION totp.url (email text, totp_secret text, totp_interval int, totp_issuer text)
  RETURNS text
  AS $$
  SELECT
    concat('otpauth://totp/', totp.urlencode (email), '?secret=', totp.urlencode (totp_secret), '&period=', totp.urlencode (totp_interval::text), '&issuer=', totp.urlencode (totp_issuer));
$$
LANGUAGE 'sql'
STRICT IMMUTABLE;

COMMIT;

