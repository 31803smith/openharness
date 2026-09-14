import assert from 'node:assert/strict';
import test from 'node:test';
import {
  getHeroFrame,
  HERO_LOOP_MS,
  HERO_SESSIONS,
} from '../lib/hero-workspace.ts';

await test('finishing changes both screens together, keeps focus, and stops the finished terminal', () => {
  const working = getHeroFrame(5999);
  const finished = getHeroFrame(6000);
  assert.equal(working.focused.session.agent, 'api');
  assert.equal(working.focused.status, 'working');
  assert.equal(finished.focused.session.agent, 'api');
  assert.equal(finished.focused.status, 'ready');
  assert.equal(finished.focused.session.completion?.length, 2);
  assert.equal(
    finished.focused,
    finished.sessions.find((frame) => frame.session.agent === 'api'),
  );

  const later = getHeroFrame(12000);
  const completed = later.sessions.find(
    (frame) => frame.session.agent === 'api',
  )!;
  assert.equal(later.focused.session.agent, 'storefront');
  assert.equal(completed.status, 'ready');
  assert.equal(completed.seconds, finished.focused.seconds);
  assert.equal(completed.outputTick, finished.focused.outputTick);
});

await test('every focused device state comes from its monitor pane and every finished state has a result', () => {
  const seen = new Set<string>();
  for (let elapsed = 0; elapsed < HERO_LOOP_MS; elapsed += 100) {
    const frame = getHeroFrame(elapsed);
    assert.ok(frame.sessions.includes(frame.focused));
    seen.add(frame.focused.session.agent);
    for (const pane of frame.sessions) {
      if (pane.status === 'ready') {
        assert.equal(pane.session.completion?.length, 2);
        assert.ok(pane.session.completion.every((line) => line.length > 0));
      }
    }
  }
  assert.deepEqual(
    seen,
    new Set(HERO_SESSIONS.map((session) => session.agent)),
  );
});

await test('working panes advance independently and each loop restarts both screens in the approved state', () => {
  const early = getHeroFrame(1800);
  const storefront = early.sessions.find(
    (frame) => frame.session.agent === 'storefront',
  )!;
  const api = early.sessions.find((frame) => frame.session.agent === 'api')!;
  assert.ok(storefront.outputTick > api.outputTick);
  assert.equal(early.focused.session.agent, 'api');
  assert.deepEqual(getHeroFrame(HERO_LOOP_MS), getHeroFrame(0));
  assert.deepEqual(getHeroFrame(HERO_LOOP_MS * 3 + 12000), getHeroFrame(12000));
});
