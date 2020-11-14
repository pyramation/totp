-- Verify schemas/totp/procedures/urlencode  on pg

BEGIN;

SELECT verify_function ('totp.urlencode');

ROLLBACK;
