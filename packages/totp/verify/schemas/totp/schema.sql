-- Verify schemas/totp/schema  on pg

BEGIN;

SELECT verify_schema ('totp');

ROLLBACK;
