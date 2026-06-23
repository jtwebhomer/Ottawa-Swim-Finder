import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import { getDb, isDatabaseEmpty } from './db.js';
import { createRouter } from './routes.js';
import { syncRegistryToDatabase, runWeeklyFullSync, runRepairSync } from './syncService.js';
import { createApiKeyMiddleware } from './auth.js';
import { createDashboardRouter } from './dashboardRouter.js';
import { runSyncJob } from './syncRunner.js';
import { startPipelineScheduler } from './scheduler.js';
import { handleCacheImportRequest } from './cacheImportHandler.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const HOST = process.env.HOST || '0.0.0.0';
const PORT = parseInt(process.env.PORT || '3000', 10);
const API_KEY = process.env.API_KEY;
const BODY_LIMIT = process.env.BODY_LIMIT || '50mb';
const DB_PATH = path.resolve(
  process.env.DATABASE_PATH || path.join(__dirname, '../data/ottawa_swim.db'),
);
const USE_WINDOWS_TASK = process.env.USE_WINDOWS_TASK_SCHEDULER !== 'false';
const ENABLE_IN_PROCESS_SCHEDULER = process.env.ENABLE_IN_PROCESS_SCHEDULER === 'true';

const db = getDb(DB_PATH);
const app = express();
const syncOptions = {};

app.use(
  cors({
    origin: true,
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'x-api-key'],
  }),
);

app.use('/dashboard', createDashboardRouter(db));

function cacheImportBodyParser(req, res, next) {
  const contentType = req.headers['content-type'] || '';
  if (contentType.includes('application/json')) {
    return express.json({ limit: BODY_LIMIT })(req, res, next);
  }
  return express.text({
    type: ['text/html', 'text/plain', 'application/octet-stream'],
    limit: BODY_LIMIT,
  })(req, res, next);
}

// Cache import — raw HTML (extension) or JSON
app.post(
  '/cache/import',
  createApiKeyMiddleware(API_KEY),
  cacheImportBodyParser,
  (req, res) => handleCacheImportRequest(db, req, res),
);

app.use(express.json({ limit: BODY_LIMIT }));

app.use((err, req, res, next) => {
  if (err?.type === 'entity.too.large') {
    return res.status(413).json({
      error: 'Upload too large — extension should send schedule tables only, not full page',
      limit: BODY_LIMIT,
    });
  }
  next(err);
});

app.use(createApiKeyMiddleware(API_KEY));
app.use(
  createRouter(db, {
    runFullSync: runWeeklyFullSync,
    runRepairSync,
    syncOptions,
  }),
);

async function bootstrap() {
  syncRegistryToDatabase(db);

  app.listen(PORT, HOST, () => {
    console.log(`Ottawa Swim Finder API listening on http://${HOST}:${PORT}`);
    console.log('All requests require header: x-api-key');
    console.log(`Sync Dashboard: http://127.0.0.1:${PORT}/dashboard`);
    console.log('Cache import: POST /cache/import (Chrome extension)');
    if (USE_WINDOWS_TASK) {
      console.log(
        '[scheduler] Windows Task Scheduler: weekly sync + 30-min repair (scripts/install-sync-scheduled-task.ps1)',
      );
    }
    if (ENABLE_IN_PROCESS_SCHEDULER) {
      startPipelineScheduler(db, syncOptions);
    }
  });

  if (isDatabaseEmpty(db)) {
    console.log('[startup] Database empty — starting initial weekly sync');
    setTimeout(
      () => runSyncJob(runWeeklyFullSync, db, syncOptions, 'first-run'),
      3000,
    );
  }
}

bootstrap().catch((e) => {
  console.error(e);
  process.exit(1);
});
