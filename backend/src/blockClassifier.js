/**
 * Block / parse outcome classification for orchestrator + repair sync.
 */
import { Classification, RenderStatus } from './classification.js';
import { DisplayStatus } from './facilityRegistry.js';
import { hasScheduleSignals, isChallengeHtml } from './renderValidation.js';

export function classifyScrapeOutcome({ blocked, parseResult, renderStatus, html, httpStatus = 0 }) {
  const parsed = parseResult?.sessions ?? [];
  const tablesFound = parseResult?.tablesFound ?? 0;

  if (parsed.length > 0) {
    return {
      displayStatus: DisplayStatus.LIVE_OK,
      blockClass: null,
      parsed,
      reason: 'parsed_sessions',
      recoverable: true,
    };
  }

  const challenge = blocked || httpStatus === 403 || isChallengeHtml(html);

  if (challenge) {
    const hard = httpStatus === 403 || isChallengeHtml(html);
    return {
      displayStatus: DisplayStatus.BLOCKED,
      blockClass: hard ? Classification.BLOCKED_HARD : Classification.BLOCKED_TEMPORARY,
      parsed,
      reason: hard ? 'bot_challenge' : 'transient_block',
      recoverable: !hard,
      requiresManualUnlock: hard,
    };
  }

  if (hasScheduleSignals(html) || tablesFound > 0) {
    return {
      displayStatus: DisplayStatus.PARSE_ISSUE,
      blockClass: Classification.PARSE_FAILED,
      parsed,
      reason: 'signals_no_parse',
      recoverable: true,
    };
  }

  if (renderStatus === RenderStatus.INCOMPLETE || renderStatus === RenderStatus.UNSTABLE) {
    return {
      displayStatus: DisplayStatus.PARSE_ISSUE,
      blockClass: Classification.BLOCKED_TEMPORARY,
      parsed,
      reason: 'render_incomplete',
      recoverable: true,
    };
  }

  if (renderStatus === RenderStatus.ERROR) {
    return {
      displayStatus: DisplayStatus.PARSE_ISSUE,
      blockClass: Classification.BLOCKED_TEMPORARY,
      parsed,
      reason: 'render_error',
      recoverable: true,
    };
  }

  return {
    displayStatus: DisplayStatus.PARSE_ISSUE,
    blockClass: Classification.PARSE_FAILED,
    parsed,
    reason: 'empty_swim_schedule',
    recoverable: true,
  };
}

export function isRepairClassification(blockClass) {
  return (
    blockClass === Classification.BLOCKED_TEMPORARY ||
    blockClass === Classification.PARSE_FAILED
  );
}
