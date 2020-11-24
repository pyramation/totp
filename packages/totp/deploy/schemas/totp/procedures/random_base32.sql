-- Deploy schemas/totp/procedures/random_base32 to pg
-- requires: schemas/totp/schema

BEGIN;

CREATE FUNCTION totp.random_base32 (_length int DEFAULT 20)
  RETURNS text
  LANGUAGE sql
  AS $$
  SELECT
    string_agg(('{a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z,2,3,4,5,6,7}'::text[])[ceil(random() * 32)], '')
  FROM
    generate_series(1, _length);
$$;

CREATE FUNCTION totp.generate_secret(hash TEXT DEFAULT 'sha1') RETURNS BYTEA AS $$
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
$$ LANGUAGE plpgsql VOLATILE;

COMMIT;

