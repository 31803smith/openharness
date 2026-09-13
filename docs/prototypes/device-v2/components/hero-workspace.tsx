'use client';

import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { Check, GitBranch, Hand, Pause, Play } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { EngineMark } from '@/components/device-hardware';
import { AGENTS } from '@/lib/demo-state';
import {
  getHeroFrame,
  HERO_MACHINES,
  HERO_LOOP_MS,
  type HeroSessionFrame,
} from '@/lib/hero-workspace';

function lineTone(line: string) {
  if (line.startsWith('+')) return 'added';
  if (line.startsWith('-')) return 'removed';
  if (/^[❯›$]/.test(line)) return 'command';
  if (line.startsWith('?')) return 'attention';
  if (/✓|PASS|passed|passing|200 OK|complete\./.test(line)) return 'success';
  if (/^[⏺•]/.test(line)) return 'tool';
  return 'text';
}

function HeroTerminal({
  frame,
  focused,
}: {
  frame: HeroSessionFrame;
  focused: boolean;
}) {
  const { session, status, outputTick, seconds } = frame;
  const agent = AGENTS[session.agent];
  const working = status === 'working';
  const machine = HERO_MACHINES.find((item) => item.id === session.machine)!;
  const output = working
    ? Array.from(
        { length: 21 },
        (_, index) =>
          session.lines[(outputTick + index) % session.lines.length],
      )
    : session.status === 'working' && session.completion
      ? [...session.lines.slice(-17), '', ...session.completion]
      : session.lines;

  return (
    <div
      className={
        'hero-terminal hero-terminal-' +
        status +
        (focused ? ' hero-terminal-focused' : '')
      }
    >
      <div className="hero-terminal-heading">
        <EngineMark agent={agent} />
        <b>{agent.name}</b>
        <span>{machine.name}</span>
        {status === 'waiting' ? (
          <Hand className="hero-terminal-status-icon" />
        ) : status === 'ready' ? (
          <Check className="hero-terminal-status-icon" />
        ) : (
          <i className="hero-terminal-status-dot" />
        )}
      </div>
      <div className="hero-terminal-path">
        <GitBranch />
        {session.branch}
        <span>{session.folder}</span>
      </div>
      <div className="hero-terminal-output">
        {output.map((line, index) => (
          <div key={index} className={'hero-line hero-line-' + lineTone(line)}>
            {line || '\u00a0'}
          </div>
        ))}
      </div>
      <div className="hero-terminal-footer">
        <span>
          {working ? (
            <>
              <i className="hero-terminal-cursor" /> Working
            </>
          ) : status === 'ready' ? (
            'Finished'
          ) : (
            'Needs you'
          )}
        </span>
        <span>
          {agent.engine}
          <em>·</em>
          {Math.floor(seconds / 60)}m {String(seconds % 60).padStart(2, '0')}s
        </span>
      </div>
    </div>
  );
}

function HeroDeviceScreen({ frame }: { frame: HeroSessionFrame }) {
  const { session, status } = frame;
  return (
    <div className="hero-device-screen" aria-hidden="true">
      <span className="hero-device-swarm">Workshop</span>
      <div
        className={'hero-device-content hero-device-' + status}
        key={session.agent + ':' + status}
      >
        <div className="hero-device-identity">
          <EngineMark agent={AGENTS[session.agent]} />
          <b>{AGENTS[session.agent].name}</b>
        </div>
        {status === 'ready' && session.completion ? (
          <div className="hero-device-summary">
            {session.completion.map((line) => (
              <span key={line}>{line}</span>
            ))}
          </div>
        ) : (
          <span className="hero-device-status">
            {status === 'waiting' ? <Hand /> : <i />}
            {status === 'waiting' ? 'Needs you' : 'Working'}
          </span>
        )}
      </div>
    </div>
  );
}

export function HeroWorkspace() {
  const monitor = useRef<HTMLDivElement>(null);
  const [inView, setInView] = useState(false);
  const [documentVisible, setDocumentVisible] = useState(true);
  const [reducedMotion, setReducedMotion] = useState(true);
  const [paused, setPaused] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const running = inView && documentVisible && !reducedMotion && !paused;
  const frame = getHeroFrame(elapsed);
  const focusedAgent = AGENTS[frame.focused.session.agent];
  const counts = (status: HeroSessionFrame['status']) =>
    frame.sessions.filter((session) => session.status === status).length;

  useEffect(() => {
    const element = monitor.current;
    if (!element) return;
    const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
    const updateMotion = () => setReducedMotion(motion.matches);
    const updateVisibility = () => setDocumentVisible(!document.hidden);
    const observer = new IntersectionObserver(
      ([entry]) => setInView(entry.isIntersecting),
      { threshold: 0.15 },
    );
    observer.observe(element);
    motion.addEventListener('change', updateMotion);
    document.addEventListener('visibilitychange', updateVisibility);
    updateMotion();
    updateVisibility();
    return () => {
      observer.disconnect();
      motion.removeEventListener('change', updateMotion);
      document.removeEventListener('visibilitychange', updateVisibility);
    };
  }, []);

  useEffect(() => {
    if (!running) return;
    // One clock owns both screens. A fresh measurement on resume prevents
    // jumping ahead after pausing, scrolling away, or leaving the tab.
    let previous = performance.now();
    const timer = window.setInterval(() => {
      const now = performance.now();
      const delta = now - previous;
      previous = now;
      setElapsed((value) => (value + delta) % HERO_LOOP_MS);
    }, 200);
    return () => window.clearInterval(timer);
  }, [running]);

  return (
    <>
      <div
        className="hero-monitor"
        ref={monitor}
        aria-hidden="true"
        data-running={running}
      >
        <div className="hero-workspace">
          <div className="hero-workspace-titlebar">
            <span className="hero-window-dots">
              <i />
              <i />
              <i />
            </span>
            <b>Harness V2</b>
            <div className="hero-workspace-tabs">
              <span className="is-selected">Workshop</span>
              <span>Launch</span>
              <span>Infrastructure</span>
            </div>
            <span className="hero-workspace-machines">4 machines</span>
          </div>
          <div className="hero-terminal-grid">
            {frame.sessions.map((session, index) => (
              <div
                className="hero-terminal-cell"
                key={session.session.agent}
                style={
                  { '--cursor-delay': index * -0.23 + 's' } as CSSProperties
                }
              >
                <HeroTerminal
                  frame={session}
                  focused={session === frame.focused}
                />
              </div>
            ))}
          </div>
          <div className="hero-workspace-statusbar">
            <span>
              <i /> Connected by USB
            </span>
            <span>{focusedAgent.name} in focus</span>
            <span>
              {counts('working')} working<em>·</em>
              {counts('ready')} finished
              <em>·</em>
              {counts('waiting')} needs you
            </span>
          </div>
        </div>
      </div>
      <HeroDeviceScreen frame={frame.focused} />
      {!reducedMotion && (
        <Button
          className="hero-motion-toggle"
          variant="ghost"
          size="icon"
          aria-label={paused ? 'Play hero animation' : 'Pause hero animation'}
          title={paused ? 'Play hero animation' : 'Pause hero animation'}
          onClick={() => setPaused((value) => !value)}
        >
          {paused ? <Play /> : <Pause />}
        </Button>
      )}
    </>
  );
}
