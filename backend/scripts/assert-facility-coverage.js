#!/usr/bin/env node
/**
 * CI/build gate — fails when facility registry coverage is below Ottawa minimums.
 */
import { assertFacilityCoverage, loadFacilityRegistry } from '../src/facilityRegistry.js';

try {
  const registry = loadFacilityRegistry();
  const result = assertFacilityCoverage(registry);
  console.log('[coverage] OK', result);
} catch (e) {
  console.error(e.message);
  process.exit(1);
}
