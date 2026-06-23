import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { classifyScrapeOutcome, isRepairClassification } from './blockClassifier.js';
import { Classification } from './classification.js';
import { DisplayStatus } from './facilityRegistry.js';

describe('blockClassifier', () => {
  it('classifies parsed sessions as LIVE_OK', () => {
    const r = classifyScrapeOutcome({
      blocked: false,
      parseResult: { sessions: [{ id: 1 }], tablesFound: 1 },
      renderStatus: 'OK',
      html: '<table>swim</table>',
    });
    assert.equal(r.displayStatus, DisplayStatus.LIVE_OK);
    assert.equal(r.blockClass, null);
  });

  it('classifies http 403 as BLOCKED_HARD', () => {
    const r = classifyScrapeOutcome({
      blocked: true,
      parseResult: { sessions: [], tablesFound: 0 },
      renderStatus: 'BLOCKED',
      html: '<html>pardon our interruption</html>',
      httpStatus: 403,
    });
    assert.equal(r.blockClass, Classification.BLOCKED_HARD);
    assert.equal(r.requiresManualUnlock, true);
  });

  it('classifies parse signals without rows as PARSE_FAILED', () => {
    const r = classifyScrapeOutcome({
      blocked: false,
      parseResult: { sessions: [], tablesFound: 2 },
      renderStatus: 'OK',
      html: '<table>lane swim monday</table>',
    });
    assert.equal(r.blockClass, Classification.PARSE_FAILED);
    assert.equal(isRepairClassification(r.blockClass), true);
  });

  it('repair targets exclude BLOCKED_HARD', () => {
    assert.equal(isRepairClassification(Classification.BLOCKED_HARD), false);
    assert.equal(isRepairClassification(Classification.BLOCKED_TEMPORARY), true);
  });
});
