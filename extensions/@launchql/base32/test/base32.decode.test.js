import { getConnections } from './utils';
import cases from 'jest-in-case';

let db, base32, teardown;
const objs = {
  tables: {}
};

beforeAll(async () => {
  ({ db, teardown } = await getConnections());
  base32 = db.helper('base32');
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

it('base32_to_decimal', async () => {
  const [{ base32_to_decimal }] = await base32.call('base32_to_decimal', {
    input: 'INQXI==='
  });
  expect(base32_to_decimal).toEqual([
    '8',
    '13',
    '16',
    '23',
    '8',
    '=',
    '=',
    '='
  ]);
});

it('base32_to_decimal', async () => {
  const [{ base32_to_decimal }] = await base32.call('base32_to_decimal', {
    input: 'INQXI==='
  });
  expect(base32_to_decimal).toEqual([
    '8',
    '13',
    '16',
    '23',
    '8',
    '=',
    '=',
    '='
  ]);
});

it('decimal_to_chunks', async () => {
  const [{ decimal_to_chunks }] = await base32.call(
    'decimal_to_chunks',
    {
      input: ['8', '13', '16', '23', '8', '=', '=', '=']
    },
    {
      input: 'text[]'
    }
  );
  expect(decimal_to_chunks).toEqual([
    '01000',
    '01101',
    '10000',
    '10111',
    '01000',
    'xxxxx',
    'xxxxx',
    'xxxxx'
  ]);
});

it('decode', async () => {
  const [{ decode }] = await base32.call('decode', {
    input: 'INQXI'
  });
  expect(decode).toEqual('Cat');
});

it('zero_fill', async () => {
  const [{ zero_fill }] = await base32.call('zero_fill', {
    a: 300,
    b: 2
  });
  expect(zero_fill).toBe('75');
});

it('zero_fill (-)', async () => {
  const [{ zero_fill }] = await base32.call('zero_fill', {
    a: -300,
    b: 2
  });
  expect(zero_fill).toBe('1073741749');
});

it('zero_fill (0)', async () => {
  const [{ zero_fill }] = await base32.call('zero_fill', {
    a: -300,
    b: 0
  });
  expect(zero_fill).toBe('4294966996');
});

cases(
  'base32',
  async (opts) => {
    const [result] = await base32.call('decode', {
      input: opts.name
    });
    expect(result.decode).toEqual(opts.result);
    expect(result.decode).toMatchSnapshot();
  },
  [
    { result: '', name: '' },
    { result: 'Cat', name: 'INQXI' },
    { result: 'chemistryisgreat', name: 'MNUGK3LJON2HE6LJONTXEZLBOQ======' },
    { result: 'f', name: 'MY======' },
    { result: 'fo', name: 'MZXQ====' },
    { result: 'foo', name: 'MZXW6===' },
    { result: 'foob', name: 'MZXW6YQ=' },
    { result: 'fooba', name: 'MZXW6YTB' },
    { result: 'fooba', name: 'mzxw6ytb' },
    { result: 'foobar', name: 'MZXW6YTBOI======' }
  ]
);
