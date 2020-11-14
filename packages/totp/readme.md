# totp [![Build Status](https://travis-ci.com/pyramation/totp.svg?branch=master)](https://travis-ci.com/pyramation/totp)

TOTP implementation in pure PostgreSQL plpgsql

This extension provides the HMAC Time-Based One-Time Password Algorithm (TOTP) as specfied in RFC 4226 as pure plpgsql functions.

# Usage

## totp.generate

```sql
SELECT totp.generate('mysecret');

-- you can also specify totp_interval, and totp_length
SELECT totp.generate('mysecret', 30, 6);
```

In this case, produces a TOTP code of length 6

```
013438
```

## totp.verify

```sql
SELECT totp.verify('mysecret', '765430');

-- you can also specify totp_interval, and totp_length
SELECT totp.verify('mysecret', '765430', 30, 6);
```

Depending on input, returns `TRUE/FALSE` 

## totp.url

```sql
-- totp.url ( email text, totp_secret text, totp_interval int, totp_issuer text )
SELECT totp.url(
    'customer@email.com',
    'mysecret',
    30,
    'Acme Inc'
);
```

Will produce a URL-encoded string

```
otpauth://totp/customer@email.com?secret=mysecret&period=30&issuer=Acme%20Inc
```

# caveats

Currently only supports `sha1`, pull requests welcome!

# credits

Thanks to 

https://tools.ietf.org/html/rfc6238

https://www.youtube.com/watch?v=VOYxF12K1vE

https://pgxn.org/dist/otp/

# Development

## start the postgres db process

First you'll want to start the postgres docker (you can also just use `docker-compose up -d`):

```sh
make up
```

## install modules

Install modules

```sh
yarn install
```

## install the Postgres extensions

Now that the postgres process is running, install the extensions:

```sh
make install
```

This basically `ssh`s into the postgres instance with the `packages/` folder mounted as a volume, and installs the bundled sql code as pgxn extensions.

## testing

Testing will load all your latest sql changes and create fresh, populated databases for each sqitch module in `packages/`.

```sh
yarn test:watch
```

## building new modules

Create a new folder in `packages/`

```sh
lql init
```

Then, run a generator:

```sh
lql generate
```

You can also add arguments if you already know what you want to do:

```sh
lql generate schema --schema myschema
lql generate table --schema myschema --table mytable
```

## deploy code as extensions

`cd` into `packages/<module>`, and run `lql package`. This will make an sql file in `packages/<module>/sql/` used for `CREATE EXTENSION` calls to install your sqitch module as an extension.

## recursive deploy

You can also deploy all modules utilizing versioning as sqtich modules. Remove `--createdb` if you already created your db:

```sh
lql deploy awesome-db --yes --recursive --createdb
```
