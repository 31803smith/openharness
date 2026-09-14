'use client';

import { useEffect, useRef, useState } from 'react';
import Image from 'next/image';
import { ArrowUpRight, Circle, Fingerprint, Play, Usb } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { EngineMark } from '@/components/device-hardware';
import { FeatureWalkthrough } from '@/components/feature-walkthrough';
import { HeroWorkspace } from '@/components/hero-workspace';
import { Keynote } from '@/components/keynote';
import { AGENTS } from '@/lib/demo-state';

export function Wordmark() {
  return (
    <a href="#top" className="wordmark" aria-label="Harness home">
      <span className="brand-glyph">h</span>
      <span>harness</span>
      <span className="version-tag">V2</span>
    </a>
  );
}

export default function HarnessExperience() {
  const [keynoteOpen, setKeynoteOpen] = useState(false);
  const progressLine = useRef<HTMLDivElement>(null);
  const heroProduct = useRef<HTMLElement>(null);

  useEffect(() => {
    const elements = document.querySelectorAll('.reveal');
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add('is-visible');
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.08, rootMargin: '0px 0px -30px 0px' },
    );
    elements.forEach((element) => {
      element.classList.add('reveal-ready');
      observer.observe(element);
    });
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
    let frame = 0;
    const update = () => {
      const range = document.documentElement.scrollHeight - window.innerHeight;
      if (progressLine.current)
        progressLine.current.style.transform = `scaleX(${range > 0 ? window.scrollY / range : 0})`;
      if (heroProduct.current)
        heroProduct.current.style.translate = reduced.matches
          ? '0 0'
          : `0 ${Math.min(window.scrollY * 0.035, 24)}px`;
      frame = 0;
    };
    const scroll = () => {
      if (!frame) frame = window.requestAnimationFrame(update);
    };
    window.addEventListener('scroll', scroll, { passive: true });
    update();
    return () => {
      observer.disconnect();
      window.removeEventListener('scroll', scroll);
      window.cancelAnimationFrame(frame);
    };
  }, []);

  return (
    <main id="top" className="launch-page">
      <a className="skip-link" href="#experience">
        Skip to the interactive demo
      </a>
      <div className="reading-progress" ref={progressLine} />
      <header className="site-header">
        <Wordmark />
        <nav aria-label="Main navigation">
          <a href="#experience">Experience</a>
          <a href="#details">Device</a>
          <button className="nav-cta" onClick={() => setKeynoteOpen(true)}>
            Watch the reveal
            <Play />
          </button>
        </nav>
      </header>
      <section className="hero" aria-labelledby="hero-title">
        <div className="hero-copy">
          <p className="eyebrow">Introducing Harness V2</p>
          <h1 id="hero-title">
            Great work.
            <br />
            <span>Within reach.</span>
          </h1>
          <p className="hero-description">
            A home for your agents. A touch closer to your work.
          </p>
          <div className="hero-actions">
            <Button
              className="primary-pill"
              nativeButton={false}
              render={
                <a
                  href="#experience"
                  aria-label="Experience the interactive Harness demo"
                />
              }
            >
              Try it yourself
            </Button>
            <button
              className="text-action"
              onClick={() => setKeynoteOpen(true)}
            >
              <span className="play-circle">
                <Play />
              </span>
              Watch the reveal
            </button>
          </div>
        </div>
        <figure className="hero-desk" ref={heroProduct}>
          <div className="hero-desk-scene">
            <Image
              src="/images/harness-desk-connected.webp"
              width="1672"
              height="941"
              alt="A 27-inch monitor and the small Harness device on a clean desk, joined by one straight USB cable. Six agents work across four machines; the highlighted agent and its status appear on both screens."
              className="hero-desk-image"
              priority
              unoptimized
            />
            <HeroWorkspace />
          </div>
        </figure>
      </section>
      <FeatureWalkthrough />
      <div className="familiar-agents reveal">
        <p>The agents you know. Together in Harness.</p>
        <div>
          {['storefront', 'api', 'tests'].map((id) => (
            <span key={id}>
              <EngineMark agent={AGENTS[id]} />
              {AGENTS[id].engine}
            </span>
          ))}
        </div>
      </div>
      <section
        className="details-strip reveal"
        id="details"
        aria-label="Device details"
      >
        <div>
          <Circle />
          <span>
            <b>466 × 466</b>
            <small>A clear view, at a glance.</small>
          </span>
        </div>
        <div>
          <Usb />
          <span>
            <b>Connected by USB</b>
            <small>One cable to your computer.</small>
          </span>
        </div>
        <div>
          <Fingerprint />
          <span>
            <b>Made for touch</b>
            <small>Swipe, scroll, and speak.</small>
          </span>
        </div>
      </section>
      <section className="closing-section reveal">
        <p className="eyebrow">Harness V2</p>
        <h2>
          Your next great thing.
          <br />
          <span>Starts here.</span>
        </h2>
        <p>See what happens when your workspace works with you.</p>
        <div className="closing-actions">
          <Button className="primary-pill" onClick={() => setKeynoteOpen(true)}>
            Watch the reveal
            <Play />
          </Button>
          <a className="text-link" href="#experience">
            Try the experience
            <ArrowUpRight />
          </a>
        </div>
      </section>
      <footer className="site-footer">
        <Wordmark />
        <span>Great work. Within reach.</span>
        <small>Interactive preview. Agents and voice are simulated.</small>
      </footer>
      <Keynote open={keynoteOpen} onOpenChange={setKeynoteOpen} />
    </main>
  );
}
