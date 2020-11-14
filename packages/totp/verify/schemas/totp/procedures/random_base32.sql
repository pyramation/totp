-- Verify schemas/totp/procedures/random_base32  on pg

BEGIN;

SELECT verify_function ('totp.random_base32');

ROLLBACK;
