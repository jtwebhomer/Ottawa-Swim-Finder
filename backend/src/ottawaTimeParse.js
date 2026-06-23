const MONTH_NAMES = {
  january: 1, february: 2, march: 3, april: 4, may: 5, june: 6,
  july: 7, august: 8, september: 9, october: 10, november: 11, december: 12,
  jan: 1, feb: 2, mar: 3, apr: 4, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
};

const TIME_RANGE =
  /((?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?)|noon|midnight)\s*(?:[-–]|to)\s*((?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?)|noon|midnight)/gi;

export function extractTimeRanges(cellText) {
  const trimmed = (cellText || '').trim();
  if (!trimmed || /^n\/a$|^-$|^na$/i.test(trimmed)) return [];

  const results = [];
  for (const m of trimmed.matchAll(TIME_RANGE)) {
    const range = parseRange(m[1], m[2]);
    if (range) results.push(range);
  }
  return results;
}

function parseRange(startRaw, endRaw) {
  const endM = parseSingle(endRaw, null, null);
  if (endM == null) return null;
  const startM = parseSingle(startRaw, endRaw, endM);
  if (startM == null || startM >= endM) return null;
  return [formatMinutes(startM), formatMinutes(endM)];
}

function parseSingle(raw, reference, endMinutes) {
  let t = raw.trim().toLowerCase().replace(/\./g, '');
  if (t === 'noon') t = '12 pm';
  if (t === 'midnight') t = '12 am';

  const m = t.match(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/);
  if (!m) return null;

  let h = parseInt(m[1], 10);
  const min = parseInt(m[2] ?? '0', 10);
  let ap = m[3];

  if (!ap && reference) {
    ap = inferPeriodForStart(h, reference, endMinutes);
  }
  if (!ap && h >= 13) return h * 60 + min;
  if (!ap) return null;

  let hour24 = h % 12;
  if (ap === 'pm') hour24 += 12;
  if (ap === 'am' && h === 12) hour24 = 0;
  return hour24 * 60 + min;
}

function inferPeriodForStart(hour12, reference, endMinutes) {
  const ref = reference.trim().toLowerCase().replace(/\./g, '');
  const rm = ref.match(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/);
  if (!rm || !rm[3]) return null;
  let rh = parseInt(rm[1], 10) % 12;
  if (rm[3] === 'pm') rh += 12;
  if (rm[3] === 'am' && parseInt(rm[1], 10) === 12) rh = 0;
  const resolvedEnd = endMinutes ?? rh * 60 + parseInt(rm[2] ?? '0', 10);
  if (rm[3] === 'pm' && hour12 > parseInt(rm[1], 10)) {
    const amStart = (hour12 === 12 ? 0 : hour12) * 60;
    if (amStart < resolvedEnd) return 'am';
  }
  return rm[3];
}

function formatMinutes(total) {
  const h = Math.floor(total / 60);
  const m = total % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

export function formatDate(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

export function todayDateOnly() {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

export function parseMonthDay(text) {
  const m = text.trim().match(/([A-Za-z]+)\s+(\d{1,2})/);
  if (!m) return null;
  const key = m[1].toLowerCase();
  const month = MONTH_NAMES[key] ?? MONTH_NAMES[key.slice(0, 3)];
  if (!month) return null;
  return new Date(new Date().getFullYear(), month - 1, parseInt(m[2], 10));
}

export function parseDateRangeFromTitle(title) {
  const m = title.match(/([A-Za-z]+\s+\d{1,2})\s+to\s+([A-Za-z]+\s+\d{1,2})/i);
  if (!m) return [null, null];
  let start = parseMonthDay(m[1]);
  let end = parseMonthDay(m[2]);
  if (!start || !end) return [null, null];

  if (end < start) end = new Date(end.getFullYear() + 1, end.getMonth(), end.getDate());

  const today = todayDateOnly();
  if (today < start && end.getFullYear() === start.getFullYear() + 1) {
    start = new Date(start.getFullYear() - 1, start.getMonth(), start.getDate());
    end = new Date(end.getFullYear() - 1, end.getMonth(), end.getDate());
  }
  while (end < today) {
    start = new Date(start.getFullYear() + 1, start.getMonth(), start.getDate());
    end = new Date(end.getFullYear() + 1, end.getMonth(), end.getDate());
  }
  return [formatDate(start), formatDate(end)];
}

export function tryParseDateHeader(header) {
  const m = header.trim().match(/\b([A-Za-z]+)\s+(\d{1,2})\b/);
  if (!m) return null;
  const key = m[1].toLowerCase();
  const month = MONTH_NAMES[key] ?? MONTH_NAMES[key.slice(0, 3)];
  if (!month) return null;
  const day = parseInt(m[2], 10);
  let year = new Date().getFullYear();
  let candidate = new Date(year, month - 1, day);
  const today = todayDateOnly();
  if (candidate < new Date(today.getTime() - 45 * 86400000)) {
    year += 1;
    candidate = new Date(year, month - 1, day);
  }
  return formatDate(candidate);
}

const DAY_NAMES = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

export function columnDayIndex(header) {
  const lower = header.toLowerCase().trim();
  if (/\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\b/.test(lower)) return null;
  for (let i = 0; i < DAY_NAMES.length; i++) {
    const day = DAY_NAMES[i];
    const short = day.slice(0, 3);
    if (lower === day || lower === short || lower.startsWith(`${day} `) || lower.startsWith(`${short} `)) {
      return i + 1;
    }
  }
  return null;
}

export function expandRecurring(entries) {
  const expanded = [];
  const today = todayDateOnly();
  const horizon = new Date(today.getTime() + 90 * 86400000);

  for (const entry of entries) {
    if (entry.schedule_type === 'special' && entry.date) {
      expanded.push(entry);
      continue;
    }
    if (!entry.day_of_week) continue;

    let tableStart = entry.date_range_start ? new Date(entry.date_range_start) : today;
    let tableEnd = entry.date_range_end ? new Date(entry.date_range_end) : horizon;
    const effectiveStart = tableStart > today ? tableStart : today;
    let effectiveEnd = tableEnd > horizon ? horizon : tableEnd;
    if (effectiveEnd < effectiveStart) continue;

    for (let d = new Date(effectiveStart); d <= effectiveEnd; d.setDate(d.getDate() + 1)) {
      if (d.getDay() === entry.day_of_week % 7) {
        expanded.push({
          ...entry,
          schedule_type: 'expanded',
          date: formatDate(d),
        });
      }
    }
  }
  return expanded;
}

// JS getDay(): 0=Sun; our day_of_week: 1=Mon..7=Sun
function fixDayMatch(d, dayOfWeek) {
  const js = d.getDay();
  const ours = js === 0 ? 7 : js;
  return ours === dayOfWeek;
}

// Fix expandRecurring day matching
export function expandRecurringFixed(entries) {
  const expanded = [];
  const today = todayDateOnly();
  const horizon = new Date(today.getTime() + 90 * 86400000);

  for (const entry of entries) {
    if (entry.schedule_type === 'special' && entry.date) {
      expanded.push(entry);
      continue;
    }
    if (!entry.day_of_week) continue;

    let tableStart = entry.date_range_start ? new Date(entry.date_range_start + 'T12:00:00') : today;
    let tableEnd = entry.date_range_end ? new Date(entry.date_range_end + 'T12:00:00') : horizon;
    const effectiveStart = tableStart > today ? tableStart : today;
    let effectiveEnd = tableEnd > horizon ? horizon : tableEnd;
    if (effectiveEnd < effectiveStart) continue;

    for (let d = new Date(effectiveStart); d <= effectiveEnd; d.setDate(d.getDate() + 1)) {
      if (fixDayMatch(d, entry.day_of_week)) {
        expanded.push({ ...entry, schedule_type: 'expanded', date: formatDate(d) });
      }
    }
  }
  return expanded;
}
