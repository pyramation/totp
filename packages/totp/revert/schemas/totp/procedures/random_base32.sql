-- Revert schemas/totp/procedures/random_base32 from pg

BEGIN;

DROP FUNCTION totp.random_base32;

COMMIT;
