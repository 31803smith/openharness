'use client';

import { useEffect, useReducer } from 'react';
import {
  ArrowLeft,
  ArrowRight,
  Check,
  Pause,
  Play,
  RotateCcw,
  Usb,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from '@/components/ui/dialog';
import { DeviceHardware } from '@/components/device-hardware';
import {
  demoReducer,
  initialState,
  type DemoAction,
  type DemoState,
} from '@/lib/demo-state';

const SCENES: {
  eyebrow: string;
  title: string;
  accent: string;
  description: string;
  actions: DemoAction[];
}[] = [
  {
    eyebrow: 'MEET HARNESS',
    title: 'Your agents.',
    accent: 'Within reach.',
    description: 'One workspace on screen. One simple way to move through it.',
    actions: [{ type: 'reset' }],
  },
  {
    eyebrow: '01 / FIND YOUR FLOW',
    title: 'Switch agents.',
    accent: 'Keep your place.',
    description: 'Swipe left or right. Your workspace follows your focus.',
    actions: [{ type: 'reset' }, { type: 'step', direction: 1 }],
  },
  {
    eyebrow: '02 / SAY THE WORD',
    title: 'Say what',
    accent: 'comes next.',
    description: 'Double tap to speak to the agent in focus.',
    actions: [{ type: 'reset' }, { type: 'voice-start' }],
  },
  {
    eyebrow: '02 / SAY THE WORD',
    title: 'Message sent.',
    accent: 'Work continues.',
    description: 'Your message reaches Storefront, even if you switch agents.',
    actions: [
      { type: 'reset' },
      { type: 'voice-start' },
      { type: 'voice-transcribe' },
      { type: 'voice-send' },
    ],
  },
  {
    eyebrow: '03 / TAKE A DETOUR',
    title: 'One small',
    accent: 'decision.',
    description:
      'Tap a notification to go straight to the agent that needs you.',
    actions: [
      { type: 'reset' },
      { type: 'focus', agent: 'notes' },
      { type: 'scroll', delta: 6 },
      { type: 'inspect-question' },
    ],
  },
  {
    eyebrow: '03 / TAKE A DETOUR',
    title: 'And right',
    accent: 'back to your flow.',
    description: 'Return to the same agent and the same reading position.',
    actions: [
      { type: 'reset' },
      { type: 'focus', agent: 'notes' },
      { type: 'scroll', delta: 6 },
      { type: 'inspect-question' },
      { type: 'answer' },
      { type: 'return' },
    ],
  },
  {
    eyebrow: 'HARNESS V2',
    title: 'Great work.',
    accent: 'Within reach.',
    description:
      'The app and the device. Connected by USB. Built around your work.',
    actions: [
      { type: 'reset' },
      { type: 'inspect-question' },
      { type: 'answer' },
      { type: 'return' },
    ],
  },
];

type Playback = {
  scene: number;
  playing: boolean;
  progress: number;
  interacted: boolean;
  demo: DemoState;
};
type PlaybackAction =
  | { type: 'tick' }
  | { type: 'move'; scene: number }
  | { type: 'toggle' }
  | { type: 'interact' | 'voice-timer'; action: DemoAction };

function enterScene(scene: number, playing: boolean): Playback {
  return {
    scene,
    playing,
    progress: 0,
    interacted: false,
    demo: SCENES[scene].actions.reduce(demoReducer, initialState()),
  };
}

function playbackReducer(player: Playback, action: PlaybackAction): Playback {
  switch (action.type) {
    case 'tick': {
      if (!player.playing) return player;
      if (player.progress >= 99)
        return player.scene < SCENES.length - 1
          ? enterScene(player.scene + 1, true)
          : { ...player, progress: 100, playing: false };
      return { ...player, progress: player.progress + 1 };
    }
    case 'move':
      return enterScene(
        Math.max(0, Math.min(SCENES.length - 1, action.scene)),
        player.playing,
      );
    case 'toggle':
      return player.scene === SCENES.length - 1 && player.progress === 100
        ? enterScene(0, true)
        : {
            ...(player.interacted
              ? enterScene(player.scene, !player.playing)
              : player),
            playing: !player.playing,
          };
    case 'interact':
      return {
        ...player,
        playing: false,
        interacted: true,
        demo: demoReducer(player.demo, action.action),
      };
    case 'voice-timer':
      return { ...player, demo: demoReducer(player.demo, action.action) };
  }
}

function KeynotePlayer({ onExplore }: { onExplore: () => void }) {
  const [player, dispatch] = useReducer(playbackReducer, undefined, () =>
    enterScene(0, true),
  );
  const { demo: state, scene, playing, progress, interacted } = player;
  const current = SCENES[scene];

  useEffect(() => {
    if (
      !interacted ||
      (state.voice !== 'listening' && state.voice !== 'transcribing')
    )
      return;
    const timer = window.setTimeout(
      () =>
        dispatch({
          type: 'voice-timer',
          action: {
            type:
              state.voice === 'listening' ? 'voice-transcribe' : 'voice-send',
          },
        }),
      state.voice === 'listening' ? 4200 : 1200,
    );
    return () => window.clearTimeout(timer);
  }, [state.voice, interacted]);
  useEffect(() => {
    if (!playing) return;
    const timer = window.setInterval(() => dispatch({ type: 'tick' }), 70);
    return () => window.clearInterval(timer);
  }, [playing, scene]);
  function manualAction(action: DemoAction) {
    dispatch({ type: 'interact', action });
  }
  function move(next: number) {
    dispatch({ type: 'move', scene: next });
  }

  return (
    <div className="keynote-player">
      <div className="keynote-top">
        <span className="keynote-wordmark">
          <span className="brand-glyph">h</span>harness <i>THE V2 EXPERIENCE</i>
        </span>
        <span className="keynote-runtime">
          {String(scene + 1).padStart(2, '0')} / 07
        </span>
      </div>
      <div className="keynote-main">
        <div className="keynote-copy" key={scene}>
          <p className="eyebrow">{current.eyebrow}</p>
          <h2>
            {current.title}
            <br />
            <span>{current.accent}</span>
          </h2>
          <p>{current.description}</p>
          {scene === SCENES.length - 1 ? (
            <Button className="primary-pill" onClick={onExplore}>
              Try it yourself
              <ArrowRight />
            </Button>
          ) : (
            <span className="keynote-small">
              <Usb />
              Connected by USB.
            </span>
          )}
        </div>
        <div className="keynote-product">
          <DeviceHardware
            state={state}
            dispatch={manualAction}
            onVoice={() => manualAction({ type: 'voice-start' })}
            onStopVoice={() => manualAction({ type: 'voice-transcribe' })}
          />
        </div>
      </div>
      <div className="keynote-timeline">
        {SCENES.map((item, index) => (
          <button
            key={index}
            aria-label={`Go to scene ${index + 1}: ${item.title} ${item.accent}`}
            onClick={() => move(index)}
            className={index === scene ? 'is-current' : ''}
          >
            <span
              style={{
                width: `${index < scene ? 100 : index === scene ? progress : 0}%`,
              }}
            />
          </button>
        ))}
      </div>
      <div className="keynote-controls">
        <button
          aria-label={
            scene === SCENES.length - 1 && progress === 100
              ? 'Replay keynote'
              : playing
                ? 'Pause keynote'
                : 'Play keynote'
          }
          onClick={() => dispatch({ type: 'toggle' })}
        >
          {scene === SCENES.length - 1 && progress === 100 ? (
            <RotateCcw />
          ) : playing ? (
            <Pause />
          ) : (
            <Play />
          )}
        </button>
        <span>
          {interacted
            ? 'Paused while you explore'
            : playing
              ? 'Playing the reveal'
              : progress === 100
                ? 'Your turn.'
                : 'Paused'}
        </span>
        <div>
          <button
            aria-label="Previous scene"
            disabled={scene === 0}
            onClick={() => move(scene - 1)}
          >
            <ArrowLeft />
          </button>
          <button
            aria-label="Next scene"
            disabled={scene === SCENES.length - 1}
            onClick={() => move(scene + 1)}
          >
            {scene === SCENES.length - 1 ? <Check /> : <ArrowRight />}
          </button>
        </div>
      </div>
      <span className="keynote-disclosure">
        Interactive concept · Simulated agents and voice
      </span>
    </div>
  );
}

export function Keynote({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="keynote-dialog">
        <DialogTitle className="sr-only">
          Introducing the Harness V2 experience
        </DialogTitle>
        <DialogDescription className="sr-only">
          A guided interactive product reveal. Pause, change scenes, or explore
          the device. Escape closes the keynote.
        </DialogDescription>
        {open && (
          <KeynotePlayer
            onExplore={() => {
              onOpenChange(false);
              window.setTimeout(
                () =>
                  document.getElementById('experience')?.scrollIntoView({
                    behavior: window.matchMedia(
                      '(prefers-reduced-motion: reduce)',
                    ).matches
                      ? 'instant'
                      : 'smooth',
                  }),
                100,
              );
            }}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}
