'use client';

/* eslint-disable jsx-a11y/no-noninteractive-tabindex -- Scrollable terminal regions need tab focus for native keyboard scrolling. */

import { useEffect, useRef, type Dispatch } from 'react';
import { ArrowDown, ArrowUp, Check, Hand, Maximize2, Usb } from 'lucide-react';
import {
  AGENTS,
  SWARMS,
  getAgentStatus,
  visibleAgentIds,
  type Agent,
  type DemoAction,
  type DemoState,
} from '@/lib/demo-state';
import { EngineMark } from '@/components/device-hardware';
import { TERMINAL_LINE_PIXELS } from '@/lib/device-gestures';

const FILES: Record<string, string[]> = {
  storefront: [
    'app/collection/page.tsx',
    'components/product-card.tsx',
    'styles/collection.css',
  ],
  api: [
    'src/routes/catalog.ts',
    'src/schema/product.ts',
    'tests/catalog.test.ts',
  ],
  tests: ['checkout.spec.ts', 'shipping.spec.ts', 'collection.spec.ts'],
  notes: ['CHANGELOG.md', 'docs/launch.md', 'README.md'],
  payments: [
    'src/payments/stripe.ts',
    'src/payments/checkout.ts',
    '.env.example',
  ],
  launch: ['app/launch/page.tsx', 'components/hero.tsx', 'public/launch.webp'],
  deploy: ['deploy/preview.yml', 'deploy/health-check.ts', 'Dockerfile'],
  observability: [
    'src/tracing.ts',
    'dashboards/overview.json',
    'src/metrics.ts',
  ],
};

function TerminalPane({
  agent,
  state,
  dispatch,
  trackScrollBounds,
}: {
  agent: Agent;
  state: DemoState;
  dispatch: Dispatch<DemoAction>;
  trackScrollBounds: boolean;
}) {
  const focused = state.focused === agent.id;
  const output = useRef<HTMLDivElement>(null);
  const sent = state.sentTo === agent.id;
  const resolved = state.answered && agent.id === 'payments';
  const status = getAgentStatus(state, agent);
  const offset = state.scroll[agent.id] || 0;
  const needsScrollBounds = state.scrollLimits?.[agent.id] === undefined;
  useEffect(() => {
    const element = output.current;
    if (!element || !trackScrollBounds) return;
    const measure = () => {
      if (!element.clientHeight) return;
      dispatch({
        type: 'scroll-limit',
        agent: agent.id,
        limit:
          Math.max(0, element.scrollHeight - element.clientHeight) /
          TERMINAL_LINE_PIXELS,
      });
    };
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    if (element.firstElementChild) observer.observe(element.firstElementChild);
    measure();
    return () => observer.disconnect();
  }, [agent.id, dispatch, trackScrollBounds, needsScrollBounds]);
  useEffect(() => {
    if (
      output.current?.clientHeight &&
      Math.abs(output.current.scrollTop - offset * TERMINAL_LINE_PIXELS) > 1
    )
      output.current.scrollTo({
        top: offset * TERMINAL_LINE_PIXELS,
        behavior: 'instant',
      });
  }, [offset, focused]);
  return (
    <section
      className={`terminal-pane ${focused ? 'pane-focused' : ''}`}
      aria-label={`${agent.name} terminal`}
    >
      <button
        className="pane-title"
        aria-pressed={focused}
        onClick={() => dispatch({ type: 'focus', agent: agent.id })}
      >
        <span>
          <EngineMark agent={agent} />
          {agent.name}
        </span>
        <span className={`pane-state ${status}`}>
          {status === 'waiting' ? (
            <Hand />
          ) : status === 'ready' ? (
            <Check />
          ) : (
            <i />
          )}
          {status === 'working'
            ? 'Working'
            : status === 'ready'
              ? 'Done'
              : 'Needs input'}
        </span>
      </button>
      <section
        className="terminal-output"
        ref={output}
        aria-label={`${agent.name} output`}
        tabIndex={focused ? 0 : -1}
        onScroll={(event) => {
          if (!event.currentTarget.clientHeight) return;
          dispatch({
            type: 'scroll-position',
            agent: agent.id,
            position: event.currentTarget.scrollTop / TERMINAL_LINE_PIXELS,
          });
        }}
      >
        <div className="terminal-content">
          <div className="terminal-greeting">
            <EngineMark agent={agent} />
            <b>{agent.engine}</b>
          </div>
          <p className="terminal-directory">~/work/acme · {agent.branch}</p>
          <p className="terminal-user">
            <span>❯</span>
            {agent.id === 'payments'
              ? 'Connect checkout. Keep it simple.'
              : agent.id === 'notes'
                ? 'Tell the story of this release.'
                : agent.id === 'api'
                  ? 'Make the catalog feel instant.'
                  : 'Make the next release feel considered.'}
          </p>
          <p className="terminal-response">{agent.result}</p>
          <p className="terminal-tool">
            <span>●</span>{' '}
            {agent.status === 'ready' ? 'Updated' : 'Working with'}{' '}
            {FILES[agent.id].length} files
          </p>
          <div className="terminal-files">
            {FILES[agent.id].map((file, index) => (
              <p key={file}>
                <span>{file}</span>
                <b>+{12 + index * 17}</b>
              </p>
            ))}
          </div>
          <p className="terminal-tool">
            <span>●</span> Reviewing the changes
          </p>
          <p className="terminal-response">
            {agent.id === 'notes'
              ? 'Organized the release into new features, improvements, and fixes.'
              : 'The main flow is complete. Checking loading, empty, and error states.'}
          </p>
          <p className="terminal-success">
            <Check />{' '}
            {agent.status === 'working'
              ? 'Typecheck passed.'
              : 'All checks passed.'}
          </p>
          <p className="terminal-response">
            {agent.id === 'notes'
              ? 'Added migration notes and linked the changes to their pull requests.'
              : 'Keyboard navigation and responsive layouts are covered. Reviewing the final changes.'}
          </p>
          <div className="terminal-review">
            <p className="terminal-tool">
              <span>●</span> Review summary
            </p>
            {FILES[agent.id].map((file, index) => (
              <div key={file}>
                <span className="terminal-line-number">0{index + 1}</span>
                <span>
                  <b>{file.split('/').at(-1)}</b>
                  <small>
                    {
                      [
                        'Updated the main flow.',
                        'Covered the edge cases.',
                        'Verified the result.',
                      ][index]
                    }
                  </small>
                </span>
              </div>
            ))}
          </div>
          {resolved && (
            <p className="terminal-user terminal-new-message">
              <span>❯</span>Use the existing account.<small>FROM HARNESS</small>
            </p>
          )}
          {sent && (
            <p className="terminal-user terminal-new-message">
              <span>❯</span>
              {state.voiceText}
              <small>VOICE · FROM HARNESS</small>
            </p>
          )}
          <p className="terminal-final">
            <span>✳</span>{' '}
            {resolved
              ? 'Connecting the existing Stripe account…'
              : sent
                ? 'On it. Working on your request…'
                : status === 'waiting'
                  ? 'Waiting for your decision.'
                  : status === 'working'
                    ? 'Working…'
                    : 'Ready when you are.'}
          </p>
          <span className="terminal-cursor" />
        </div>
      </section>
    </section>
  );
}

export function DesktopPreview({
  state,
  dispatch,
  onExpand,
  trackScrollBounds = true,
  className = '',
}: {
  state: DemoState;
  dispatch: Dispatch<DemoAction>;
  onExpand?: () => void;
  trackScrollBounds?: boolean;
  className?: string;
}) {
  const group = SWARMS.find((item) => item.id === state.swarm)!;
  const visible = visibleAgentIds(state);
  return (
    <div className={`desktop-preview launch-app ${className}`}>
      <div className="desktop-titlebar">
        <div className="traffic-lights" aria-hidden="true">
          <i />
          <i />
          <i />
        </div>
        <span className="desktop-wordmark">harness</span>
        <span className="desktop-window-label">Your workspace</span>
        {onExpand && (
          <button aria-label="Expand desktop demo" onClick={onExpand}>
            <Maximize2 />
          </button>
        )}
      </div>
      <div className="desktop-app-body">
        <div className="desktop-workspace">
          <div className="desktop-swarm-bar">
            <div className="desktop-swarm-tabs" aria-label="Switch Swarm">
              {SWARMS.map((item) => (
                <button
                  key={item.id}
                  className={item.id === state.swarm ? 'is-active' : ''}
                  onClick={() => dispatch({ type: 'swarm', swarm: item.id })}
                  aria-pressed={item.id === state.swarm}
                >
                  {item.name}
                  {item.id === 'launch' && !state.answered && <i />}
                </button>
              ))}
            </div>
            <span className="pane-count">
              {group.agents.indexOf(visible[0]) + 1}–
              {group.agents.indexOf(visible.at(-1)!) + 1} of{' '}
              {group.agents.length}
            </span>
          </div>
          <div className="desktop-panes panes-2">
            {visible.map((id) => (
              <TerminalPane
                key={id}
                agent={AGENTS[id]}
                state={state}
                dispatch={dispatch}
                trackScrollBounds={trackScrollBounds}
              />
            ))}
          </div>
        </div>
      </div>
      <div className="desktop-focus-hint">
        <Usb />
        <span>Controlling</span>
        <b>{AGENTS[state.focused].name}</b>
        <div className="terminal-scroll-controls">
          <button
            aria-label="Scroll focused terminal up"
            onClick={() => dispatch({ type: 'scroll', delta: -3 })}
          >
            <ArrowUp />
          </button>
          <button
            aria-label="Scroll focused terminal down"
            onClick={() => dispatch({ type: 'scroll', delta: 3 })}
          >
            <ArrowDown />
          </button>
        </div>
        <span className="scroll-position">
          line {Math.floor(state.scroll[state.focused] || 0) + 1}
        </span>
      </div>
    </div>
  );
}
