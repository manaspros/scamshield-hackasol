#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { validateRecords } from './agg.mjs';

async function main() {
  const file = process.argv[2];
  if (!file || process.argv.length !== 3) throw new Error('usage: node dashboard/validate.mjs <file>');
  const [input, districtFile] = await Promise.all([
    readFile(file, 'utf8'),
    readFile(new URL('../data/districts.json', import.meta.url), 'utf8'),
  ]);
  const parsed = JSON.parse(input);
  // Accept a bare array or the documented metadata wrapper used by sample data.
  const rows = Array.isArray(parsed) ? parsed : parsed && Array.isArray(parsed.rows) ? parsed.rows : null;
  if (!rows) throw new Error('input must be an array or an object with a rows array');
  const districtData = JSON.parse(districtFile);
  validateRecords(rows, districtData.districts);
  process.stdout.write(`Valid: ${rows.length} records\n`);
}

main().catch((error) => {
  process.stderr.write(`Invalid: ${error.message}\n`);
  process.exitCode = 1;
});
