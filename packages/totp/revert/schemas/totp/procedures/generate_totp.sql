-- Revert schemas/totp/procedures/generate_totp from pg

BEGIN;

-- DROP FUNCTION totp.generate_totp;

COMMIT;
