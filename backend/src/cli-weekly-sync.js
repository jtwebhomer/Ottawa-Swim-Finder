import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { getDb } from './db.js';
import { runWeeklyFullSync } from './syncService.js';
import { runSyncJob } from './syncRunner.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DB_PATH = path.resolve(
  process.env.DATABASE_PATH || path.join(__dirname, '../data/ottawa_swim.db'),
);
const LOG_DIR = path.resolve(__dirname, '../logs');

if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });

const db = getDb(DB_PATH);
const result = await runSyncJob(
  runWeeklyFullSync,
  db,
  { headless: process.env.PLAYWRIGHT_HEADLESS !== 'false' },
  'weekly-cli',
);

console.log('[cli-weekly-sync]', JSON.stringify(result));
process.exit(result.skipped ? 0 : result.status === 'failure' ? 1 : 0);
