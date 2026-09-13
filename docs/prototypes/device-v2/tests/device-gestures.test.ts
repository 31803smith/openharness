import assert from 'node:assert/strict';
import test from 'node:test';
import {
  beginGesture,
  moveGesture,
  finishGesture,
  wheelScrollDelta,
  horizontalWheelStep,
} from '../lib/device-gestures.ts';
import { demoReducer, initialState } from '../lib/demo-state.ts';

await test('vertical dragging updates the focused terminal before pointer release', () => {
  const first = moveGesture(beginGesture(1, 100, 200), 102, 176);
  assert.equal(first.scrollDelta, 1);
  const state = demoReducer(initialState(), {
    type: 'scroll',
    delta: first.scrollDelta,
  });
  assert.equal(state.scroll.storefront, 1);
  const next = moveGesture(first.gesture, 103, 152);
  assert.equal(next.scrollDelta, 1);
  assert.equal(
    demoReducer(state, { type: 'scroll', delta: next.scrollDelta }).scroll
      .storefront,
    2,
  );
  // Releasing at the last delivered position must not scroll the same distance twice.
  const end = finishGesture(next.gesture, 103, 152);
  assert.equal(end.scrollDelta, 0);
  assert.equal(end.step, 0);
});

await test('reversing a vertical drag scrolls back without waiting for another gesture', () => {
  const up = moveGesture(beginGesture(1, 100, 200), 100, 152);
  const down = moveGesture(up.gesture, 100, 188);
  assert.equal(up.scrollDelta, 2);
  assert.equal(down.scrollDelta, -1.5);
});

await test('vertical gestures stay vertical when the pointer drifts sideways', () => {
  const start = moveGesture(beginGesture(1, 100, 200), 101, 176);
  const end = finishGesture(start.gesture, 220, 152);
  assert.equal(end.gesture.axis, 'vertical');
  assert.equal(end.scrollDelta, 1);
  assert.equal(end.step, 0);
});

await test('horizontal swipes still change agents once and never scroll the terminal', () => {
  const start = moveGesture(beginGesture(1, 200, 200), 180, 201);
  const end = finishGesture(start.gesture, 140, 230);
  assert.equal(start.scrollDelta, 0);
  assert.equal(end.scrollDelta, 0);
  assert.equal(end.step, 1);
  assert.equal(finishGesture(beginGesture(1, 100, 200), 150, 201).step, -1);
});

await test('small tap movements do not steal button clicks or start scrolling', () => {
  const end = finishGesture(beginGesture(1, 100, 200), 103, 204);
  assert.equal(end.gesture.axis, null);
  assert.equal(end.scrollDelta, 0);
  assert.equal(end.step, 0);
});

await test('pointer release includes a final movement even when no move event was delivered', () => {
  assert.equal(
    finishGesture(beginGesture(1, 100, 200), 100, 152).scrollDelta,
    2,
  );
});

await test('trackpad pixels, mouse-wheel lines, and pages all scroll in both directions', () => {
  assert.equal(wheelScrollDelta(12, 0, 240), 0.5);
  assert.equal(wheelScrollDelta(-12, 0, 240), -0.5);
  assert.equal(wheelScrollDelta(3, 1, 240), 3);
  assert.equal(wheelScrollDelta(-3, 1, 240), -3);
  assert.equal(wheelScrollDelta(1, 2, 240), 10);
  assert.equal(wheelScrollDelta(-1, 2, 240), -10);
});

await test('a horizontal trackpad gesture switches once and ignores its remaining momentum', () => {
  const start = horizontalWheelStep(null, 20, 0);
  assert.equal(start.step, 0);
  const threshold = horizontalWheelStep(start.gesture, 30, 16);
  assert.equal(threshold.step, 1);
  const momentum = horizontalWheelStep(threshold.gesture, 120, 32);
  assert.equal(momentum.step, 0);
  const tail = horizontalWheelStep(momentum.gesture, 60, 70);
  assert.equal(tail.step, 0);
  const nextGesture = horizontalWheelStep(tail.gesture, -60, 300);
  assert.equal(nextGesture.step, -1);
});

await test('horizontal wheel noise does not switch agents or poison the next event', () => {
  const noise = horizontalWheelStep(null, Number.NaN, 0);
  assert.equal(noise.step, 0);
  assert.equal(noise.gesture.total, 0);
  const drift = horizontalWheelStep(noise.gesture, 10, 16);
  assert.equal(drift.step, 0);
  const fresh = horizontalWheelStep(drift.gesture, -48, 250);
  assert.equal(fresh.step, -1);
});
