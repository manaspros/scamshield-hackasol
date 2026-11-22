import test from 'node:test';
import assert from 'node:assert/strict';
import { countByTypePerWeek, countByWeek, validateRecords } from '../agg.mjs';

const districts = ['Raipur', 'Bilaspur'];

test('T3_7_rejectsExtraKeys', () => {
  assert.throws(() => validateRecords([
    { district: 'Raipur', scam_type: 'OTP', date: '2026-01-01', note: 'private' },
  ], districts), /exactly district, scam_type, date/);
  assert.throws(() => validateRecords([
    { district: 'Raipur', scam_type: 'OTP' },
  ], districts), /exactly district, scam_type, date/);
});

test('T3_7_weeklyCounts', () => {
  const rows = [
    { district: 'Raipur', scam_type: 'OTP', date: '2026-01-05' },
    { district: 'Bilaspur', scam_type: 'OTP', date: '2026-01-11' },
    { district: 'Raipur', scam_type: 'KYC', date: '2026-01-12' },
  ];
  assert.deepEqual({ ...countByWeek(rows) }, { '2026-W02': 2, '2026-W03': 1 });
  assert.deepEqual(JSON.parse(JSON.stringify(countByTypePerWeek(rows))), {
    '2026-W02': { OTP: 2 }, '2026-W03': { KYC: 1 },
  });
});
