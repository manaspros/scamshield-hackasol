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

test('T3_9_headlineAndAccuracyTiles', async () => {
  const { headline, modelAccuracy, niceScale, spreadLabels, themeLabel } = await import('../app.js');
  assert.deepEqual([themeLabel(true), themeLabel(false)], ['Light theme', 'Dark theme']);
  const rows = [
    { district: 'Raipur', scam_type: 'OTP', date: '2026-01-05' },
    { district: 'Raipur', scam_type: 'OTHER', date: '2026-01-06' },
    { district: 'Raipur', scam_type: 'KYC', date: '2026-01-12' },
    { district: 'Raipur', scam_type: 'KYC', date: '2026-01-13' },
  ];
  const h = headline(rows);
  assert.deepEqual([h.total, h.detected, h.unclassified, h.delta], [4, 3, 1, 0]);
  assert.equal(h.topType.name, 'KYC');
  const { typeName } = await import('../app.js');
  assert.deepEqual(['FAKE_QR', 'DIGITAL_ARREST', 'MISTAKEN_TRANSFER'].map(typeName), ['Fake QR', 'Digital arrest', 'Mistaken transfer']);
  const m1 = JSON.parse(readFileSync(join(dir, 'm1.json'), 'utf8'));
  const a = modelAccuracy(m1);
  assert.equal(a.system, 'Base Gemma 3 1B');
  assert.ok(Math.abs(a.value - 24 / 26) < 1e-9);
  assert.equal(modelAccuracy(null), null);
  assert.deepEqual(niceScale(9), { step: 5, top: 10 });
  const ys = spreadLabels([10, 11, 12], 16, 0, 100);
  assert.ok(ys[1] - ys[0] >= 16 && ys[2] - ys[1] >= 16);
});

test('T3_9_chartsAreInlineAndOffline', () => {
  assert.doesNotMatch(html, /<script[^>]+src="https?:/i);
  assert.doesNotMatch(html + js, /cdn\.|googleapis/i);
  assert.match(js, /createElementNS/);
  assert.match(js, /role: 'img'/);
});

test('T3_9_accuracyRowsFollowDataForTwoAndThreeSystems', async () => {
  const { accuracyRows, modelAccuracy, accuracyText } = await import('../app.js');
  const m = (p, r, tp, fp, fn, tn) => ({ precision: p, recall: r, fpr: 0, counts: { n: tp + fp + fn + tn, tp, fp, fn, tn } });
  const two = { data: { headline: 'synthetic' }, systems: {
    rules: { overall: m(1, 0.5, 5, 0, 5, 5), per_language: { en: m(1, 0.5, 5, 0, 5, 5) } },
    base_gemma: { overall: m(1, 0.9, 9, 0, 1, 5), per_language: { hi: m(1, 0.9, 9, 0, 1, 5) } },
    finetuned_gemma: { status: 'not run' } } };
  const rows2 = accuracyRows(two);
  assert.deepEqual(rows2.map((r) => [r.name, !!r.notRun]), [['Rules only', false], ['Base Gemma 3 1B', false], ['Fine-tuned Gemma', true]]);
  assert.equal(rows2[1].langs[0].name, 'Hindi');
  // The key missing entirely, or present with null metrics, also reads as not run.
  const noKey = structuredClone(two); delete noKey.systems.finetuned_gemma;
  const nullMetrics = structuredClone(two); nullMetrics.systems.finetuned_gemma = { overall: { precision: null, recall: null } };
  for (const f of [noKey, nullMetrics]) assert.equal(accuracyRows(f)[2].notRun, true);
  assert.equal(rows2[2].status, 'Not run yet');
  const future = structuredClone(two); future.systems.finetuned_gemma = { status: 'future work (not planned for this prototype)' };
  assert.equal(accuracyRows(future)[2].status, 'Future work (not planned for this prototype)');
  assert.equal(modelAccuracy(two).system, 'Base Gemma 3 1B');
  const three = structuredClone(two);
  three.systems.finetuned_gemma = { overall: m(1, 1, 10, 0, 0, 5), per_language: { en: m(1, 1, 10, 0, 0, 5) } };
  const rows3 = accuracyRows(three);
  assert.equal(rows3.length, 3);
  assert.ok(rows3.every((r) => !r.notRun));
  assert.equal(modelAccuracy(three).system, 'Fine-tuned Gemma');
  assert.equal(modelAccuracy(three).value, 1);
  assert.equal(accuracyText(three), '');
});
