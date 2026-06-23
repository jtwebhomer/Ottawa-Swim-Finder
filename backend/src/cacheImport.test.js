import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs';
import path from 'path';
import os from 'os';
import {
  saveCacheImport,
  loadBestCacheForFacility,
  pickBestScheduleSource,
  scoreScheduleCandidate,
} from './cacheImport.js';

describe('cacheImport', () => {
  let tmpDir;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'osf-cache-'));
    process.env.CACHE_IMPORT_DIR = tmpDir;
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    delete process.env.CACHE_IMPORT_DIR;
  });

  it('scores more complete schedules higher', () => {
    const low = scoreScheduleCandidate({ sessionCount: 2, tablesFound: 1, htmlLength: 1000, capturedAt: Date.now() });
    const high = scoreScheduleCandidate({ sessionCount: 20, tablesFound: 3, htmlLength: 5000, capturedAt: Date.now() });
    assert.ok(high > low);
  });

  it('pickBestScheduleSource prefers more sessions then newer', () => {
    const winner = pickBestScheduleSource([
      { sessionCount: 5, tablesFound: 1, capturedAt: 1000 },
      { sessionCount: 12, tablesFound: 2, capturedAt: 500 },
      { sessionCount: 12, tablesFound: 2, capturedAt: 2000 },
    ]);
    assert.equal(winner.capturedAt, 2000);
    assert.equal(winner.sessionCount, 12);
  });

  it('rejects challenge HTML on import', () => {
    const saved = saveCacheImport('brewer-pool-and-arena', '<html>Pardon our interruption</html>', {
      source: 'extension',
    });
    assert.equal(saved.evaluated, null);
    assert.equal(loadBestCacheForFacility('brewer-pool-and-arena'), null);
  });
});
