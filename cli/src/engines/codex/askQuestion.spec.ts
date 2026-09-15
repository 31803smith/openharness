import { describe, expect, it } from 'vitest'
import { readFileSync } from 'fs'
import { fileURLToPath } from 'url'
import { parseEngineQuestionPane } from '../../lib/askQuestion.js'

function fixture(name: string): string {
  return readFileSync(fileURLToPath(new URL(`../../lib/__fixtures__/${name}`, import.meta.url)), 'utf-8')
}

describe('Codex question dialog', () => {
  it('reads a request_user_input dialog and keeps only the option labels', () => {
    // Captured live (plan mode, 0.149): the footer is `enter to submit answer | esc to interrupt`, and
    // each row carries its description in an aligned column after the label.
    expect(parseEngineQuestionPane('codex', fixture('question-codex.txt'))).toMatchObject({
      kind: 'question',
      question: 'Which colour should the demo use?',
      rows: [
        { number: '1', label: 'Red' },
        { number: '2', label: 'Green' },
      ],
      multi: false,
    })
  })

  it('still reads the approval prompt, whose rows have no description column', () => {
    const view = parseEngineQuestionPane('codex', fixture('permission-codex.txt'))
    expect(view?.kind).toBe('question')
    if (view?.kind !== 'question') return
    expect(view.rows[0].label).toMatch(/^Yes/)
  })
})
