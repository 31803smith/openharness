'use client';

import {
  useCallback,
  useEffect,
  useReducer,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import {
  ArrowLeftRight,
  ArrowRight,
  ArrowUpDown,
  Check,
  CornerUpLeft,
  Hand,
  Mic,
  RotateCcw,
  Send,
} from 'lucide-react';
import { DeviceHardware, EngineMark } from '@/components/device-hardware';
import { DesktopPreview } from '@/components/desktop-preview';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  AGENTS,
  demoReducer,
  getAgentStatus,
  type DemoAction,
  type DemoState,
} from '@/lib/demo-state';
import { initialFeatureState, type Feature } from '@/lib/feature-demos';

type FeatureAction = DemoAction | { type: 'reset-feature'; feature: Feature };

function featureReducer(state: DemoState, action: FeatureAction) {
  return action.type === 'reset-feature'
    ? initialFeatureState(action.feature)
    : demoReducer(state, action);
}

function useFeatureDemo(feature: Feature) {
  const [state, dispatch] = useReducer(
    featureReducer,
    feature,
    initialFeatureState,
  );
  const onVoice = useCallback(() => dispatch({ type: 'voice-start' }), []);
  const onStopVoice = useCallback(
    () => dispatch({ type: 'voice-transcribe' }),
    [],
  );
  const reset = useCallback(
    () => dispatch({ type: 'reset-feature', feature }),
    [feature],
  );

  useEffect(() => {
    if (state.voice === 'listening') {
      const timer = window.setTimeout(
        () => dispatch({ type: 'voice-transcribe' }),
        4200,
      );
      return () => window.clearTimeout(timer);
    }
    if (state.voice === 'transcribing') {
      const timer = window.setTimeout(
        () => dispatch({ type: 'voice-send' }),
        1200,
      );
      return () => window.clearTimeout(timer);
    }
  }, [state.voice]);

  return { state, dispatch, onVoice, onStopVoice, reset };
}

type FeatureDemo = ReturnType<typeof useFeatureDemo>;

function FeatureFrame({
  id,
  feature,
  label,
  title,
  description,
  actions,
  demo,
  children,
}: {
  id: string;
  feature: Feature;
  label: string;
  title: ReactNode;
  description: string;
  actions?: ReactNode;
  demo: FeatureDemo;
  children: ReactNode;
}) {
  return (
    <section
      id={id}
      className={`feature-fold feature-${feature}`}
      aria-labelledby={`${id}-title`}
    >
      <div className="feature-inner">
        <div className="feature-heading reveal">
          <div>
            <p className="feature-label">{label}</p>
            <h2 id={`${id}-title`}>{title}</h2>
          </div>
          <div className="feature-introduction">
            <p>{description}</p>
            {actions && <div className="feature-actions">{actions}</div>}
          </div>
        </div>
        {children}
        <div className="feature-bottom">
          <span>The app. The device. In sync.</span>
          <button
            className="feature-reset"
            onClick={demo.reset}
            aria-label={`Reset ${feature === 'attention' ? 'Needs you' : feature} demo`}
          >
            <RotateCcw /> Replay
          </button>
        </div>
        <output className="sr-only" aria-live="polite">
          {demo.state.announcement}
        </output>
      </div>
    </section>
  );
}

function FeatureDevice({
  demo,
  children,
}: {
  demo: FeatureDemo;
  children: ReactNode;
}) {
  return (
    <div className="feature-device">
      <DeviceHardware
        state={demo.state}
        dispatch={demo.dispatch}
        onVoice={demo.onVoice}
        onStopVoice={demo.onStopVoice}
      />
      <div className="feature-device-caption">{children}</div>
    </div>
  );
}

function FocusFeature() {
  const demo = useFeatureDemo('focus');
  const [expanded, setExpanded] = useState(false);
  const stage = useRef<HTMLDivElement>(null);
  const scrollPreview = () => {
    const output = stage.current?.querySelector<HTMLElement>(
      '.pane-focused .terminal-output',
    );
    if (!output) return;
    const nearEnd =
      output.scrollTop >= output.scrollHeight - output.clientHeight - 40;
    output.scrollBy({
      top: nearEnd ? -180 : 180,
      behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches
        ? 'instant'
        : 'smooth',
    });
  };

  return (
    <FeatureFrame
      id="experience"
      feature="focus"
      label="01 / Focus"
      title={
        <>
          Switch agents.
          <br />
          <span>Keep your place.</span>
        </>
      }
      description="Swipe across to change agents. Scroll up or down to read their work. Your workspace follows every move."
      demo={demo}
      actions={
        <>
          <Button
            className="feature-button"
            onClick={() => demo.dispatch({ type: 'step', direction: 1 })}
          >
            <ArrowLeftRight /> Switch agent
          </Button>
          <Button
            className="feature-button feature-button-secondary"
            onClick={scrollPreview}
          >
            <ArrowUpDown /> Try scrolling
          </Button>
        </>
      }
    >
      <div className="feature-stage feature-focus-stage reveal" ref={stage}>
        <DesktopPreview
          state={demo.state}
          dispatch={demo.dispatch}
          trackScrollBounds={!expanded}
          onExpand={() => setExpanded(true)}
        />
        <FeatureDevice demo={demo}>
          <span>
            <ArrowLeftRight /> Switch agents
          </span>
          <span>
            <ArrowUpDown /> Scroll output
          </span>
        </FeatureDevice>
      </div>
      <Dialog open={expanded} onOpenChange={setExpanded}>
        <DialogContent className="desktop-dialog">
          <DialogTitle>Your workspace, up close.</DialogTitle>
          <DialogDescription>
            Switch agents and scroll their output. Each one keeps its place.
          </DialogDescription>
          <DesktopPreview
            state={demo.state}
            dispatch={demo.dispatch}
            className="desktop-expanded"
          />
          <Button className="outline-pill" onClick={() => setExpanded(false)}>
            <CornerUpLeft /> Back to the device
          </Button>
        </DialogContent>
      </Dialog>
    </FeatureFrame>
  );
}

function VoiceFeature() {
  const demo = useFeatureDemo('voice');
  const { state, dispatch } = demo;
  const target = AGENTS[state.voiceTarget || state.focused];
  const sent = state.voice === 'sent';
  const listening = state.voice === 'listening';
  const transcribing = state.voice === 'transcribing';

  return (
    <FeatureFrame
      id="voice"
      feature="voice"
      label="02 / Voice"
      title={
        <>
          Say it.
          <br />
          <span>Keep going.</span>
        </>
      }
      description="A thought becomes a message. Double tap the device, speak, and send it straight to the agent in focus."
      demo={demo}
    >
      <div className="feature-stage feature-story-stage reveal">
        <div
          className={`feature-card voice-message-card ${listening ? 'is-listening' : ''} ${sent ? 'is-sent' : ''}`}
        >
          <div className="feature-card-header">
            <div className="feature-card-agent">
              <EngineMark agent={target} />
              <span>{target.name}</span>
            </div>
            <span
              className={`feature-state ${sent ? 'feature-state-ready' : ''}`}
            >
              <i />
              {listening
                ? 'Listening'
                : transcribing
                  ? 'Transcribing'
                  : sent
                    ? 'Sent'
                    : 'Voice message'}
            </span>
          </div>
          <div className="feature-card-content">
            <div className="message-wave" aria-hidden="true">
              {Array.from({ length: 35 }, (_, index) => (
                <i
                  key={index}
                  style={{
                    height: `${8 + (Math.sin(index * 1.4) + 1) * 16}px`,
                    animationDelay: `${index * -0.09}s`,
                  }}
                />
              ))}
            </div>
            <blockquote>
              “
              {state.voiceText ||
                'Check the layout on mobile before wrapping up.'}
              ”
            </blockquote>
            <p className="feature-card-note">
              {sent
                ? `Delivered to ${target.name}. Already on it.`
                : 'One message. The right agent.'}
            </p>
          </div>
          <div className="feature-card-footer">
            <Button
              className="feature-button"
              disabled={transcribing}
              onClick={
                sent
                  ? () => dispatch({ type: 'voice-close' })
                  : listening
                    ? demo.onStopVoice
                    : demo.onVoice
              }
            >
              {sent ? <CornerUpLeft /> : listening ? <Send /> : <Mic />}
              {sent
                ? 'Back to your agent'
                : listening
                  ? 'Send message'
                  : transcribing
                    ? 'Transcribing…'
                    : 'Try voice'}
            </Button>
            <span>Simulated voice · No mic needed</span>
          </div>
        </div>
        <FeatureDevice demo={demo}>
          <span>
            <Mic /> Double tap to speak
          </span>
        </FeatureDevice>
      </div>
    </FeatureFrame>
  );
}

function AttentionFeature() {
  const demo = useFeatureDemo('attention');
  const { state, dispatch } = demo;
  const asking = state.view === 'question';
  const returned = state.answered && !state.returnTo;
  const origin =
    AGENTS[state.returnTo?.focused || (returned ? state.focused : 'notes')];

  return (
    <FeatureFrame
      id="needs-you"
      feature="attention"
      label="03 / Needs you"
      title={
        <>
          One decision.
          <br />
          <span>Back in motion.</span>
        </>
      }
      description="When an agent needs a hand, it raises one. Tap to answer, then get back to your work."
      demo={demo}
    >
      <div className="feature-stage feature-story-stage reveal">
        <div
          className={`feature-card decision-card ${state.answered ? 'is-resolved' : ''}`}
        >
          <div className="feature-card-header">
            <div className="feature-card-agent">
              <EngineMark agent={AGENTS.payments} />
              <span>Payments</span>
            </div>
            <span
              className={`feature-state ${state.answered ? 'feature-state-ready' : 'feature-state-attention'}`}
            >
              {state.answered ? <i /> : <Hand />}
              {state.answered ? 'Working' : 'Needs you'}
            </span>
          </div>
          <div className="feature-card-content">
            <p className="feature-card-kicker">
              {state.answered ? 'Decision sent' : 'A question from your agent'}
            </p>
            <h3>
              {state.answered ? (
                <>
                  Using your
                  <br />
                  existing account.
                </>
              ) : (
                <>
                  Use the existing
                  <br />
                  Stripe account?
                </>
              )}
            </h3>
            <p className="feature-card-note">
              {returned
                ? `Back to ${origin.name}. Your place is saved.`
                : state.returnTo
                  ? `${origin.name} is right where you left it.`
                  : 'Your other agents keep working.'}
            </p>
          </div>
          <div className="feature-card-footer">
            {state.answered ? (
              <Button
                className="feature-button"
                onClick={
                  returned ? demo.reset : () => dispatch({ type: 'return' })
                }
              >
                {returned ? <RotateCcw /> : <CornerUpLeft />}
                {returned ? 'Try again' : `Back to ${origin.name}`}
              </Button>
            ) : asking ? (
              <>
                <Button
                  className="feature-button"
                  onClick={() => dispatch({ type: 'answer' })}
                >
                  Use existing account <ArrowRight />
                </Button>
                <button
                  className="feature-text-button"
                  onClick={() => dispatch({ type: 'return' })}
                >
                  Later
                </button>
              </>
            ) : (
              <Button
                className="feature-button"
                onClick={() => dispatch({ type: 'inspect-question' })}
              >
                <Hand /> Open request
              </Button>
            )}
            <span>
              {returned
                ? `Reading position restored · Line ${Math.floor(state.scroll[state.focused] || 0) + 1}`
                : 'Your place stays saved'}
            </span>
          </div>
        </div>
        <FeatureDevice demo={demo}>
          <span>
            {state.answered ? <ArrowRight /> : <Hand />}
            {state.answered
              ? 'Answer sent. Work continues.'
              : asking
                ? 'A quick answer. Right here.'
                : 'Tap the hand to answer'}
          </span>
        </FeatureDevice>
      </div>
    </FeatureFrame>
  );
}

function UpdatesFeature() {
  const demo = useFeatureDemo('updates');
  const { state, dispatch } = demo;
  const opened = !state.completionNotice;
  const origin = AGENTS[state.returnTo?.focused || 'storefront'];
  const result = AGENTS.api;
  const finished = getAgentStatus(state, result) === 'ready';

  return (
    <FeatureFrame
      id="updates"
      feature="updates"
      label="04 / Updates"
      title={
        <>
          Know what’s done.
          <br />
          <span>Keep your focus.</span>
        </>
      }
      description="Finished work comes with a short summary. No decision needed. Your current agent stays in focus until you’re ready to look."
      demo={demo}
    >
      <div className="feature-stage feature-story-stage reveal">
        <div
          className={`feature-card completion-card ${opened ? 'is-read' : ''}`}
        >
          <div className="feature-card-header">
            <div className="feature-card-agent">
              <EngineMark agent={result} />
              <span>{result.name}</span>
            </div>
            <span className="feature-state feature-state-ready">
              {finished ? <Check /> : <i />}
              {finished ? 'Finished' : 'Working'}
            </span>
          </div>
          <div className="feature-card-content">
            <p className="feature-card-kicker">
              {finished
                ? opened
                  ? 'The result, at a glance'
                  : 'A quiet update'
                : 'Your next request'}
            </p>
            <h3>
              {finished && result.status === 'ready' ? (
                result.completion.map((line) => <span key={line}>{line}</span>)
              ) : (
                <>
                  New work.
                  <br />
                  Already underway.
                </>
              )}
            </h3>
            <p className="feature-card-note">
              {!finished
                ? 'A new task replaces the previous result.'
                : state.returnTo
                  ? 'Two lines. Everything you need to know.'
                  : `${AGENTS[state.focused].name} stays in focus.`}
            </p>
          </div>
          <div className="feature-card-footer">
            <Button
              className="feature-button"
              onClick={
                state.returnTo
                  ? () => dispatch({ type: 'return' })
                  : opened
                    ? demo.reset
                    : () => dispatch({ type: 'inspect-completion' })
              }
            >
              {state.returnTo ? (
                <CornerUpLeft />
              ) : opened ? (
                <RotateCcw />
              ) : (
                <Check />
              )}
              {state.returnTo
                ? `Back to ${origin.name}`
                : opened
                  ? 'Replay update'
                  : 'Read update'}
            </Button>
            <span>No response needed</span>
          </div>
        </div>
        <FeatureDevice demo={demo}>
          <span>
            {!finished ? (
              <ArrowRight />
            ) : opened && !state.returnTo ? (
              <CornerUpLeft />
            ) : (
              <Check />
            )}
            {!finished
              ? 'Your next request is underway'
              : state.returnTo
                ? 'The summary. On your device.'
                : opened
                  ? 'Back to your work'
                  : 'Tap the update when you’re ready'}
          </span>
        </FeatureDevice>
      </div>
    </FeatureFrame>
  );
}

export function FeatureWalkthrough() {
  return (
    <>
      <FocusFeature />
      <VoiceFeature />
      <AttentionFeature />
      <UpdatesFeature />
    </>
  );
}
