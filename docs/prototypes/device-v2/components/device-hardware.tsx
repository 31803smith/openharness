'use client';

/* eslint-disable jsx-a11y/no-noninteractive-element-interactions, jsx-a11y/no-noninteractive-tabindex -- This composite device simulator owns arrow-key and pointer gestures. Every gesture also has a named button equivalent. */

import { useEffect, useRef, type CSSProperties, type Dispatch } from 'react';
import Image from 'next/image';
import {
  ArrowLeft,
  Check,
  ChevronLeft,
  ChevronRight,
  CornerUpLeft,
  Hand,
  Square,
} from 'lucide-react';
import {
  AGENTS,
  SWARMS,
  getAgentStatus,
  type Agent,
  type DemoAction,
  type DemoState,
} from '@/lib/demo-state';
import {
  beginGesture,
  moveGesture,
  finishGesture,
  wheelScrollDelta,
  horizontalWheelStep,
  TERMINAL_LINE_PIXELS,
  type DeviceGesture,
  type HorizontalWheelGesture,
} from '@/lib/device-gestures';

export function EngineMark({ agent }: { agent: Agent }) {
  return (
    <span
      className={`engine-mark engine-${agent.engine.toLowerCase()}`}
      style={{ '--engine-color': agent.color } as CSSProperties}
      aria-hidden="true"
    >
      {agent.engine === 'Claude' ? (
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2.35"
          strokeLinecap="round"
        >
          <path d="M2.64 12h18.72M12 2.64v18.72M5.38 5.38l13.24 13.24M5.38 18.62L18.62 5.38" />
        </svg>
      ) : (
        <Image
          src={`/images/engines/${agent.engine.toLowerCase()}.png`}
          width="24"
          height="24"
          alt=""
          unoptimized
        />
      )}
    </span>
  );
}

export function DeviceHardware({
  state,
  dispatch,
  onVoice,
  onStopVoice,
  className = '',
}: {
  state: DemoState;
  dispatch: Dispatch<DemoAction>;
  onVoice: () => void;
  onStopVoice: () => void;
  className?: string;
}) {
  const display = useRef<HTMLDivElement>(null);
  const gesture = useRef<DeviceGesture | null>(null);
  const wheelGesture = useRef<HorizontalWheelGesture | null>(null);
  const suppressClick = useRef(false);
  const group = SWARMS.find((item) => item.id === state.swarm)!;
  const agent = AGENTS[state.focused];
  const status = getAgentStatus(state, agent);
  const completion =
    status === 'ready' && agent.status === 'ready' ? agent.completion : null;
  const target = AGENTS[state.voiceTarget || state.focused];

  useEffect(() => {
    const screen = display.current;
    if (!screen || state.view !== 'focus') return;
    wheelGesture.current = null;
    const onWheel = (event: WheelEvent) => {
      // Keep pinch-to-zoom native. Horizontal trackpad gestures switch agents once.
      if (event.ctrlKey || (!event.deltaY && !event.deltaX)) return;
      event.preventDefault();
      event.stopPropagation();
      if (Math.abs(event.deltaX) > Math.abs(event.deltaY)) {
        const result = horizontalWheelStep(
          wheelGesture.current,
          wheelScrollDelta(event.deltaX, event.deltaMode, screen.clientWidth) *
            TERMINAL_LINE_PIXELS,
          event.timeStamp,
        );
        wheelGesture.current = result.gesture;
        if (result.step) dispatch({ type: 'step', direction: result.step });
        return;
      }
      dispatch({
        type: 'scroll',
        delta: wheelScrollDelta(
          event.deltaY,
          event.deltaMode,
          screen.clientHeight,
        ),
      });
    };
    // React delegates wheel events passively; this listener must cancel page scrolling.
    screen.addEventListener('wheel', onWheel, { passive: false });
    return () => screen.removeEventListener('wheel', onWheel);
  }, [state.view, dispatch]);

  return (
    <div className={`device-hardware ${className}`}>
      <Image
        className="hardware-image"
        src="/images/harness-front.png"
        width="1254"
        height="1254"
        alt="The black circular Harness device in its sculpted desktop cradle"
        draggable={false}
        priority={className.includes('hero')}
        unoptimized
      />
      <div
        ref={display}
        className="device-display"
        tabIndex={0}
        role="application"
        aria-roledescription="device simulator"
        aria-label="Interactive Harness screen. Swipe or scroll left and right to switch agents. Drag or scroll up and down to read the focused terminal. Double tap or press V for voice."
        onPointerDown={(event) => {
          if (!event.isPrimary || event.button !== 0) return;
          suppressClick.current = false;
          if (state.view !== 'focus') return;
          gesture.current = beginGesture(
            event.pointerId,
            event.clientX,
            event.clientY,
          );
        }}
        onPointerMove={(event) => {
          const current = gesture.current;
          if (
            !current ||
            current.pointerId !== event.pointerId ||
            state.view !== 'focus'
          )
            return;
          const result = moveGesture(current, event.clientX, event.clientY);
          gesture.current = result.gesture;
          if (!result.gesture.axis) return;
          suppressClick.current = true;
          event.preventDefault();
          if (!event.currentTarget.hasPointerCapture(event.pointerId))
            event.currentTarget.setPointerCapture(event.pointerId);
          if (result.gesture.axis === 'vertical') {
            if (result.scrollDelta)
              dispatch({ type: 'scroll', delta: result.scrollDelta });
          }
        }}
        onPointerCancel={() => {
          gesture.current = null;
        }}
        onLostPointerCapture={(event) => {
          // A touched child may lose its implicit capture when the screen takes over.
          if (event.target === event.currentTarget) gesture.current = null;
        }}
        onPointerUp={(event) => {
          const start = gesture.current;
          gesture.current = null;
          if (
            !start ||
            start.pointerId !== event.pointerId ||
            state.view !== 'focus'
          )
            return;
          const result = finishGesture(start, event.clientX, event.clientY);
          if (result.gesture.axis) suppressClick.current = true;
          if (result.scrollDelta) {
            dispatch({ type: 'scroll', delta: result.scrollDelta });
          }
          if (result.step) dispatch({ type: 'step', direction: result.step });
          if (event.currentTarget.hasPointerCapture(event.pointerId))
            event.currentTarget.releasePointerCapture(event.pointerId);
        }}
        onClickCapture={(event) => {
          // A swipe that began over a control must not also tap that control.
          if (suppressClick.current && event.detail !== 0) {
            event.preventDefault();
            event.stopPropagation();
          }
        }}
        onDoubleClick={(event) => {
          if (
            !suppressClick.current &&
            !(event.target as HTMLElement).closest('button') &&
            state.view === 'focus'
          )
            onVoice();
        }}
        onKeyDown={(event) => {
          if (event.target !== event.currentTarget) return;
          if (event.key === 'ArrowRight' || event.key === 'ArrowLeft') {
            event.preventDefault();
            dispatch({
              type: 'step',
              direction: event.key === 'ArrowRight' ? 1 : -1,
            });
          }
          if (
            state.view === 'focus' &&
            (event.key === 'ArrowUp' || event.key === 'ArrowDown')
          ) {
            event.preventDefault();
            dispatch({
              type: 'scroll',
              delta: event.key === 'ArrowDown' ? 3 : -3,
            });
          }
          if (event.key.toLowerCase() === 'v') onVoice();
          if (event.key === 'Escape') {
            dispatch({ type: 'voice-close' });
            dispatch({ type: 'view', view: 'focus' });
          }
        }}
      >
        {state.view === 'focus' && (
          <div className="device-face face-focus" key={`focus-${agent.id}`}>
            <button
              className="face-context"
              aria-label={`${group.name}. Switch Swarms`}
              onClick={() => dispatch({ type: 'view', view: 'swarms' })}
            >
              {group.name}
            </button>
            <div className="face-agent">
              <div className="face-identity">
                <span className="sr-only">{agent.engine}</span>
                <EngineMark agent={agent} />
                <h3>{agent.name}</h3>
              </div>
              {completion ? (
                <p className="face-completion">
                  <span>
                    <span className="sr-only">Completed: </span>
                    {completion[0]}
                  </span>
                  <span>{completion[1]}</span>
                </p>
              ) : (
                <div className={`face-status status-${status}`}>
                  <i />
                  <span>
                    {status === 'working' ? 'Working' : 'Needs input'}
                  </span>
                </div>
              )}
            </div>
            <button
              className="face-step step-prev"
              aria-label="Previous agent"
              onClick={() => dispatch({ type: 'step', direction: -1 })}
            >
              <ChevronLeft />
            </button>
            <button
              className="face-step step-next"
              aria-label="Next agent"
              onClick={() => dispatch({ type: 'step', direction: 1 })}
            >
              <ChevronRight />
            </button>
            <div className="face-footer">
              {state.returnTo ? (
                <button
                  className="face-attention face-return"
                  aria-label={`Return to ${AGENTS[state.returnTo.focused].name}`}
                  onClick={() => dispatch({ type: 'return' })}
                >
                  <CornerUpLeft />
                  Return
                </button>
              ) : !state.answered ? (
                <button
                  className="face-attention face-needs-input"
                  aria-label="1 agent needs your input to continue. Go to Payments"
                  onClick={() => dispatch({ type: 'inspect-question' })}
                >
                  <Hand />1
                </button>
              ) : state.completionNotice ? (
                <button
                  className="face-attention face-update"
                  aria-label={`${AGENTS[state.completionNotice].name} finished. View summary`}
                  onClick={() => dispatch({ type: 'inspect-completion' })}
                >
                  <Check />1
                </button>
              ) : null}
            </div>
          </div>
        )}
        {state.view === 'swarms' && (
          <div className="device-face face-swarms">
            <button
              className="face-back"
              onClick={() => dispatch({ type: 'view', view: 'focus' })}
            >
              <ArrowLeft />
              Swarms
            </button>
            <div className="swarm-list">
              {SWARMS.map((item) => (
                <button
                  key={item.id}
                  onClick={() => dispatch({ type: 'swarm', swarm: item.id })}
                  className={item.id === state.swarm ? 'selected' : ''}
                >
                  <span>{item.name}</span>
                  {item.id === state.swarm ? <Check /> : <ChevronRight />}
                </button>
              ))}
            </div>
          </div>
        )}
        {state.view === 'question' && (
          <div className="device-face face-question">
            <button
              className="face-back"
              onClick={() => dispatch({ type: 'return' })}
            >
              <ArrowLeft />
              Payments
            </button>
            <h3>
              Use existing
              <br />
              account?
            </h3>
            <button
              className="screen-primary"
              onClick={() => dispatch({ type: 'answer' })}
            >
              Use existing
            </button>
            <button
              className="screen-secondary"
              onClick={() => dispatch({ type: 'return' })}
            >
              Later
            </button>
          </div>
        )}
        {state.view === 'voice' && (
          <div className={`device-face face-voice voice-${state.voice}`}>
            <button
              className="face-context"
              aria-label={
                state.voice === 'sent'
                  ? 'Return from voice'
                  : `Cancel voice to ${target.name}`
              }
              onClick={() => dispatch({ type: 'voice-close' })}
            >
              <ArrowLeft />
              To {target.name}
            </button>
            <h3>
              {state.voice === 'listening'
                ? 'Listening'
                : state.voice === 'transcribing'
                  ? 'Transcribing'
                  : 'Sent'}
            </h3>
            <div className="voice-wave" aria-hidden="true">
              {Array.from({ length: 27 }, (_, index) => (
                <i
                  key={index}
                  style={
                    {
                      '--bar': `${20 + (Math.sin(index * 1.7) + 1) * 30}%`,
                      '--delay': `${index * -0.11}s`,
                    } as CSSProperties
                  }
                />
              ))}
            </div>
            {state.voice === 'listening' ? (
              <button className="voice-stop" onClick={onStopVoice}>
                <Square />
                Send
              </button>
            ) : state.voice === 'sent' ? (
              <button
                className="voice-stop"
                onClick={() => dispatch({ type: 'voice-close' })}
              >
                Done
              </button>
            ) : null}
          </div>
        )}
      </div>
    </div>
  );
}
