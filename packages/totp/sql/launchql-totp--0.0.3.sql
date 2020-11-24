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

CREATE FUNCTION totp.pad_secret ( input bytea, len int ) RETURNS bytea AS $EOFCODE$
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
$EOFCODE$ LANGUAGE plpgsql IMMUTABLE;

CREATE FUNCTION totp.base32_to_hex ( input text ) RETURNS text AS $EOFCODE$
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
$EOFCODE$ LANGUAGE plpgsql IMMUTABLE;

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

CREATE FUNCTION totp.generate ( secret text, period int DEFAULT 30, digits int DEFAULT 6, time_from timestamptz DEFAULT now(), hash text DEFAULT 'sha1', encoding text DEFAULT 'base32', clock_offset int DEFAULT 0 ) RETURNS text AS $EOFCODE$
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
$EOFCODE$ LANGUAGE plpgsql STABLE;

CREATE FUNCTION totp.verify ( secret text, check_totp text, period int DEFAULT 30, digits int DEFAULT 6, time_from timestamptz DEFAULT now(), hash text DEFAULT 'sha1', encoding text DEFAULT 'base32', clock_offset int DEFAULT 0 ) RETURNS boolean AS $EOFCODE$
  SELECT totp.generate (
    secret,
    period,
    digits,
    time_from,
    hash,
    encoding,
    clock_offset) = check_totp;
$EOFCODE$ LANGUAGE sql;

CREATE FUNCTION totp.url ( email text, totp_secret text, totp_interval int, totp_issuer text ) RETURNS text AS $EOFCODE$
  SELECT
    concat('otpauth://totp/', totp.urlencode (email), '?secret=', totp.urlencode (totp_secret), '&period=', totp.urlencode (totp_interval::text), '&issuer=', totp.urlencode (totp_issuer));
$EOFCODE$ LANGUAGE sql STRICT IMMUTABLE;

CREATE FUNCTION totp.random_base32 ( _length int DEFAULT 20 ) RETURNS text LANGUAGE sql AS $EOFCODE$
  SELECT
    string_agg(('{a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z,2,3,4,5,6,7}'::text[])[ceil(random() * 32)], '')
  FROM
    generate_series(1, _length);
$EOFCODE$;

CREATE FUNCTION totp.generate_secret ( hash text DEFAULT 'sha1' ) RETURNS bytea AS $EOFCODE$
BEGIN
    -- See https://tools.ietf.org/html/rfc4868#section-2.1.2
    -- The optimal key length for HMAC is the block size of the algorithm
    CASE
          WHEN hash = 'sha1'   THEN RETURN totp.random_base32(20); -- = 160 bits
          WHEN hash = 'sha256' THEN RETURN totp.random_base32(32); -- = 256 bits
          WHEN hash = 'sha512' THEN RETURN totp.random_base32(64); -- = 512 bits
          ELSE
            RAISE EXCEPTION 'Unsupported hash algorithm for OTP (see RFC6238/4226).';
            RETURN NULL;
    END CASE;
END;
$EOFCODE$ LANGUAGE plpgsql VOLATILE;