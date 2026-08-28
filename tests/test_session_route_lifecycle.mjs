import assert from 'node:assert/strict';

import {
  createSessionRecord,
  normalizeSessionRecord,
  resumeSessionRecord,
  sessionLaunchConflicts,
} from '../dashboard/session_lifecycle.mjs';

const originTerminal = {
  sessionId: '11111111-1111-4111-8111-111111111111',
  routeId: 'account-codex_plus_1-gpt-5.6-sol',
  routeName: 'Codex Plus 1: Sol',
  model: 'gpt-5.6-sol',
  startedAt: '2026-08-28T10:00:00.000Z',
};

const legacyMutated = {
  id: originTerminal.sessionId,
  name: 'Công việc chính',
  routeId: 'google-1-gemini',
  routeName: 'Google 1: Gemini',
  model: 'gemini-3.7-flash-high',
  createdAt: '2026-08-28T10:00:00.000Z',
  lastOpenedAt: '2026-08-28T11:00:00.000Z',
};

const repaired = normalizeSessionRecord(legacyMutated, originTerminal);
assert.equal(repaired.routeId, originTerminal.routeId);
assert.equal(repaired.model, originTerminal.model);
assert.equal(repaired.lastRouteId, legacyMutated.routeId);
assert.equal(repaired.lastModel, legacyMutated.model);

const resumed = resumeSessionRecord(repaired, {
  id: 'google-2-claude',
  name: 'Google 2: Claude',
  model: 'claude-opus-4-6-thinking',
}, '2026-08-28T12:00:00.000Z');
assert.equal(resumed.routeId, originTerminal.routeId);
assert.equal(resumed.model, originTerminal.model);
assert.equal(resumed.lastRouteId, 'google-2-claude');
assert.equal(resumed.lastModel, 'claude-opus-4-6-thinking');

const created = createSessionRecord({
  id: '22222222-2222-4222-8222-222222222222',
  name: 'Phiên độc lập',
  route: { id: 'google-1-gemini', name: 'Google 1: Gemini', model: 'gemini-3.7-flash-high' },
  now: '2026-08-28T13:00:00.000Z',
});
assert.equal(created.routeId, created.lastRouteId);
assert.equal(created.model, created.lastModel);

const terminals = [
  { sessionId: repaired.id, routeId: repaired.routeId, running: true },
  { sessionId: created.id, routeId: repaired.routeId, running: false },
];
assert.equal(sessionLaunchConflicts(repaired.id, terminals, new Set()), true);
assert.equal(sessionLaunchConflicts(created.id, terminals, new Set()), false);
assert.equal(sessionLaunchConflicts(created.id, terminals, new Set([created.id])), true);

console.log('PASS: session identity remains independent from the most recently selected route');
console.log('PASS: the same route may own multiple session UUIDs while one UUID cannot launch twice concurrently');
