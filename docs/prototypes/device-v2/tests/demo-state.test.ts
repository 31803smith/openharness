import assert from 'node:assert/strict';
import test from 'node:test';
import {
  demoReducer,
  AGENTS,
  getAgentStatus,
  visibleAgentIds,
  SWARMS,
  initialState,
  type DemoAction,
} from '../lib/demo-state.ts';

function run(...actions: DemoAction[]) {
  return actions.reduce(demoReducer, initialState());
}

await test('the two-pane preview always includes the focused agent in Swarm order', () => {
  for (const swarm of SWARMS) {
    for (const id of swarm.agents) {
      const state = run(
        { type: 'swarm', swarm: swarm.id },
        { type: 'focus', agent: id },
      );
      const visible = visibleAgentIds(state);
      assert.equal(visible.length, 2);
      assert.ok(visible.includes(id));
      const start = swarm.agents.indexOf(visible[0]);
      assert.deepEqual(visible, swarm.agents.slice(start, start + 2));
    }
  }
  assert.deepEqual(visibleAgentIds(initialState()), ['storefront', 'api']);
  assert.deepEqual(visibleAgentIds(run({ type: 'step', direction: -1 })), [
    'tests',
    'notes',
  ]);
});

await test('swiping follows pane order, wraps, and stays inside the active Swarm', () => {
  const previous = run({ type: 'step', direction: -1 });
  assert.equal(previous.focused, 'notes');
  assert.equal(previous.swarm, 'workshop');
  assert.equal(
    demoReducer(previous, { type: 'step', direction: 1 }).focused,
    'storefront',
  );
  const launch = run(
    { type: 'swarm', swarm: 'launch' },
    { type: 'step', direction: 1 },
  );
  assert.equal(launch.focused, 'launch');
  assert.equal(
    demoReducer(launch, { type: 'step', direction: 1 }).focused,
    'payments',
  );
});

await test('each Swarm remembers its focused agent', () => {
  const state = run(
    { type: 'focus', agent: 'tests' },
    { type: 'swarm', swarm: 'infra' },
    { type: 'focus', agent: 'observability' },
    { type: 'swarm', swarm: 'workshop' },
  );
  assert.equal(state.focused, 'tests');
  assert.equal(
    demoReducer(state, { type: 'swarm', swarm: 'infra' }).focused,
    'observability',
  );
  assert.equal(demoReducer(state, { type: 'focus', agent: 'payments' }), state);
});

await test('a voice destination stays locked even when desktop focus and Swarm change', () => {
  const state = run(
    { type: 'voice-start' },
    { type: 'focus', agent: 'tests' },
    { type: 'swarm', swarm: 'infra' },
    { type: 'voice-transcribe' },
    { type: 'voice-send' },
  );
  assert.equal(state.focused, 'deploy');
  assert.equal(state.voiceTarget, 'storefront');
  assert.equal(state.sentTo, 'storefront');
  assert.equal(state.voice, 'sent');
  assert.equal(state.view, 'voice');
});

await test('cancelled voice cannot send from a late timer or skip transcription', () => {
  const listening = run({ type: 'voice-start' });
  assert.equal(
    demoReducer(listening, { type: 'voice-send' }).voice,
    'listening',
  );
  const cancelled = run(
    { type: 'voice-start' },
    { type: 'voice-close' },
    { type: 'voice-transcribe' },
    { type: 'voice-send' },
  );
  assert.equal(cancelled.sentTo, null);
  assert.equal(cancelled.voice, 'idle');
  assert.equal(cancelled.view, 'focus');
});

await test('a notification opens its agent directly on request and cannot interrupt voice capture', () => {
  const state = run({ type: 'focus', agent: 'tests' });
  assert.equal(state.focused, 'tests');
  assert.equal(state.swarm, 'workshop');
  const opened = demoReducer(state, { type: 'inspect-question' });
  assert.equal(opened.focused, 'payments');
  assert.equal(opened.swarm, 'launch');
  assert.equal(opened.view, 'question');
  assert.deepEqual(opened.returnTo, {
    swarm: 'workshop',
    focused: 'tests',
  });
  const voice = demoReducer(state, { type: 'voice-start' });
  assert.equal(demoReducer(voice, { type: 'inspect-question' }), voice);
});

await test('a decision detour restores the exact agent and manually scrolled reading position', () => {
  const state = run(
    { type: 'focus', agent: 'notes' },
    { type: 'scroll-position', agent: 'notes', position: 6.375 },
    { type: 'inspect-question' },
    { type: 'scroll', delta: 3 },
    { type: 'answer' },
    { type: 'return' },
  );
  assert.equal(state.swarm, 'workshop');
  assert.equal(state.focused, 'notes');
  assert.equal(state.scroll.notes, 6.375);
  assert.equal(state.scroll.payments, 3);
  assert.equal(state.returnTo, null);
  assert.equal(state.answered, true);
});

await test('deferring a question returns without answering; a repeated jump preserves the origin', () => {
  const state = run(
    { type: 'focus', agent: 'api' },
    { type: 'inspect-question' },
    { type: 'inspect-question' },
    { type: 'return' },
  );
  assert.equal(state.focused, 'api');
  assert.equal(state.answered, false);
  assert.equal(state.view, 'focus');
});

await test('answering requires the question view and an answered question cannot reopen', () => {
  const untouched = initialState();
  assert.equal(demoReducer(untouched, { type: 'answer' }), untouched);
  const answered = run(
    { type: 'inspect-question' },
    { type: 'answer' },
    { type: 'return' },
  );
  assert.equal(demoReducer(answered, { type: 'inspect-question' }), answered);
});

await test('terminal reading positions are independent and bounded', () => {
  const state = run(
    { type: 'scroll', delta: -3 },
    { type: 'scroll', delta: 6 },
    { type: 'focus', agent: 'api' },
    { type: 'scroll', delta: 200 },
  );
  assert.equal(state.scroll.storefront, 6);
  assert.equal(state.scroll.api, 20);
  assert.equal(
    demoReducer(state, { type: 'scroll', delta: -200 }).scroll.api,
    0,
  );
});

await test('scrolling follows measured output bounds and reverses immediately at either end', () => {
  const longOutput = run(
    { type: 'scroll-limit', agent: 'storefront', limit: 57.5 },
    { type: 'scroll', delta: 200 },
  );
  assert.equal(longOutput.scroll.storefront, 57.5);
  const reversed = demoReducer(longOutput, { type: 'scroll', delta: -2 });
  assert.equal(reversed.scroll.storefront, 55.5);
  const resized = demoReducer(reversed, {
    type: 'scroll-limit',
    agent: 'storefront',
    limit: 30,
  });
  assert.equal(resized.scroll.storefront, 30);
  const top = demoReducer(resized, { type: 'scroll', delta: -200 });
  assert.equal(top.scroll.storefront, 0);
  assert.equal(
    demoReducer(top, { type: 'scroll', delta: 2 }).scroll.storefront,
    2,
  );
  const manual = demoReducer(longOutput, {
    type: 'scroll-position',
    agent: 'storefront',
    position: 42.25,
  });
  assert.equal(manual.scroll.storefront, 42.25);
});

await test('reset clears the entire demo without mutating another instance', () => {
  const independent = initialState();
  const changed = run(
    { type: 'focus', agent: 'api' },
    { type: 'inspect-question' },
    { type: 'answer' },
    { type: 'voice-start' },
  );
  const reset = demoReducer(changed, { type: 'reset' });
  assert.deepEqual(reset, independent);
  assert.notEqual(reset.focusMemory, independent.focusMemory);
  assert.notEqual(reset.scroll, independent.scroll);
});

await test('finished tasks keep their result until new work starts for that agent', () => {
  const browsed = run(
    { type: 'focus', agent: 'api' },
    { type: 'focus', agent: 'notes' },
    { type: 'focus', agent: 'api' },
    { type: 'voice-start' },
    { type: 'voice-close' },
  );
  assert.equal(getAgentStatus(browsed, AGENTS.api), 'ready');

  const restartActions: DemoAction[] = [
    { type: 'voice-start' },
    { type: 'voice-transcribe' },
    { type: 'voice-send' },
    { type: 'voice-close' },
  ];
  const restarted = restartActions.reduce(demoReducer, browsed);
  assert.equal(getAgentStatus(restarted, AGENTS.api), 'working');
  assert.equal(getAgentStatus(restarted, AGENTS.notes), 'ready');

  const nextActions: DemoAction[] = [
    { type: 'focus', agent: 'notes' },
    { type: 'voice-start' },
    { type: 'voice-transcribe' },
    { type: 'voice-send' },
  ];
  const anotherTask = nextActions.reduce(demoReducer, restarted);
  assert.equal(getAgentStatus(anotherTask, AGENTS.api), 'working');
  assert.equal(getAgentStatus(anotherTask, AGENTS.notes), 'working');
});
