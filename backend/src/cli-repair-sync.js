import 'dotenv/config';
import path from 'path';
import { fileURLToPath } from 'url';
import { getDb } from './db.js';
import { runRepairSync } from './syncService.js';
import { runSyncJob } from './syncRunner.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DB_PATH = path.resolve(
  process.env.DATABASE_PATH || path.join(__dirname, '../data/ottawa_swim.db'),
);

const db = getDb(DB_PATH);
const result = await runSyncJob(
  runRepairSync,
  db,
  { headless: process.env.PLAYWRIGHT_HEADLESS !== 'false' },
  'repair-cli',
);

console.log('[cli-repair-sync]', JSON.stringify(result));
process.exit(result.skipped ? 0 : result.status === 'failure' ? 1 : 0);
