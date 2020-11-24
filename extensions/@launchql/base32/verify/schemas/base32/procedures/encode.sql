-- Verify schemas/base32/procedures/encode  on pg

BEGIN;

SELECT verify_function ('base32.encode');

ROLLBACK;
