import test from 'node:test';
import assert from 'node:assert/strict';
import { typeName, accuracyRows } from '../app.js';

test('QA pending typeName never returns a non-string for prototype-named types', () => {
  for (const t of ['constructor', 'toString', '__proto__', 'hasOwnProperty']) assert.equal(typeof typeName(t), 'string', t);
});

test('QA pending accuracyRows system names are strings for prototype-named system keys', () => {
  const rows = accuracyRows({ systems: { constructor: { overall: { precision: 1 } } } });
  for (const r of rows) assert.equal(typeof r.name, 'string');
});
