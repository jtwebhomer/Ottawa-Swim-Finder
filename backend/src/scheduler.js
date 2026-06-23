/**
 * In-process scheduler for weekly full sync + 30-minute repair loop.
 * On Windows, prefer Task Scheduler (scripts/install-sync-scheduled-task.ps1).
 */
import { runWeeklyFullSync, runRepairSync } from './syncService.js';
import { runSyncJob } from './syncRunner.js';

const WEEKLY_MS = 7 * 24 * 60 * 60 * 1000;
const REPAIR_MS = 30 * 60 * 1000;

export function startPipelineScheduler(database, options = {}) {
  const { headless = true } = options;
  let weeklyTimer = null;
  let repairTimer = null;
  let repairRunning = false;

  async function runWeekly() {
    await runSyncJob(runWeeklyFullSync, database, { headless }, 'weekly');
  }

  async function runRepair() {
    if (repairRunning) {
      console.log('[scheduler] Repair skipped — previous repair still running');
      return;
    }
    repairRunning = true;
    try {
      await runSyncJob(runRepairSync, database, { headless }, 'repair');
    } finally {
      repairRunning = false;
    }
  }

  weeklyTimer = setInterval(runWeekly, WEEKLY_MS);
  repairTimer = setInterval(runRepair, REPAIR_MS);

  console.log('[scheduler] Weekly full sync every 7 days');
  console.log('[scheduler] Repair loop every 30 minutes');

  return {
    stop() {
      if (weeklyTimer) clearInterval(weeklyTimer);
      if (repairTimer) clearInterval(repairTimer);
    },
    runWeekly,
    runRepair,
  };
}
