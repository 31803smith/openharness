import assert from 'node:assert/strict';
import test from 'node:test';
import {
  demoReducer,
  getAgentStatus,
  AGENTS,
  type DemoAction,
} from '../lib/demo-state.ts';
import { initialFeatureState, type Feature } from '../lib/feature-demos.ts';

function run(feature: Feature, ...actions: DemoAction[]) {
  return actions.reduce(demoReducer, initialFeatureState(feature));
}

await test('each feature opens with only its own scenario and owns independent state', () => {
  const focus = initialFeatureState('focus');
  const voice = initialFeatureState('voice');
  const attention = initialFeatureState('attention');
  const updates = initialFeatureState('updates');

  for (const quiet of [focus, voice]) {
    assert.equal(quiet.answered, true);
    assert.equal(quiet.completionNotice, null);
    assert.equal(quiet.voice, 'idle');
  }
  assert.equal(attention.answered, false);
  assert.equal(attention.focused, 'notes');
  assert.equal(attention.scroll.notes, 6);
  assert.equal(attention.completionNotice, null);
  assert.equal(updates.answered, true);
  assert.equal(updates.focused, 'storefront');
  assert.equal(updates.completionNotice, 'api');
  assert.notEqual(focus.scroll, voice.scroll);
  assert.notEqual(focus.focusMemory, updates.focusMemory);

  const changed = demoReducer(focus, { type: 'step', direction: 1 });
  assert.equal(changed.focused, 'api');
  assert.equal(voice.focused, 'storefront');
  assert.equal(updates.focused, 'storefront');
  assert.deepEqual(initialFeatureState('focus'), focus);
});

await test('a completed update waits without changing focus, reading position, or an active voice capture', () => {
  const before = run(
    'voice',
    { type: 'scroll-position', agent: 'storefront', position: 7.125 },
    { type: 'voice-start' },
  );
  const notified = demoReducer(before, {
    type: 'completion-notify',
    agent: 'api',
  });
  assert.equal(notified.focused, before.focused);
  assert.equal(notified.swarm, before.swarm);
  assert.equal(notified.scroll, before.scroll);
  assert.equal(notified.voice, 'listening');
  assert.equal(notified.voiceTarget, 'storefront');
  assert.equal(notified.view, 'voice');
  assert.equal(notified.returnTo, null);
  assert.equal(notified.completionNotice, 'api');
  assert.equal(demoReducer(notified, { type: 'inspect-completion' }), notified);

  const closed = demoReducer(notified, { type: 'voice-close' });
  assert.equal(
    demoReducer(closed, { type: 'inspect-completion' }).focused,
    'api',
  );
});

await test('reading an update goes directly to its summary and returns to the exact saved position', () => {
  const before = run(
    'updates',
    { type: 'swarm', swarm: 'infra' },
    { type: 'focus', agent: 'observability' },
    { type: 'scroll-position', agent: 'observability', position: 8.375 },
  );
  const read = demoReducer(before, { type: 'inspect-completion' });
  assert.equal(read.swarm, 'workshop');
  assert.equal(read.focused, 'api');
  assert.equal(read.view, 'focus');
  assert.equal(read.completionNotice, null);
  assert.equal(getAgentStatus(read, AGENTS.api), 'ready');
  assert.match(
    read.announcement,
    /Three endpoints built\. All tests passing\./,
  );
  assert.deepEqual(read.returnTo, { swarm: 'infra', focused: 'observability' });
  assert.equal(demoReducer(read, { type: 'answer' }), read);

  const returned = demoReducer(read, { type: 'return' });
  assert.equal(returned.focused, 'observability');
  assert.equal(returned.swarm, 'infra');
  assert.equal(returned.scroll.observability, 8.375);
  assert.equal(returned.returnTo, null);
});

await test('updates ignore unfinished work and new work clears an obsolete completion notice', () => {
  const state = initialFeatureState('focus');
  assert.equal(
    demoReducer(state, { type: 'completion-notify', agent: 'missing' }),
    state,
  );
  assert.equal(
    demoReducer(state, { type: 'completion-notify', agent: 'storefront' }),
    state,
  );

  const restarted = run(
    'updates',
    { type: 'focus', agent: 'api' },
    { type: 'voice-start' },
    { type: 'voice-transcribe' },
    { type: 'voice-send' },
    { type: 'voice-close' },
  );
  assert.equal(restarted.completionNotice, null);
  assert.equal(getAgentStatus(restarted, AGENTS.api), 'working');
  assert.equal(
    demoReducer(restarted, { type: 'completion-notify', agent: 'api' }),
    restarted,
  );
  assert.equal(
    demoReducer(restarted, { type: 'inspect-completion' }),
    restarted,
  );
});

await test('a request can be deferred, answered, and replayed without consuming a separate update', () => {
  const updates = initialFeatureState('updates');
  const deferred = run(
    'attention',
    { type: 'inspect-question' },
    { type: 'return' },
  );
  assert.equal(deferred.focused, 'notes');
  assert.equal(deferred.scroll.notes, 6);
  assert.equal(deferred.answered, false);

  const answered = [
    { type: 'inspect-question' },
    { type: 'answer' },
    { type: 'return' },
  ].reduce(
    (state, action) => demoReducer(state, action as DemoAction),
    deferred,
  );
  assert.equal(answered.focused, 'notes');
  assert.equal(answered.scroll.notes, 6);
  assert.equal(answered.answered, true);
  assert.equal(updates.completionNotice, 'api');
  assert.equal(initialFeatureState('attention').answered, false);
});
