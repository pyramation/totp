import { getConnections } from './utils';

let db, totp, teardown;
const objs = {
  tables: {}
};

beforeAll(async () => {
  ({ db, teardown } = await getConnections());
  totp = db.helper('totp');
});

afterAll(async () => {
  try {
    //try catch here allows us to see the sql parsing issues!
    await teardown();
  } catch (e) {
    // noop
  }
});

beforeEach(async () => {
  await db.beforeEach();
});

afterEach(async () => {
  await db.afterEach();
});

it('generates secrets', async () => {
  const secrets = await db.one(`SELECT * FROM totp.random_base32($1)`, [16]);
  expect(secrets).toBeTruthy();
});
it('interval TOTP', async () => {
  const [
    { interval }
  ] = await db.any(`SELECT * FROM totp.generate($1) as interval`, [
    'vmlhl2knm27eftq7'
  ]);
  // console.log('interval TOTP', interval);
  expect(interval).toBeTruthy();
});
it('TOTP', async () => {
  const [{ totp }] = await db.any(
    `SELECT * FROM totp.generate(
    secret := $1, 
    period := $2,
    digits := $3,
    time_from := $4,
    encoding := 'base32'
  ) as totp`,
    ['vmlhl2knm27eftq7', 30, 6, '2020-02-05 22:11:40.56915+00']
  );
  expect(totp).toEqual('295485');
});
it('validation', async () => {
  const [{ verified }] = await db.any(
    `SELECT * FROM totp.verify(
      secret := $1,
      check_totp := $2,
      period := $3,
      digits := $4,
      time_from := $5,
      encoding := 'base32'
    ) as verified`,
    ['vmlhl2knm27eftq7', '295485', 30, 6, '2020-02-05 22:11:40.56915+00']
  );
  expect(verified).toBe(true);
});
it('URL Encode', async () => {
  const [{ urlencode }] = await db.any(
    `
        SELECT * FROM totp.urlencode($1)
      `,
    ['http://hu.wikipedia.org/wiki/São_Paulo']
  );
  expect(urlencode).toEqual('http://hu.wikipedia.org/wiki/S%C3%A3o_Paulo');
});
it('URLs', async () => {
  const [{ url }] = await db.any(
    `
        SELECT * FROM totp.url($1, $2, $3, $4) as url
      `,
    ['dude@example.com', 'vmlhl2knm27eftq7', 30, 'acme']
  );
  expect(url).toEqual(
    'otpauth://totp/dude@example.com?secret=vmlhl2knm27eftq7&period=30&issuer=acme'
  );
});
it('time-based validation wont verify in test', async () => {
  const [{ verified }] = await db.any(
    `
        SELECT * FROM totp.verify($1, $2, $3, $4) as verified
      `,
    ['vmlhl2knm27eftq7', '843386', 30, 6]
  );
  expect(verified).toBe(false);
});
