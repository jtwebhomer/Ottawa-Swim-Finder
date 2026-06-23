import Database from 'better-sqlite3';
const db = new Database('./data/ottawa_swim.db');
const logs = db.prepare('SELECT * FROM sync_logs ORDER BY timestamp DESC LIMIT 5').all();
const bySource = db
  .prepare('SELECT source_status, source, COUNT(*) as c FROM schedules GROUP BY source_status, source')
  .all();
const verified = db
  .prepare("SELECT COUNT(*) as c FROM facilities WHERE last_verified IS NOT NULL")
  .get();
console.log(JSON.stringify({ sync_logs: logs, bySource, facilities_verified: verified.c }, null, 2));
