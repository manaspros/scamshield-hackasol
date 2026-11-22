import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = join(dirname(fileURLToPath(import.meta.url)), '..');
const html = readFileSync(join(dir, 'index.html'), 'utf8');
const js = readFileSync(join(dir, 'app.js'), 'utf8');
const isLocal = (r) => !/^([a-z]+:|\/\/|#|data:)/i.test(r);

test('T3_9_referencedFilesExist', () => {
  const refs = [...html.matchAll(/\b(?:src|href)="([^"]+)"/g)].map((m) => m[1]);
  refs.push(...[...js.matchAll(/from '(\.[^']+)'/g)].map((m) => m[1]));
  // Fetched at runtime; the sample and district data are static repo files.
  refs.push(...[...js.matchAll(/(?:SAMPLE|DISTRICTS)_URL = '([^']+)'/g)].map((m) => m[1]));
  assert.ok(refs.length >= 4);
  for (const r of refs.filter(isLocal)) assert.ok(existsSync(join(dir, r)), `missing ${r}`);
});

test('T3_9_importsAgg', () => {
  assert.match(js, /from '\.\/agg\.mjs'/);
});

test('T3_9_notMeasuredPath', async () => {
  const { accuracyText, parseExport, summarize } = await import('../app.js');
  assert.equal(accuracyText(null), 'not measured');
  assert.equal(accuracyText({ systems: {} }), 'not measured');
  assert.equal(accuracyText({ rules: { precision: 0.9 } }), '');
  const districts = ['Raipur'];
  assert.throws(() => parseExport('{nope', districts), /not valid JSON/);
  assert.throws(() => parseExport('[{"district":"X","scam_type":"OTP","date":"2026-01-01"}]', districts), /unknown district/);
  const ok = parseExport('{"_synthetic":true,"rows":[{"district":"Raipur","scam_type":"OTP","date":"2026-01-05"}]}', districts);
  assert.equal(ok.synthetic, true);
  assert.equal(summarize(ok.rows).total, 1);
});
