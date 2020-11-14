-- Verify schemas/totp/procedures/generate_totp  on pg

BEGIN;

SELECT verify_function ('totp.generate_totp');

ROLLBACK;
