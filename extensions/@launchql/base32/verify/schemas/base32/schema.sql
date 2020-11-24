-- Verify schemas/base32/schema  on pg

BEGIN;

SELECT verify_schema ('base32');

ROLLBACK;
