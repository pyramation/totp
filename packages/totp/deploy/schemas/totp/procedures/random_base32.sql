-- Deploy schemas/totp/procedures/random_base32 to pg
-- requires: schemas/totp/schema

BEGIN;

CREATE FUNCTION totp.random_base32 (_length int DEFAULT 16)
  RETURNS text
  LANGUAGE sql
  AS $$
  SELECT
    string_agg(('{a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z,2,3,4,5,6,7}'::text[])[ceil(random() * 32)], '')
  FROM
    generate_series(1, _length);
$$;

COMMIT;

