import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { parseScheduleHtml } from './parser.js';
import { validateRenderedPage, isChallengeHtml } from './renderValidation.js';
import { Classification } from './classification.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixturePath = path.resolve(__dirname, '../../app/test/fixtures/plant_recreation_centre.html');

describe('parser', () => {
  it('parses Plant fixture with season tables', () => {
    const html = fs.readFileSync(fixturePath, 'utf8');
    const { sessions, tablesFound } = parseScheduleHtml(html, 'plant-recreation-centre');
    assert.ok(tablesFound >= 2);
    assert.ok(sessions.length > 10);
    assert.ok(sessions.some((s) => s.category === 'lane'));
  });

  it('parses date-column week grid', () => {
    const today = new Date();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const headers = Array.from({ length: 7 }, (_, i) => {
      const d = new Date(today);
      d.setDate(d.getDate() + i);
      return `${days[(d.getDay() + 6) % 7]} ${months[d.getMonth()]} ${d.getDate()}`;
    });
    const html = `<table>
<caption>Test Pool - swim - June 1 to August 31</caption>
<thead><tr><th></th>${headers.map((h) => `<th>${h}</th>`).join('')}</tr></thead>
<tbody><tr><th>Lane swim</th>${headers.map(() => '<td>3 - 5 pm</td>').join('')}</tr></tbody>
</table>`;
    const { sessions } = parseScheduleHtml(html, 'test-pool');
    assert.ok(sessions.length >= 7);
  });
});

describe('renderValidation', () => {
  it('detects challenge pages', () => {
    assert.equal(isChallengeHtml('<html>Pardon Our Interruption</html>'), true);
  });

  it('validates swim schedule pages', () => {
    const html = fs.readFileSync(fixturePath, 'utf8');
    const v = validateRenderedPage(html);
    assert.equal(v.valid, true);
    assert.equal(v.blocked, false);
  });
});

describe('classification', () => {
  it('defines explicit failure states', () => {
    assert.ok(Classification.PARSE_FAILED);
    assert.ok(Classification.CONFIRMED_EMPTY);
    assert.notEqual(Classification.PARSE_FAILED, Classification.CONFIRMED_EMPTY);
  });
});
