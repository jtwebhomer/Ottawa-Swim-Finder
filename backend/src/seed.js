import 'dotenv/config';
import path from 'path';
import { fileURLToPath } from 'url';
import { getDb } from './db.js';
import { seedFromAssets } from './syncService.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DB_PATH = path.resolve(
  process.env.DATABASE_PATH || path.join(__dirname, '../data/ottawa_swim.db'),
);

const db = getDb(DB_PATH);
await seedFromAssets(db);
console.log('Seed complete:', DB_PATH);
