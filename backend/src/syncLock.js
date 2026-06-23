import fs from 'fs';
import path from 'path';

const DEFAULT_LOCK = path.resolve('data', 'sync.lock');
const STALE_MS = 4 * 60 * 60 * 1000;

export function acquireSyncLock(lockPath = DEFAULT_LOCK) {
  const dir = path.dirname(lockPath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  if (fs.existsSync(lockPath)) {
    try {
      const data = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
      const age = Date.now() - (data.startedAt ?? 0);
      if (age < STALE_MS) {
        return { acquired: false, reason: 'sync_in_progress', holder: data };
      }
      console.warn(`[sync-lock] Removing stale lock (${Math.round(age / 60000)}m old)`);
      fs.unlinkSync(lockPath);
    } catch {
      fs.unlinkSync(lockPath);
    }
  }

  fs.writeFileSync(
    lockPath,
    JSON.stringify({ pid: process.pid, startedAt: Date.now(), label: 'sync' }),
  );
  return { acquired: true };
}

export function releaseSyncLock(lockPath = DEFAULT_LOCK) {
  try {
    if (fs.existsSync(lockPath)) fs.unlinkSync(lockPath);
  } catch {
    // ignore
  }
}

export function isLockHeld(lockPath = DEFAULT_LOCK) {
  if (!fs.existsSync(lockPath)) return false;
  try {
    const data = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
    return Date.now() - (data.startedAt ?? 0) < STALE_MS;
  } catch {
    return false;
  }
}
