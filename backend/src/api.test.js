import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { getDb, closeDb } from './db.js';
import { createRouter } from './routes.js';
import { seedFromAssets } from './syncService.js';
import { createApiKeyMiddleware } from './auth.js';

const testDb = ':memory:';
const TEST_API_KEY = 'test-secret-key';

describe('API routes', () => {
  let server;
  let port;

  before(async () => {
    process.env.ALLOW_FIXTURE_SEED = 'true';
    closeDb();
    const db = getDb(testDb);
    await seedFromAssets(db);
    const app = express();
    app.use(createApiKeyMiddleware(TEST_API_KEY));
    app.use(createRouter(db));
    await new Promise((resolve) => {
      server = app.listen(0, resolve);
    });
    port = server.address().port;
  });

  after(async () => {
    if (server) {
      await new Promise((resolve) => server.close(resolve));
    }
    closeDb();
  });

  async function get(pathname, { withKey = true } = {}) {
    const headers = withKey ? { 'x-api-key': TEST_API_KEY } : {};
    const res = await fetch(`http://127.0.0.1:${port}${pathname}`, { headers });
    return { status: res.status, body: await res.json() };
  }

  it('rejects requests without API key', async () => {
    const { status } = await get('/facilities', { withKey: false });
    assert.equal(status, 401);
  });

  it('GET /facilities returns canonical facilities', async () => {
    const { status, body } = await get('/facilities');
    assert.equal(status, 200);
    assert.ok(body.facilities.length >= 57);
    const f = body.facilities[0];
    assert.ok('data_model' in f);
    assert.ok('has_swim_schedule' in f);
    assert.ok('display_status' in f);
    assert.ok('status' in f);
    assert.ok('sessions_count' in f);
    assert.ok('debug' in f);
    assert.ok('can_debug' in f.debug);
    assert.ok('debug_url' in f.debug);
    assert.equal(body.total, body.facilities.length);
  });

  it('GET /schedules requires facility_id', async () => {
    const { status } = await get('/schedules');
    assert.equal(status, 400);
  });

  it('GET /schedules returns seeded fixture rows', async () => {
    const { status, body } = await get('/schedules?facility_id=plant-recreation-centre');
    assert.equal(status, 200);
    assert.ok(body.schedules.length > 0);
    assert.equal(body.schedules[0].source_status, 'fixture');
  });

  it('GET /swims/today returns grouped swims', async () => {
    const { status, body } = await get('/swims/today');
    assert.equal(status, 200);
    assert.ok(body.date);
    assert.ok(Array.isArray(body.facilities));
  });

  it('GET /sync/status returns health metadata', async () => {
    const { status, body } = await get('/sync/status');
    assert.equal(status, 200);
    assert.ok('sync_health' in body);
    assert.ok('total_sessions' in body);
    assert.ok(Array.isArray(body.facilities));
    assert.ok(body.facilities.length >= 57);
    assert.ok('debug' in body.facilities[0]);
    assert.ok('status' in body.facilities[0]);
    assert.ok('display_status' in body.facilities[0]);
    assert.ok('sessions_count' in body.facilities[0]);
    assert.ok('data_model' in body.facilities[0]);
  });
});
