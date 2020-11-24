-- Revert schemas/base32/procedures/encode from pg

BEGIN;

DROP FUNCTION base32.encode;

COMMIT;
