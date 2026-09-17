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

  /**
   * The release bundle is ONE file — upload-cli.sh, install.sh and the self-updater all move `cli.js`
   * and `notify.mjs` and nothing else — so the docs cannot travel as files beside it. The bundle
   * build embeds them (esbuild `define`, the way the dsh registry travels), and a bundled daemon
   * installs from that, never from a `docs/skills/` it does not have.
   */
  it('installs from the sources the build embedded, reading nothing from docs/skills', async () => {
    vi.stubGlobal('__HARNESS_SKILLS__', JSON.stringify({
      'harness-compute.md': '# EMBEDDED SKILL\n\nfrom the bundle\n',
      'harness-compute.agent.md': "---\nname: 'harness-compute'\nmode: primary\n---\nEMBEDDED AGENT\n",
    }))
    try {
      const { installOpencodeHarnessComputeSkill } = await load()
      installOpencodeHarnessComputeSkill()

      const skill = readFileSync(join(configHome, 'opencode', 'skills', 'harness-compute', 'SKILL.md'), 'utf-8')
      expect(skill.startsWith('---\nname: harness-compute\n')).toBe(true)
      expect(skill.endsWith('# EMBEDDED SKILL\n\nfrom the bundle\n')).toBe(true)
      expect(skill).not.toContain('HOW TO OPERATE HARNESS COMPUTE')
      const agent = readFileSync(join(configHome, 'opencode', 'agents', 'harness-compute.md'), 'utf-8')
      expect(agent).toBe("---\nname: 'harness-compute'\nmode: primary\n---\nEMBEDDED AGENT\n")
      expect(console.error).not.toHaveBeenCalled()
    } finally {
      vi.unstubAllGlobals()
    }
  })

  it('is what both builds embed: the two docs, by name, in build.mjs and build-bundle.mjs', () => {
    const cliRoot = join(__dirname, '..', '..')
    for (const script of ['build.mjs', 'build-bundle.mjs']) {
      const source = readFileSync(join(cliRoot, script), 'utf-8')
      expect(source, script).toContain('__HARNESS_SKILLS__')
      expect(source, script).toContain("'harness-compute.md'")
      expect(source, script).toContain("'harness-compute.agent.md'")
    }
    // The copy beside cli.js is gone with the lookup that read it: a directory nobody ships is a
    // promise nobody keeps. (The comment explaining why may still name it; the calls may not.)
    const bundle = readFileSync(join(cliRoot, 'build-bundle.mjs'), 'utf-8')
    expect(bundle).not.toMatch(/mkdirSync\(['"]dist\/skills/)
    expect(bundle).not.toMatch(/copyFileSync\([^)]*dist\/skills/)
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
