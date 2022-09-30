\echo Use "CREATE EXTENSION launchql-totp" to load this file. \quit
CREATE SCHEMA totp;

CREATE FUNCTION totp.urlencode ( in_str text ) RETURNS text AS $EOFCODE$
DECLARE
  _i int4;
  _temp varchar;
  _ascii int4;
  _result text := '';
BEGIN
  FOR _i IN 1..length(in_str)
  LOOP
    _temp := substr(in_str, _i, 1);
    IF _temp ~ '[0-9a-zA-Z:/@._?#-]+' THEN
      _result := _result || _temp;
    ELSE
      _ascii := ascii(_temp);
      IF _ascii > x'07ff'::int4 THEN
        RAISE exception 'won''t deal with 3 (or more) byte sequences.';
      END IF;
      IF _ascii <= x'07f'::int4 THEN
        _temp := '%' || to_hex(_ascii);
      ELSE
        _temp := '%' || to_hex((_ascii & x'03f'::int4) + x'80'::int4);
        _ascii := _ascii >> 6;
        _temp := '%' || to_hex((_ascii & x'01f'::int4) + x'c0'::int4) || _temp;
      END IF;
      _result := _result || upper(_temp);
    END IF;
  END LOOP;
  RETURN _result;
END;
$EOFCODE$ LANGUAGE plpgsql STRICT IMMUTABLE;


CREATE FUNCTION totp.hotp ( key bytea, c int, digits int DEFAULT 6, hash text DEFAULT 'sha1' ) RETURNS text AS $EOFCODE$
DECLARE
    c BYTEA := '\x' || LPAD(TO_HEX(c), 16, '0');
    mac BYTEA := HMAC(c, key, hash);
    trunc_offset INT := GET_BYTE(mac, length(mac) - 1) % 16;
    result TEXT := SUBSTRING(SET_BIT(SUBSTRING(mac FROM 1 + trunc_offset FOR 4), 7, 0)::TEXT, 2)::BIT(32)::INT % (10 ^ digits)::INT;
BEGIN
    RETURN LPAD(result, digits, '0');
END;
$EOFCODE$ LANGUAGE plpgsql IMMUTABLE;


CREATE FUNCTION totp.generate ( secret bytea, period int DEFAULT 30, digits int DEFAULT 6, time_from timestamptz DEFAULT now(), hash text DEFAULT 'sha1', clock_offset int DEFAULT 0 ) RETURNS text AS $EOFCODE$
DECLARE
    c int := FLOOR(EXTRACT(EPOCH FROM time_from) / period)::int + clock_offset;
BEGIN
  RETURN totp.hotp(secret, c, digits, hash);
END;
$EOFCODE$ LANGUAGE plpgsql VOLATILE;


CREATE FUNCTION totp.constant_time_equal(a text, b text, minlength int DEFAULT 6) RETURNS boolean AS $EOFCODE$
-- Compare all of the individual characters of each string
-- minlength is optional, prevents timing attacks to discover the length of the string
-- Create a table of true/false for each individual character comparison
-- Count the true/false
-- Compare the count of true to the number of comparisons.
  WITH maxlen AS (
    SELECT max(s) AS l
    FROM (VALUES (octet_length(a)),
                 (octet_length(b)),
                 (minlength)) AS val(s)
  ),
  matches AS (
    SELECT substring(a FROM ix for 1) = substring(b FROM ix for 1) AS eq
    FROM (SELECT generate_series(1, (SELECT l FROM maxlen)) AS ix) AS series
  ),
  counts AS (
    SELECT count(*) AS ct, eq
    FROM matches GROUP BY eq
  )
  SELECT (SELECT l FROM maxlen) = coalesce((SELECT ct FROM counts WHERE eq='t'), 0)

$EOFCODE$ language sql VOLATILE;

CREATE FUNCTION totp.verify ( secret bytea, check_totp text, period int DEFAULT 30, digits int DEFAULT 6, time_from timestamptz DEFAULT now(), hash text DEFAULT 'sha1', clock_offset int DEFAULT 0 ) RETURNS boolean AS $EOFCODE$
  SELECT totp.constant_time_equal(
    totp.generate (
      secret,
      period,
      digits,
      time_from,
      hash,
      clock_offset),
    check_totp);
$EOFCODE$ LANGUAGE sql VOLATILE;

CREATE FUNCTION totp.url ( email text, totp_secret bytea, totp_interval int, totp_issuer text ) RETURNS text AS $EOFCODE$
  SELECT
    concat('otpauth://totp/',
           totp.urlencode (email),
           '?secret=',
           totp.urlencode (base32.encode(totp_secret::text)),
           '&period=',
           totp.urlencode (totp_interval::text),
           '&issuer=',
           totp.urlencode (totp_issuer));
$EOFCODE$ LANGUAGE sql STRICT IMMUTABLE;

CREATE FUNCTION totp.generate_secret ( hash text DEFAULT 'sha1' ) RETURNS bytea AS $EOFCODE$
BEGIN
    -- See https://tools.ietf.org/html/rfc4868#section-2.1.2
    -- The optimal key length for HMAC is the block size of the algorithm
    CASE
          WHEN hash = 'sha1'   THEN RETURN gen_random_bytes(20); -- = 160 bits
          WHEN hash = 'sha256' THEN RETURN gen_random_bytes(32); -- = 256 bits
          WHEN hash = 'sha512' THEN RETURN gen_random_bytes(64); -- = 512 bits
          ELSE
            RAISE EXCEPTION 'Unsupported hash algorithm for OTP (see RFC6238/4226).';
            RETURN NULL;
    END CASE;
END;
$EOFCODE$ LANGUAGE plpgsql VOLATILE;
