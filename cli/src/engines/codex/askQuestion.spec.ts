import { describe, expect, it } from 'vitest'
import { readFileSync } from 'fs'
import { fileURLToPath } from 'url'
import { codexRowKeys, parseEngineQuestionPane } from '../../lib/askQuestion.js'

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

  it('commits a request_user_input row with Enter, an approval row with the digit alone', () => {
    const q = parseEngineQuestionPane('codex', fixture('question-codex.txt'))
    const p = parseEngineQuestionPane('codex', fixture('permission-codex.txt'))
    if (q?.kind !== 'question' || p?.kind !== 'question') throw new Error('fixtures did not parse')
    expect(codexRowKeys(q.rows[0], q)).toEqual(['1', 'Enter'])
    expect(codexRowKeys(p.rows[1], p)).toEqual(['2'])
  })

  it('reads a dialog whose top is scrolled out of the pane as still open, not as gone', () => {
    // A four-pane window leaves Codex's dialog this much room: rows 3–5 and the footer. Row 1 and the
    // question are above the pane. Measured 2026-09-15; the watcher used to close the dial on it.
    const scrolled = [
      '                          sans-serif.',
      '    3. Mono               A technical',
      '                          monospaced',
      '                          visual style.',
      '    4. Roboto             A neutral,',
      '                          widely',
      '                          supported UI',
      '                          sans-serif.',
      '    5. None of the above  Optionally, add',
      '  option 1/5 | tab to add notes',
      '  enter to submit answer',
      '  esc to interrupt',
    ].join('\n')
    const view = parseEngineQuestionPane('codex', scrolled)
    expect(view).toMatchObject({ kind: 'question', partial: true, question: '' })
    if (view?.kind !== 'question') return
    expect(view.rows.map((r) => r.label)).toEqual(['Mono', 'Roboto', 'None of the above'])
  })
})
