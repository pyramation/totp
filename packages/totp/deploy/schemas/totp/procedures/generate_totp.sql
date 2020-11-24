-- Deploy schemas/totp/procedures/generate_totp to pg
-- requires: schemas/totp/schema
-- requires: schemas/totp/procedures/urlencode

BEGIN;

-- https://www.youtube.com/watch?v=VOYxF12K1vE
-- https://tools.ietf.org/html/rfc6238
-- http://blog.tinisles.com/2011/10/google-authenticator-one-time-password-algorithm-in-javascript/
-- https://gist.github.com/bwbroersma/676d0de32263ed554584ab132434ebd9

CREATE FUNCTION totp.pad_secret (
  input bytea,
  len int
) returns bytea as $$
DECLARE 
  output bytea;
  orig_length int = octet_length(input);
BEGIN
  IF (orig_length = len) THEN 
    RETURN input;
  END IF;

  -- create blank bytea size of new length
  output = lpad('', len, 'x')::bytea;

  FOR i IN 0 .. len-1 LOOP
    output = set_byte(output, i, get_byte(input, i % orig_length));
  END LOOP;

  RETURN output;
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE FUNCTION totp.base32_to_hex (
  input text
) returns text as $$
DECLARE 
  output text[];
  decoded text = base32.decode(input);
  len int = character_length(decoded);
  hx text;
BEGIN

  FOR i IN 1 .. len LOOP
    hx = to_hex(ascii(substring(decoded from i for 1)))::text;
    IF (character_length(hx) = 1) THEN 
        -- if it is odd number of digits, pad a 0 so it can later 
    		hx = '0' || hx;	
    END IF;
    output = array_append(output, hx);
  END LOOP;

  RETURN array_to_string(output, '');
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE FUNCTION totp.hotp(key BYTEA, c INT, digits INT DEFAULT 6, hash TEXT DEFAULT 'sha1') RETURNS TEXT AS $$
DECLARE
    c BYTEA := '\x' || LPAD(TO_HEX(c), 16, '0');
    mac BYTEA := HMAC(c, key, hash);
    trunc_offset INT := GET_BYTE(mac, length(mac) - 1) % 16;
    result TEXT := SUBSTRING(SET_BIT(SUBSTRING(mac FROM 1 + trunc_offset FOR 4), 7, 0)::TEXT, 2)::BIT(32)::INT % (10 ^ digits)::INT;
BEGIN
    RETURN LPAD(result, digits, '0');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE FUNCTION totp.generate(
    secret text, 
    period int DEFAULT 30,
    digits int DEFAULT 6, 
    time_from timestamptz DEFAULT NOW(),
    hash text DEFAULT 'sha1',
    encoding text DEFAULT 'base32',
    clock_offset int DEFAULT 0
) RETURNS text AS $$
DECLARE
    c int := FLOOR(EXTRACT(EPOCH FROM time_from) / period)::int + clock_offset;
    key bytea;
BEGIN

  IF (encoding = 'base32') THEN 
    key = ( '\x' || totp.base32_to_hex(secret) )::bytea;
  ELSE 
    key = secret::bytea;
  END IF;

  RETURN totp.hotp(key, c, digits, hash);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE FUNCTION totp.verify (
  secret text,
  check_totp text,
  period int default 30,
  digits int default 6,
  time_from timestamptz DEFAULT NOW(),
  hash text default 'sha1',
  encoding text DEFAULT 'base32',
  clock_offset int default 0
)
  RETURNS boolean
  AS $$
  SELECT totp.generate (
    secret,
    period,
    digits,
    time_from,
    hash,
    encoding,
    clock_offset) = check_totp;
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

