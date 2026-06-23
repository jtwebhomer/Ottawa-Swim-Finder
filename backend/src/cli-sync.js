import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { getDb } from './db.js';
import { seedFromAssets, runWeeklyFullSync } from './syncService.js';
import { runSyncJob } from './syncRunner.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DB_PATH = path.resolve(
  process.env.DATABASE_PATH || path.join(__dirname, '../data/ottawa_swim.db'),
);
const LOG_DIR = path.resolve(__dirname, '../logs');

if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });

const logFile = path.join(
  LOG_DIR,
  `sync-${new Date().toISOString().replace(/[:.]/g, '-')}.log`,
);
const logStream = fs.createWriteStream(logFile, { flags: 'a' });

function log(...args) {
  const line = args.map(String).join(' ');
  console.log(line);
  logStream.write(`${new Date().toISOString()} ${line}\n`);
}

const db = getDb(DB_PATH);
await seedFromAssets(db);

log('[cli-sync] Starting weekly full sync');
const result = await runSyncJob(
  runWeeklyFullSync,
  db,
  { headless: process.env.PLAYWRIGHT_HEADLESS !== 'false' },
  'scheduled-task',
);

log('[cli-sync] Result:', JSON.stringify(result));
logStream.end();

if (result.skipped) process.exit(0);
process.exit(result.status === 'failure' ? 1 : 0);
