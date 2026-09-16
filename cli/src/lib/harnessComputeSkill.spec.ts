import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'fs'
import { join } from 'path'
import { tmpdir } from 'os'

/**
 * `harness start` drops two files for opencode: the Harness Compute skill (frontmatter + the doc)
 * and the `harness-compute` agent definition (the doc verbatim — its frontmatter is the agent's). Both
 * land under XDG_CONFIG_HOME, both are idempotent, and neither may fail the start.
 */
describe('installOpencodeHarnessComputeSkill', () => {
  let configHome = ''
  const docs = join(__dirname, '..', '..', '..', 'docs', 'skills')

  async function load() {
    vi.resetModules()
    process.env.XDG_CONFIG_HOME = configHome
    delete process.env.OPENCODE_SKILL_DIR
    delete process.env.OPENCODE_AGENT_DIR
    return import('./harnessComputeSkill.js')
  }

  beforeEach(() => {
    configHome = mkdtempSync(join(tmpdir(), 'adapter-opencode-skill-'))
    vi.spyOn(console, 'log').mockImplementation(() => {})
    vi.spyOn(console, 'error').mockImplementation(() => {})
  })

  afterEach(() => {
    rmSync(configHome, { recursive: true, force: true })
    delete process.env.XDG_CONFIG_HOME
    vi.restoreAllMocks()
  })

  it('installs the skill with its frontmatter and the agent definition verbatim, under XDG_CONFIG_HOME', async () => {
    const { installOpencodeHarnessComputeSkill } = await load()
    installOpencodeHarnessComputeSkill()

    const skill = readFileSync(join(configHome, 'opencode', 'skills', 'harness-compute', 'SKILL.md'), 'utf-8')
    expect(skill.startsWith('---\nname: harness-compute\n')).toBe(true)
    expect(skill).toContain(readFileSync(join(docs, 'harness-compute.md'), 'utf-8').trimEnd())

    const agent = readFileSync(join(configHome, 'opencode', 'agents', 'harness-compute.md'), 'utf-8')
    // Byte-for-byte: the source file carries the exact frontmatter opencode reads, nothing is added.
    expect(agent).toBe(readFileSync(join(docs, 'harness-compute.agent.md'), 'utf-8'))
    expect(agent.startsWith("---\nname: 'harness-compute'\n")).toBe(true)
    expect(agent).toContain('mode: primary')
    expect(agent).toContain('question: allow')
    expect(console.error).not.toHaveBeenCalled()
  })

  it('is a no-op the second time: nothing rewritten, no temp file left behind', async () => {
    const { installOpencodeHarnessComputeSkill } = await load()
    installOpencodeHarnessComputeSkill()
    const skillPath = join(configHome, 'opencode', 'skills', 'harness-compute', 'SKILL.md')
    const agentPath = join(configHome, 'opencode', 'agents', 'harness-compute.md')
    const before = [statSync(skillPath).mtimeMs, statSync(agentPath).mtimeMs]
    vi.mocked(console.log).mockClear()

    await new Promise((resolve) => setTimeout(resolve, 20))
    installOpencodeHarnessComputeSkill()

    expect([statSync(skillPath).mtimeMs, statSync(agentPath).mtimeMs]).toEqual(before)
    expect(vi.mocked(console.log).mock.calls.map(([line]) => String(line))).toEqual([
      '[hooks] Harness Compute opencode skill already installed',
      '[hooks] harness-compute opencode agent already installed',
    ])
    expect(readdirSync(join(configHome, 'opencode', 'agents'))).toEqual(['harness-compute.md'])
    expect(readdirSync(join(configHome, 'opencode', 'skills', 'harness-compute'))).toEqual(['SKILL.md'])
  })

  it('rewrites a file that drifted from the source', async () => {
    const { installOpencodeHarnessComputeSkill } = await load()
    installOpencodeHarnessComputeSkill()
    const agentPath = join(configHome, 'opencode', 'agents', 'harness-compute.md')
    writeFileSync(agentPath, '---\nname: harness-compute\n---\nedited by hand\n')

    installOpencodeHarnessComputeSkill()

    expect(readFileSync(agentPath, 'utf-8')).toBe(readFileSync(join(docs, 'harness-compute.agent.md'), 'utf-8'))
  })

  it('honours OPENCODE_AGENT_DIR and OPENCODE_SKILL_DIR over the XDG default', async () => {
    vi.resetModules()
    process.env.XDG_CONFIG_HOME = configHome
    process.env.OPENCODE_SKILL_DIR = join(configHome, 'custom-skills')
    process.env.OPENCODE_AGENT_DIR = join(configHome, 'custom-agents')
    try {
      const { installOpencodeHarnessComputeSkill } = await import('./harnessComputeSkill.js')
      installOpencodeHarnessComputeSkill()
      expect(existsSync(join(configHome, 'custom-skills', 'harness-compute', 'SKILL.md'))).toBe(true)
      expect(existsSync(join(configHome, 'custom-agents', 'harness-compute.md'))).toBe(true)
      expect(existsSync(join(configHome, 'opencode'))).toBe(false)
    } finally {
      delete process.env.OPENCODE_SKILL_DIR
      delete process.env.OPENCODE_AGENT_DIR
    }
  })
})
