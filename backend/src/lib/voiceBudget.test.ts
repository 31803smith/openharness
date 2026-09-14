import { beforeEach, describe, expect, it, vi } from 'vitest'

vi.mock('../config/env.js', () => ({ env: { VOICE_INFLIGHT_MAX_BYTES: 100 } }))

const { reserveVoice, releaseVoice, voiceInflightBytes } = await import('./voiceBudget.js')

describe('voiceBudget', () => {
  beforeEach(() => { releaseVoice(voiceInflightBytes()) })

  it('reserves up to the cap and refuses beyond it without taking anything', () => {
    expect(reserveVoice(60)).toBe(true)
    expect(reserveVoice(40)).toBe(true)
    expect(voiceInflightBytes()).toBe(100)
    expect(reserveVoice(1)).toBe(false)
    expect(voiceInflightBytes()).toBe(100)
  })

  it('release frees capacity and never goes negative', () => {
    reserveVoice(50)
    releaseVoice(30)
    expect(voiceInflightBytes()).toBe(20)
    releaseVoice(1_000)
    expect(voiceInflightBytes()).toBe(0)
    expect(reserveVoice(100)).toBe(true)
  })

  it('ignores non-positive amounts', () => {
    expect(reserveVoice(0)).toBe(true)
    expect(reserveVoice(-5)).toBe(true)
    releaseVoice(-5)
    expect(voiceInflightBytes()).toBe(0)
  })
})
