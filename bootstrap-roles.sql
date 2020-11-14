-- anonymous
CREATE ROLE anonymous;

ALTER USER anonymous WITH NOCREATEDB;

ALTER USER anonymous WITH NOSUPERUSER;

ALTER USER anonymous WITH NOCREATEROLE;

ALTER USER anonymous WITH NOLOGIN;

ALTER USER anonymous WITH NOREPLICATION;

ALTER USER anonymous WITH NOBYPASSRLS;

-- authenticated
CREATE ROLE authenticated;

ALTER USER authenticated WITH NOCREATEDB;

ALTER USER authenticated WITH NOSUPERUSER;

ALTER USER authenticated WITH NOCREATEROLE;

ALTER USER authenticated WITH NOLOGIN;

ALTER USER authenticated WITH NOREPLICATION;

ALTER USER authenticated WITH NOBYPASSRLS;

-- administrator
CREATE ROLE administrator;

ALTER USER administrator WITH NOCREATEDB;

ALTER USER administrator WITH NOSUPERUSER;

ALTER USER administrator WITH NOCREATEROLE;

ALTER USER administrator WITH NOLOGIN;

ALTER USER administrator WITH NOREPLICATION;

-- they CAN bypass RLS
ALTER USER administrator WITH BYPASSRLS;

-- app user
CREATE ROLE app_user LOGIN PASSWORD 'app_password';

GRANT anonymous TO app_user;

GRANT authenticated TO app_user;

-- admin user
CREATE ROLE app_admin LOGIN PASSWORD 'admin_password';

GRANT anonymous TO administrator;

GRANT authenticated TO administrator;

GRANT administrator TO app_admin;

