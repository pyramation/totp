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

/*
  input: Cat (with a cap C)

  
  ASCII decimal values [67,97,116]
  Binary format [01000011, 01100001, 01110100]

 
  (BYTE = 8 bits)

  convert an input byte stream into group of 5 bytes
  if there are less than 5, adding padding
 
  [01000011, 01100001, 01110100, xxxxxxxx, xxxxxxxx]

  break these into 5 bit chunks (5 * 8 = 40 bits, when we 40/5 = 8 new elements of 5 bits each)

  [01000, 01101, 10000, 10111, 0100x, xxxxx, xxxxx, xxxxx]

  if a chunk has a mix of real bits (0|1) and empty (x), replace x with 0

  [01000, 01101, 10000, 10111, 01000, xxxxx, xxxxx, xxxxx]

  convert to decimal value

  [01000, 01101, 10000, 10111, 01000, xxxxx, xxxxx, xxxxx]
  [0b01000, 0b01101, 0b10000, 0b10111, 0b01000, xxxxx, xxxxx, xxxxx]
  
  convert to decimal value
  
  [ 8, 13, 16, 23, 8, '=', '=', '=' ]
  
  
  Table 3: The Base 32 Alphabet
  
  Value Encoding  Value Encoding  Value Encoding  Value Encoding
  0 A             9 J            18 S            27 3
  1 B            10 K            19 T            28 4
  2 C            11 L            20 U            29 5
  3 D            12 M            21 V            30 6
  4 E            13 N            22 W            31 7
  5 F            14 O            23 X
  6 G            15 P            24 Y         (pad) =
  7 H            16 Q            25 Z
  8 I            17 R            26 2
  
  [ 8, 13, 16, 23, 8, '=', '=', '=' ]
  [ I, N, Q, X, I, '=', '=', '=' ]

  */

it('to_ascii', async () => {
  const [{ to_ascii }] = await base32.call('to_ascii', {
    input: 'Cat'
  });
  expect(to_ascii).toEqual([67, 97, 116]);
});

it('to_binary', async () => {
  const [{ to_ascii }] = await base32.call('to_ascii', {
    input: 'Cat'
  });
  const [{ to_binary }] = await base32.call(
    'to_binary',
    {
      input: to_ascii
    },
    {
      input: 'int[]'
    }
  );
  expect(to_binary).toEqual(['01000011', '01100001', '01110100']);
});

it('to_groups', async () => {
  const [{ to_groups }] = await base32.call(
    'to_groups',
    {
      input: ['01000011', '01100001', '01110100']
    },
    {
      input: 'text[]'
    }
  );
  // [01000011, 01100001, 01110100, xxxxxxxx, xxxxxxxx]
  expect(to_groups).toEqual([
    '01000011',
    '01100001',
    '01110100',
    'xxxxxxxx',
    'xxxxxxxx'
  ]);
});

it('to_chunks', async () => {
  const [{ to_chunks }] = await base32.call(
    'to_chunks',
    {
      input: ['01000011', '01100001', '01110100', 'xxxxxxxx', 'xxxxxxxx']
    },
    {
      input: 'text[]'
    }
  );
  expect(to_chunks).toEqual([
    '01000',
    '01101',
    '10000',
    '10111',
    '0100x',
    'xxxxx',
    'xxxxx',
    'xxxxx'
  ]);
});

it('fill_chunks', async () => {
  const [{ fill_chunks }] = await base32.call(
    'fill_chunks',
    {
      input: [
        '01000',
        '01101',
        '10000',
        '10111',
        '0100x',
        'xxxxx',
        'xxxxx',
        'xxxxx'
      ]
    },
    {
      input: 'text[]'
    }
  );
  expect(fill_chunks).toEqual([
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

it('to_decimal', async () => {
  const [{ to_decimal }] = await base32.call(
    'to_decimal',
    {
      input: [
        '01000',
        '01101',
        '10000',
        '10111',
        '01000',
        'xxxxx',
        'xxxxx',
        'xxxxx'
      ]
    },
    {
      input: 'text[]'
    }
  );
  expect(to_decimal).toEqual(['8', '13', '16', '23', '8', '=', '=', '=']);
});

it('to_base32', async () => {
  const [{ to_base32 }] = await base32.call(
    'to_base32',
    {
      input: ['8', '13', '16', '23', '8', '=', '=', '=']
    },
    {
      input: 'text[]'
    }
  );
  expect(to_base32).toEqual('INQXI===');
});

cases(
  'base32',
  async (opts) => {
    const [result] = await base32.call('encode', {
      input: opts.name
    });
    expect(result.encode).toEqual(opts.result);
    expect(result.encode).toMatchSnapshot();
  },
  [
    { name: '', result: '' },
    { name: 'f', result: 'MY======' },
    { name: 'fo', result: 'MZXQ====' },
    { name: 'foo', result: 'MZXW6===' },
    { name: 'foob', result: 'MZXW6YQ=' },
    { name: 'fooba', result: 'MZXW6YTB' },
    { name: 'foobar', result: 'MZXW6YTBOI======' }
  ]
);
