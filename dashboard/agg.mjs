const SCAM_TYPES = Object.freeze([
  'OTP', 'KYC', 'DIGITAL_ARREST', 'COURIER_CUSTOMS', 'FAKE_QR',
  'LOAN_APP', 'INVESTMENT', 'JOB', 'MISTAKEN_TRANSFER', 'OTHER',
  'ELECTRICITY_BILL', 'SIM_SWAP', 'CUSTOMER_CARE', 'UPI_COLLECT', 'SEXTORTION', 'LOTTERY',
  'FAMILY_EMERGENCY', 'PHISHING_LINK',
]);
const REQUIRED_KEYS = Object.freeze(['date', 'district', 'scam_type']);

export function validateRecords(records, districts) {
  if (!Array.isArray(records)) throw new TypeError('records must be an array');
  if (!Array.isArray(districts) || districts.some((d) => typeof d !== 'string')) {
    throw new TypeError('districts must be an array of names');
  }
  const districtSet = new Set(districts);
  const typeSet = new Set(SCAM_TYPES);
  records.forEach((row, index) => {
    const fail = (message) => { throw new TypeError(`row ${index + 1}: ${message}`); };
    if (row === null || typeof row !== 'object' || Array.isArray(row)) fail('must be an object');
    const keys = Object.keys(row).sort();
    if (keys.length !== REQUIRED_KEYS.length || keys.some((key, i) => key !== REQUIRED_KEYS[i])) {
      fail('must have exactly district, scam_type, date');
    }
    if (typeof row.district !== 'string' || !districtSet.has(row.district)) fail('unknown district');
    if (typeof row.scam_type !== 'string' || !typeSet.has(row.scam_type)) fail('unknown scam_type');
    if (typeof row.date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(row.date)) fail('date must be YYYY-MM-DD');
    const parsed = new Date(`${row.date}T00:00:00.000Z`);
    if (Number.isNaN(parsed.valueOf()) || parsed.toISOString().slice(0, 10) !== row.date) fail('invalid calendar date');
  });
  return records;
}

function countBy(records, key) {
  const counts = Object.create(null);
  for (const row of records) counts[row[key]] = (counts[row[key]] ?? 0) + 1;
  return counts;
}

// ISO week key uses the week year's Monday date (YYYY-MM-DD), avoiding locale/timezone rules.
export function isoWeek(date) {
  const d = new Date(`${date}T00:00:00.000Z`);
  if (Number.isNaN(d.valueOf()) || d.toISOString().slice(0, 10) !== date) throw new TypeError('invalid date');
  const weekday = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - weekday + 3); // Thursday determines ISO week-year.
  const weekYear = d.getUTCFullYear();
  const jan4 = new Date(Date.UTC(weekYear, 0, 4));
  jan4.setUTCDate(jan4.getUTCDate() - ((jan4.getUTCDay() + 6) % 7));
  const week = 1 + Math.round((d - jan4) / (7 * 86400000));
  return `${weekYear}-W${String(week).padStart(2, '0')}`;
}

export function countByDistrict(records) { return countBy(records, 'district'); }
export function countByScamType(records) { return countBy(records, 'scam_type'); }
export function countByWeek(records) {
  const counts = Object.create(null);
  for (const row of records) {
    const week = isoWeek(row.date);
    counts[week] = (counts[week] ?? 0) + 1;
  }
  return counts;
}
export function countByTypePerWeek(records) {
  const counts = Object.create(null);
  for (const row of records) {
    const week = isoWeek(row.date);
    counts[week] ??= Object.create(null);
    counts[week][row.scam_type] = (counts[week][row.scam_type] ?? 0) + 1;
  }
  return counts;
}

export { SCAM_TYPES };
