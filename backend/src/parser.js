import * as cheerio from 'cheerio';
import {
  columnDayIndex,
  expandRecurringFixed,
  extractTimeRanges,
  parseDateRangeFromTitle,
  tryParseDateHeader,
} from './ottawaTimeParse.js';

const DAY_NAMES = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

const SWIM_ROW = /swim|aquafit|aqua fit|therapeutic|family/i;

function tableTitle($, table) {
  const cap = $(table).find('caption').first().text().trim();
  if (cap) return cap;
  const prev = $(table).prev();
  return prev.text().trim();
}

function isSwimTable(title) {
  const lower = title.toLowerCase();
  return lower.includes('swim') || lower.includes('aquafit');
}

function isSwimRow(label) {
  if (!label || label.length < 2) return false;
  const lower = label.toLowerCase();
  if (DAY_NAMES.includes(lower)) return false;
  return SWIM_ROW.test(label);
}

function looksLikeScheduleCell(text) {
  const lower = text.toLowerCase();
  return lower !== 'n/a' && lower !== '-' && /\d/.test(text) &&
    (lower.includes('am') || lower.includes('pm') || lower.includes(':'));
}

/**
 * Parse schedule HTML into session rows (expanded to dated entries).
 */
export function parseScheduleHtml(html, facilityId) {
  const $ = cheerio.load(html);
  const rawEntries = [];
  let tablesFound = 0;

  $('table').each((_, table) => {
    const title = tableTitle($, table);
    if (!isSwimTable(title)) return;

    const [dateRangeStart, dateRangeEnd] = parseDateRangeFromTitle(title);
    let scheduleType = dateRangeStart ? 'recurring' : 'special';

    const headerCells = $(table).find('tr').first().find('th');
    const headers = headerCells.map((__, th) => $(th).text().trim()).get();
    if (headers.length < 2) return;

    const dayColumns = {};
    const specialDates = {};
    for (let i = 0; i < headers.length; i++) {
      const parsed = tryParseDateHeader(headers[i]);
      if (parsed) {
        specialDates[i] = parsed;
        scheduleType = 'special';
        continue;
      }
      const dayIdx = columnDayIndex(headers[i]);
      if (dayIdx != null) dayColumns[i] = dayIdx;
    }

    let tableRows = 0;
    $(table).find('tr').each((__, row) => {
      const cells = $(row).find('th, td');
      if (cells.length < 2) return;

      const rawCategory = cells.first().text().trim();
      if (!isSwimRow(rawCategory)) return;

      cells.each((col, cell) => {
        if (col === 0) return;
        const cellText = $(cell).text().trim();
        if (!cellText) return;

        const times = extractTimeRanges(cellText);
        if (times.length === 0) {
          if (looksLikeScheduleCell(cellText)) {
            // unparsed but looks like schedule — counts toward parse failure detection
          }
          return;
        }

        for (const [startTime, endTime] of times) {
          tableRows++;
          rawEntries.push({
            facility_id: facilityId,
            category: normalizeCategory(rawCategory),
            raw_category: rawCategory,
            schedule_type: scheduleType,
            day_of_week: dayColumns[col] ?? null,
            date: specialDates[col] ?? null,
            start_time: startTime,
            end_time: endTime,
            notes: cellText.toLowerCase().includes('play free') ? 'Play Free' : null,
            date_range_start: dateRangeStart,
            date_range_end: dateRangeEnd,
          });
        }
      });
    });

    if (tableRows > 0) tablesFound++;
  });

  const expanded = expandRecurringFixed(rawEntries);
  return { sessions: expanded, tablesFound, rawCount: rawEntries.length };
}

function normalizeCategory(raw) {
  const lower = raw.toLowerCase();
  if (lower.includes('lane')) return 'lane';
  if (lower.includes('leisure') || lower.includes('public')) return 'leisure';
  if (lower.includes('family')) return 'family';
  if (lower.includes('aquafit') || lower.includes('aqua fit')) return 'aquafit';
  if (lower.includes('therapeutic')) return 'therapeutic';
  return 'other';
}

export function countScheduleElementsInHtml(html) {
  const $ = cheerio.load(html);
  let count = 0;
  $('table').each((_, table) => {
    const title = tableTitle($, table);
    if (isSwimTable(title)) count++;
  });
  return count;
}

/** @deprecated use parseScheduleHtml */
export function parseHtml(html, facilityId) {
  return parseScheduleHtml(html, facilityId).sessions;
}
