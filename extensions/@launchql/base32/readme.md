# base32 [![Build Status](https://travis-ci.com/pyramation/base32.svg?branch=master)](https://travis-ci.com/pyramation/base32)

RFC4648 Base32 encode/decode in plpgsql

# Usage

```sql
select base32.encode('foo');
-- MZXW6===


select base32.decode('MZXW6===');
-- foo
```

# credits

Thanks to 

https://tools.ietf.org/html/rfc4648

https://www.youtube.com/watch?v=Va8FLD-iuTg

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
