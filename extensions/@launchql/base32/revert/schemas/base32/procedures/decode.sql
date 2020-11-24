-- Revert schemas/base32/procedures/decode from pg

BEGIN;

DROP FUNCTION base32.decode;

COMMIT;
