-- Revert schemas/totp/procedures/urlencode from pg

BEGIN;

DROP FUNCTION totp.urlencode;

COMMIT;
