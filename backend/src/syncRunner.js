/** Shared sync job runner — API, CLI, and Windows Scheduled Task. */
import path from 'path';
import { fileURLToPath } from 'url';
import { acquireSyncLock, releaseSyncLock, isLockHeld } from './syncLock.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const LOCK_PATH = path.resolve(__dirname, '../data/sync.lock');

let syncRunning = false;
let lastResult = null;

export function isSyncRunning() {
  return syncRunning || isLockHeld(LOCK_PATH);
}

export function getLastSyncResult() {
  return lastResult;
}

export async function runSyncJob(runFullSync, database, options, label = 'manual') {
  const lock = acquireSyncLock(LOCK_PATH);
  if (!lock.acquired || syncRunning) {
    console.log(`[sync] Skip ${label} — already running`, lock.holder ?? '');
    return { skipped: true, reason: 'sync_already_running', running: true };
  }

  syncRunning = true;
  console.log(`[sync] Start ${label}`);
  try {
    const result = await runFullSync(database, options);
    lastResult = { ...result, label, finishedAt: Date.now() };
    console.log(`[sync] Done ${label}:`, result);
    return lastResult;
  } catch (e) {
    console.error(`[sync] Error ${label}:`, e);
    lastResult = {
      status: 'failure',
      error: e.message,
      label,
      finishedAt: Date.now(),
    };
    return lastResult;
  } finally {
    syncRunning = false;
    releaseSyncLock(LOCK_PATH);
  }
}
