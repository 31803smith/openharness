// Shared scroll positions use one unit per 24 desktop-terminal pixels.
export const TERMINAL_LINE_PIXELS = 24;
const DRAG_THRESHOLD = 8;
const SWIPE_THRESHOLD = 28;

export type DeviceGesture = {
  pointerId: number;
  startX: number;
  startY: number;
  lastY: number;
  axis: 'horizontal' | 'vertical' | null;
};

export function beginGesture(
  pointerId: number,
  x: number,
  y: number,
): DeviceGesture {
  return { pointerId, startX: x, startY: y, lastY: y, axis: null };
}

export function moveGesture(gesture: DeviceGesture, x: number, y: number) {
  const dx = x - gesture.startX;
  const dy = y - gesture.startY;
  const axis =
    gesture.axis ||
    (Math.max(Math.abs(dx), Math.abs(dy)) >= DRAG_THRESHOLD
      ? Math.abs(dy) >= Math.abs(dx)
        ? 'vertical'
        : 'horizontal'
      : null);

  return {
    gesture: { ...gesture, axis, lastY: axis ? y : gesture.lastY },
    // Drag content up to read further down, continuously during the gesture.
    scrollDelta:
      axis === 'vertical' ? (gesture.lastY - y) / TERMINAL_LINE_PIXELS : 0,
  };
}

export function finishGesture(gesture: DeviceGesture, x: number, y: number) {
  const result = moveGesture(gesture, x, y);
  const dx = x - gesture.startX;
  return {
    ...result,
    step:
      result.gesture.axis === 'horizontal' && Math.abs(dx) > SWIPE_THRESHOLD
        ? dx < 0
          ? 1
          : -1
        : 0,
  };
}

export function wheelScrollDelta(
  deltaY: number,
  deltaMode: number,
  pagePixels: number,
) {
  // Wheel events can be expressed as pixels (0), lines (1), or pages (2).
  const pixels =
    deltaY *
    (deltaMode === 1 ? TERMINAL_LINE_PIXELS : deltaMode === 2 ? pagePixels : 1);
  return Number.isFinite(pixels) ? pixels / TERMINAL_LINE_PIXELS : 0;
}

export type HorizontalWheelGesture = {
  total: number;
  lastEventAt: number;
  triggered: boolean;
};

export function horizontalWheelStep(
  previous: HorizontalWheelGesture | null,
  pixels: number,
  now: number,
) {
  const gesture =
    previous && now - previous.lastEventAt < 180
      ? previous
      : { total: 0, lastEventAt: now, triggered: false };
  const total = gesture.total + (Number.isFinite(pixels) ? pixels : 0);
  const step =
    !gesture.triggered && Math.abs(total) >= 48 ? Math.sign(total) : 0;
  return {
    gesture: {
      total,
      lastEventAt: now,
      triggered: gesture.triggered || step !== 0,
    },
    step,
  };
}
