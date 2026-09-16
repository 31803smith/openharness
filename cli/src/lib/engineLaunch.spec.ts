import { afterEach, describe, expect, it } from 'vitest'
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  AGENT_NAME_RE,
  BYPASS_PERMISSION_FLAGS,
  FIRST_PROMPT_ARGS,
  FirstPromptUnsupportedError,
  LAUNCH_RESUME_FLAG,
  NAMED_AGENT_ARGS,
  NamedAgentUnsupportedError,
  buildEngineCommandArgv,
  buildEngineLaunchArgv,
  commandAvailableInInteractiveShell,
  firstPromptArgs,
  namedAgentArgs,
  supportsFirstPrompt,
  supportsNamedAgent,
  unreadableCwdGuard,
} from './engineLaunch.js'
import { ENGINES } from '../engines/types.js'
import { engineBin } from './engineBin.js'
import type { EngineInstallRecipe } from './engineInstall.js'
import { MIN_OPEN_FILES, RAISE_OPEN_FILES_SH } from './openFiles.js'

describe('buildEngineLaunchArgv', () => {
  it('wraps zsh in its interactive login form and execs the resolved binary', () => {
    expect(buildEngineLaunchArgv('claude', {}, '/bin/zsh')).toEqual([
      '/bin/zsh', '-lic', `${RAISE_OPEN_FILES_SH}exec "$@"`, 'harness-engine', engineBin('claude'),
    ])
  })

  it('uses Ubuntu bash interactive startup files without making it a login shell', () => {
    expect(buildEngineLaunchArgv('claude', {}, '/bin/bash')).toEqual([
      '/bin/bash', '-ic', `${RAISE_OPEN_FILES_SH}exec "$@"`, 'harness-engine', engineBin('claude'),
    ])
  })

  it('enters the workspace only after interactive startup has completed', () => {
    const argv = buildEngineLaunchArgv('claude', { cwd: '/work/project' }, '/bin/zsh')
    expect(argv).toEqual([
      '/bin/zsh', '-lic',
      `${RAISE_OPEN_FILES_SH}if ! cd -- "$1"; then printf '%s\\n' 'harness: the selected working directory is unavailable.' >&2; exit 1; fi\n${unreadableCwdGuard(process.platform)}shift\nexec "$@"`,
      'harness-engine', '/work/project', engineBin('claude'),
    ])
  })

  it('hands the engine a soft open-files limit fit for it, however low the pane started', async () => {
    // A tmux server started by the desktop app passes launchd's 256 to every pane; Claude Code will
    // not start under that. The pane's own shell lifts it before exec, so the server never has to.
    const [shell, flag, paneScript] = buildEngineLaunchArgv('claude', {}, '/bin/sh')
    const { execFile } = await import('node:child_process')
    const seenByEngine = await new Promise<string>((resolve, reject) => {
      execFile(
        '/bin/sh',
        ['-c', 'ulimit -S -n 256 || exit 99; exec "$@"', 'pane', shell, flag, paneScript, 'harness-engine', '/bin/sh', '-c', 'ulimit -S -n'],
        { timeout: 10_000 },
        (error, stdout, stderr) => (error ? reject(new Error(`${error.message}\n${stderr}`)) : resolve(stdout.trim())),
      )
    })
    expect(seenByEngine).not.toBe('256')
    expect(seenByEngine === 'unlimited' || Number(seenByEngine) >= Math.min(MIN_OPEN_FILES, 4096)).toBe(true)
  })

  describe('an unreadable workspace', () => {
    // Under /bin/sh, with the engine replaced by printf so its run leaves a marker.
    async function launchInto(dir: string): Promise<{ code: number; stdout: string; stderr: string }> {
      const [, , paneScript] = buildEngineLaunchArgv('claude', { cwd: dir }, '/bin/sh')
      const { execFile } = await import('node:child_process')
      return await new Promise((resolve) => {
        execFile(
          '/bin/sh',
          ['-c', paneScript, 'harness-engine', dir, '/usr/bin/printf', 'ENGINE_RAN\n'],
          { timeout: 10_000 },
          (error, stdout, stderr) => {
            const code = error && typeof (error as { code?: unknown }).code === 'number'
              ? (error as unknown as { code: number }).code
              : 0
            resolve({ code, stdout, stderr })
          },
        )
      })
    }

    // root reads everything, so the guard has nothing to catch there.
    const notRoot = process.getuid?.() !== 0

    it.skipIf(!notRoot)('says why and stops instead of letting the engine fail on its first read', async () => {
      // Enterable but not readable: what macOS privacy settings (TCC) produce for a folder the
      // responsible app was not granted — `cd` works, the first readdir does not.
      const dir = mkdtempSync(join(tmpdir(), 'harness-unreadable-'))
      try {
        chmodSync(dir, 0o300)
        const result = await launchInto(dir)
        expect(result.code).toBe(1)
        expect(result.stdout).not.toContain('ENGINE_RAN')
        expect(result.stderr).toContain(`harness: cannot read ${dir}`)
      } finally {
        chmodSync(dir, 0o700)
        rmSync(dir, { recursive: true, force: true })
      }
    })

    it('launches the engine when the workspace is readable', async () => {
      const dir = mkdtempSync(join(tmpdir(), 'harness-readable-'))
      try {
        const result = await launchInto(dir)
        expect(result.code).toBe(0)
        expect(result.stdout).toContain('ENGINE_RAN')
      } finally {
        rmSync(dir, { recursive: true, force: true })
      }
    })

    // Both hints are pushed through a real /bin/sh, whatever platform runs the suite: the quoting
    // of the macOS text (a backtick-free command, `›`, `—`) is what a Linux runner would otherwise
    // never exercise.
    async function guardOutput(platform: NodeJS.Platform, dir: string): Promise<string> {
      const { execFile } = await import('node:child_process')
      return await new Promise((resolve) => {
        execFile(
          '/bin/sh',
          ['-c', `cd -- "$1" || exit 9\n${unreadableCwdGuard(platform)}echo ENGINE_RAN`, 'guard', dir],
          { timeout: 10_000 },
          (_error, stdout, stderr) => resolve(stdout + stderr),
        )
      })
    }

    it.skipIf(!notRoot)('points at the privacy settings on macOS and at permissions elsewhere', async () => {
      const dir = mkdtempSync(join(tmpdir(), 'harness-unreadable-hint-'))
      try {
        chmodSync(dir, 0o300)
        const darwin = await guardOutput('darwin', dir)
        expect(darwin).toContain('Full Disk Access')
        expect(darwin).toContain('tmux kill-server')
        expect(darwin).toContain('Privacy & Security')
        expect(darwin).not.toContain('ENGINE_RAN')
        const linux = await guardOutput('linux', dir)
        expect(linux).toContain('permissions')
        expect(linux).not.toContain('Privacy & Security')
        expect(linux).not.toContain('ENGINE_RAN')
      } finally {
        chmodSync(dir, 0o700)
        rmSync(dir, { recursive: true, force: true })
      }
    })

    it('keeps the action inside what a relayed pane summary can show', () => {
      // First hint line: what to do. It has to survive next to a folder path in a ~180-char summary.
      const firstHint = unreadableCwdGuard('darwin').match(/'(harness: on macOS[^']*)'/)?.[1] ?? ''
      expect(firstHint.length).toBeGreaterThan(0)
      expect(firstHint.length).toBeLessThanOrEqual(120)
    })
  })

  it('falls back to direct execution when no absolute shell is available', () => {
    expect(buildEngineLaunchArgv('claude', {}, '')).toEqual([engineBin('claude')])
    expect(buildEngineLaunchArgv('claude', {}, 'zsh')).toEqual([engineBin('claude')])
  })

  it('appends the confirmed flag for engines with a known bypass flag', () => {
    expect(buildEngineCommandArgv('claude', { bypassPermission: true }))
      .toEqual([engineBin('claude'), '--dangerously-skip-permissions'])
    expect(buildEngineCommandArgv('codex', { bypassPermission: true }))
      .toEqual([engineBin('codex'), '--dangerously-bypass-approvals-and-sandbox'])
    expect(buildEngineCommandArgv('cursor', { bypassPermission: true }))
      .toEqual([engineBin('cursor'), '--force'])
    expect(buildEngineCommandArgv('opencode', { bypassPermission: true }))
      .toEqual([engineBin('opencode'), '--auto'])
  })

  it('is a no-op for engines with no confirmed flag, even when bypass is requested', () => {
    expect(buildEngineCommandArgv('pi', { bypassPermission: true })).toEqual([engineBin('pi')])
    expect(buildEngineCommandArgv('hermes', { bypassPermission: true })).toEqual([engineBin('hermes')])
  })

  it('has an entry (possibly null) for every known engine — no engine silently falls through', () => {
    for (const engine of ENGINES) {
      expect(Object.prototype.hasOwnProperty.call(BYPASS_PERMISSION_FLAGS, engine)).toBe(true)
    }
  })

  it('appends a flag-style resume argument after the binary', () => {
    expect(buildEngineCommandArgv('claude', { resumeSessionId: 'abc-123' }))
      .toEqual([engineBin('claude'), '--resume', 'abc-123'])
    expect(buildEngineCommandArgv('opencode', { resumeSessionId: 'ses_1' }))
      .toEqual([engineBin('opencode'), '--session', 'ses_1'])
  })

  it('puts a subcommand-style resume FIRST, ahead of any other flag', () => {
    expect(buildEngineCommandArgv('codex', { resumeSessionId: 'abc-123' }))
      .toEqual([engineBin('codex'), 'resume', 'abc-123'])
    expect(buildEngineCommandArgv('codex', { resumeSessionId: 'abc-123', bypassPermission: true }))
      .toEqual([engineBin('codex'), 'resume', 'abc-123', '--dangerously-bypass-approvals-and-sandbox'])
    expect(buildEngineCommandArgv('amp', { resumeSessionId: 'T-1' }))
      .toEqual([engineBin('amp'), 'threads', 'continue', 'T-1'])
  })

  it('still applies bypassPermission with no resume requested (regression)', () => {
    expect(buildEngineCommandArgv('claude', { bypassPermission: true }))
      .toEqual([engineBin('claude'), '--dangerously-skip-permissions'])
  })

  it('is a no-op when resumeSessionId is set but the engine has no known launch resume flag', () => {
    expect(buildEngineCommandArgv('devin', { resumeSessionId: 'abc-123' })).toEqual([engineBin('devin')])
  })

  it('has a launch resume flag for every engine RESUME_ARGS also covers, plus claude/codex', () => {
    for (const engine of ['claude', 'codex', 'cursor', 'opencode', 'kilo', 'pi', 'hermes', 'commandcode',
      'muse', 'amp', 'grok', 'agy', 'copilot'] as const) {
      expect(LAUNCH_RESUME_FLAG[engine]?.length).toBeGreaterThan(0)
    }
    expect(LAUNCH_RESUME_FLAG.devin).toBeUndefined()
  })
})

describe('a first prompt on launch', () => {
  const PROMPT = 'Start a local model on this machine'

  it('hands opencode the text through its TUI flag', () => {
    expect(buildEngineCommandArgv('opencode', { firstPrompt: PROMPT }))
      .toEqual([engineBin('opencode'), '--prompt', PROMPT])
  })

  it('hands claude and codex the text positionally', () => {
    expect(buildEngineCommandArgv('claude', { firstPrompt: PROMPT })).toEqual([engineBin('claude'), PROMPT])
    expect(buildEngineCommandArgv('codex', { firstPrompt: PROMPT })).toEqual([engineBin('codex'), PROMPT])
  })

  it('puts the text LAST, after every flag, so a positional is never read as an option value', () => {
    expect(buildEngineCommandArgv('claude', { firstPrompt: PROMPT, bypassPermission: true, extraArgs: ['--allowedTools=WebSearch'] }))
      .toEqual([engineBin('claude'), '--dangerously-skip-permissions', '--allowedTools=WebSearch', PROMPT])
    expect(buildEngineCommandArgv('opencode', { firstPrompt: PROMPT, bypassPermission: true, extraArgs: ['-m', 'local/qwen'] }))
      .toEqual([engineBin('opencode'), '--auto', '-m', 'local/qwen', '--prompt', PROMPT])
  })

  it('refuses an engine with no documented mechanism, naming the engine, rather than dropping the text', () => {
    expect(supportsFirstPrompt('cursor')).toBe(false)
    expect(() => firstPromptArgs('cursor', PROMPT)).toThrow(FirstPromptUnsupportedError)
    let refusal: unknown
    try { buildEngineCommandArgv('cursor', { firstPrompt: PROMPT }) } catch (error) { refusal = error }
    expect(refusal).toBeInstanceOf(FirstPromptUnsupportedError)
    expect((refusal as FirstPromptUnsupportedError).code).toBe('PROMPT_UNSUPPORTED')
    expect((refusal as FirstPromptUnsupportedError).message).toContain('cursor')
  })

  it('leaves the argv unchanged with no prompt, or an empty one', () => {
    expect(buildEngineCommandArgv('opencode', {})).toEqual([engineBin('opencode')])
    expect(buildEngineCommandArgv('opencode', { firstPrompt: '' })).toEqual([engineBin('opencode')])
    expect(buildEngineCommandArgv('cursor', { firstPrompt: '' })).toEqual([engineBin('cursor')])
  })

  it('reaches the engine as ONE positional argument through the pane shell, however it is spelled', async () => {
    // The pane script execs "$@": the prompt must arrive as a single argv entry, spaces, quotes and
    // all, rather than being re-split by the shell.
    const spelled = `Start a local model on "this" machine; it's $HOME`
    const [, , paneScript, marker, ...command] = buildEngineLaunchArgv('claude', { firstPrompt: spelled }, '/bin/sh')
    expect(marker).toBe('harness-engine')
    expect(command).toEqual([engineBin('claude'), spelled])
    const { execFile } = await import('node:child_process')
    const seen = await new Promise<string>((resolve, reject) => {
      execFile('/bin/sh', ['-c', paneScript, 'harness-engine', '/bin/sh', '-c', 'printf "%s" "$1"', 'engine', spelled],
        { timeout: 10_000 }, (error, stdout) => (error ? reject(error) : resolve(stdout)))
    })
    expect(seen).toBe(spelled)
  })

  it('has an entry (possibly null) for every known engine — no engine silently falls through', () => {
    for (const engine of ENGINES) {
      expect(Object.prototype.hasOwnProperty.call(FIRST_PROMPT_ARGS, engine)).toBe(true)
    }
    expect(supportsFirstPrompt('opencode')).toBe(true)
    expect(supportsFirstPrompt('claude')).toBe(true)
    expect(supportsFirstPrompt('codex')).toBe(true)
  })
})

describe('opening as a named agent', () => {
  it('hands opencode the name through --agent, in the extraArgs slot a relaunch also uses', () => {
    expect(namedAgentArgs('opencode', 'harness-compute')).toEqual(['--agent', 'harness-compute'])
    expect(buildEngineCommandArgv('opencode', { bypassPermission: true, extraArgs: ['-m', 'local/qwen', ...namedAgentArgs('opencode', 'harness-compute')] }))
      .toEqual([engineBin('opencode'), '--auto', '-m', 'local/qwen', '--agent', 'harness-compute'])
    // Resume keeps it too — the flag rides `extraArgs`, which every relaunch rebuilds from the row.
    expect(buildEngineCommandArgv('opencode', { resumeSessionId: 'ses_1', extraArgs: namedAgentArgs('opencode', 'harness-compute') }))
      .toEqual([engineBin('opencode'), '--session', 'ses_1', '--agent', 'harness-compute'])
  })

  it('refuses every other engine, naming it, rather than dropping the name', () => {
    for (const engine of ENGINES) {
      if (engine === 'opencode') continue
      expect(supportsNamedAgent(engine)).toBe(false)
      let refusal: unknown
      try { namedAgentArgs(engine, 'harness-compute') } catch (error) { refusal = error }
      expect(refusal).toBeInstanceOf(NamedAgentUnsupportedError)
      expect((refusal as NamedAgentUnsupportedError).code).toBe('AGENT_UNSUPPORTED')
      expect((refusal as NamedAgentUnsupportedError).message).toContain(engine)
    }
  })

  it('has an entry (possibly null) for every known engine — no engine silently falls through', () => {
    for (const engine of ENGINES) {
      expect(Object.prototype.hasOwnProperty.call(NAMED_AGENT_ARGS, engine)).toBe(true)
    }
    expect(supportsNamedAgent('opencode')).toBe(true)
  })

  it('accepts an identifier and nothing that could be a path or prose', () => {
    for (const ok of ['harness-compute', 'build', 'A_b-1', 'x'.repeat(64)]) expect(AGENT_NAME_RE.test(ok)).toBe(true)
    for (const bad of ['', ' harness-compute', 'local model', '../etc', 'a/b', 'name.md', 'x'.repeat(65), 'nämn']) {
      expect(AGENT_NAME_RE.test(bad)).toBe(false)
    }
  })
})

const dirs: string[] = []
const originalProbePath = process.env.HARNESS_ENGINE_TEST_PATH

afterEach(() => {
  if (originalProbePath === undefined) delete process.env.HARNESS_ENGINE_TEST_PATH
  else process.env.HARNESS_ENGINE_TEST_PATH = originalProbePath
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true })
})

function executable(dir: string, name: string): string {
  const path = join(dir, name)
  writeFileSync(path, '#!/bin/sh\nexit 0\n')
  chmodSync(path, 0o700)
  return path
}

function bashProbeShell(): string {
  const dir = mkdtempSync(join(tmpdir(), 'harness-engine-shell-'))
  dirs.push(dir)
  const shell = join(dir, 'bash')
  writeFileSync(shell, `#!/bin/sh
[ "$1" = '-ic' ] || exit 97
shift
script="$1"
shift
PATH="$HARNESS_ENGINE_TEST_PATH"
export PATH
exec /bin/sh -c "$script" "$@"
`)
  chmodSync(shell, 0o700)
  return shell
}

describe('commandAvailableInInteractiveShell', () => {
  it('uses the same bash interactive PATH that launches a new engine', async () => {
    const binDir = mkdtempSync(join(tmpdir(), 'harness-engine-bin-'))
    dirs.push(binDir)
    executable(binDir, 'kilo')
    process.env.HARNESS_ENGINE_TEST_PATH = binDir

    await expect(commandAvailableInInteractiveShell('kilo', bashProbeShell())).resolves.toBe(true)
    await expect(commandAvailableInInteractiveShell('missing-engine', bashProbeShell())).resolves.toBe(false)
  })

  it('recognizes an installed vendor path before the shell profile has it on PATH', async () => {
    const binDir = mkdtempSync(join(tmpdir(), 'harness-engine-vendor-bin-'))
    dirs.push(binDir)
    const installed = executable(binDir, 'cursor-agent')
    process.env.HARNESS_ENGINE_TEST_PATH = '/usr/bin:/bin'
    const recipe: EngineInstallRecipe = {
      command: 'false',
      source: 'test fixture',
      executable: { names: ['cursor-agent'], absolutePaths: [installed] },
    }

    await expect(
      commandAvailableInInteractiveShell('cursor-agent', bashProbeShell(), recipe),
    ).resolves.toBe(true)
  })
})

describe('buildEngineLaunchArgv with installFirst', () => {
  // Everything here is about ONE rule: the engine must not be exec'd after an install that failed.
  // Doing so reproduces the `command not found` this feature exists to replace, with a screenful of
  // installer output above it to bury the cause.
  const script = (install: string): string =>
    buildEngineLaunchArgv('opencode', { installFirst: install }, '/bin/zsh')[2]

  it('leaves the plain launch alone when nothing has to be installed', () => {
    expect(buildEngineLaunchArgv('opencode', {}, '/bin/zsh')[2]).toBe(`${RAISE_OPEN_FILES_SH}exec "$@"`)
  })

  it('keeps the engine argv positional, so the shell never re-parses a path or a flag', () => {
    const argv = buildEngineLaunchArgv('opencode', {
      installFirst: 'npm install -g opencode-ai',
      bypassPermission: true,
    }, '/bin/zsh')
    expect(argv.slice(0, 2)).toEqual(['/bin/zsh', '-lic'])
    expect(argv.slice(3)).toEqual(['harness-engine', ...buildEngineCommandArgv('opencode', { bypassPermission: true })])
    expect(argv[2]).toContain('exec "$@"')
  })

  it('runs the engine only when the install succeeded', async () => {
    await expect(runPaneScript(script('true'))).resolves.toMatchObject({ code: 0, ranEngine: true })
  })

  it('does not run the engine when the install returns a failure', async () => {
    const result = await runPaneScript(script('false'))
    expect(result.ranEngine).toBe(false)
    expect(result.code).toBe(1)
    expect(result.stdout).toContain('the install failed')
  })

  it('does not run the engine when the install command is not there at all', async () => {
    const result = await runPaneScript(script('harness-no-such-installer --please'))
    expect(result.ranEngine).toBe(false)
    expect(result.code).toBe(1)
  })

  it('prints the command before running it, so a long install is not a hung pane', () => {
    expect(script('npm install -g opencode-ai')).toContain('npm install -g opencode-ai')
  })

  it("survives an install line carrying a quote, rather than ending the shell's string", async () => {
    // `curl … | bash` is already in the table; a quoted argument is the next shape to arrive, and an
    // install line is a constant in our own source — so the failure mode is a broken pane, not an
    // injection. It still must not break.
    const result = await runPaneScript(script(`sh -c 'exit 3'`))
    expect(result.ranEngine).toBe(false)
    expect(result.code).toBe(1)
  })
})

describe('buildEngineLaunchArgv with installIfMissing', () => {
  const recipe = (
    command: string,
    executable: EngineInstallRecipe['executable'] = { names: ['harness-no-such-engine'] },
  ): EngineInstallRecipe => ({ command, source: 'test fixture', executable })
  const script = (install: EngineInstallRecipe, runtimeNode?: string): string =>
    buildEngineLaunchArgv('opencode', { installIfMissing: install }, '/bin/zsh', runtimeNode)[2]

  it('execs an installed engine without running the installer', async () => {
    await expect(runPaneScript(script(recipe('false')))).resolves.toMatchObject({ code: 0, ranEngine: true })
  })

  it('runs the installer inside the pane when the engine is absent', async () => {
    const result = await runPaneScript(script(recipe('false')), 'harness-no-such-engine')
    expect(result.ranEngine).toBe(false)
    expect(result.code).toBe(1)
    expect(result.stdout).toContain('engine is missing')
  })

  it('execs a vendor path after install even when the current PATH did not reload', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'harness-engine-installed-'))
    dirs.push(dir)
    const source = join(dir, 'source-engine')
    const installed = join(dir, 'new-engine')
    writeFileSync(source, '#!/bin/sh\n/usr/bin/printf "%s" "$1"\n')
    chmodSync(source, 0o700)
    const install = `cp ${JSON.stringify(source)} ${JSON.stringify(installed)}`
    const result = await runPaneScript(
      script(recipe(install, { names: ['harness-no-such-engine'], absolutePaths: [installed] })),
      'harness-no-such-engine',
    )
    expect(result).toMatchObject({ code: 0, ranEngine: true })
  })

  it('reports a successful install that did not provide an executable', async () => {
    const result = await runPaneScript(script(recipe('true')), 'harness-no-such-engine')
    expect(result).toMatchObject({ code: 1, ranEngine: false })
    expect(result.stdout).toContain('install completed, but its executable could not be found')
  })

  it('enables npm from the managed Node runtime when the pane PATH has no npm', async () => {
    const runtimeBin = mkdtempSync(join(tmpdir(), 'harness-managed-node-bin-'))
    const emptyPath = mkdtempSync(join(tmpdir(), 'harness-empty-path-'))
    dirs.push(runtimeBin, emptyPath)
    const runtimeNode = executable(runtimeBin, 'node')
    const engineSource = join(runtimeBin, 'engine-source')
    writeFileSync(engineSource, '#!/bin/sh\n/usr/bin/printf "HARNESS-TEST-ENGINE-RAN\\n"\n')
    chmodSync(engineSource, 0o700)
    const installed = join(runtimeBin, 'installed-engine')
    const npm = join(runtimeBin, 'npm')
    writeFileSync(npm, `#!/bin/sh
if [ "$1" = prefix ]; then exit 0; fi
/bin/cp ${JSON.stringify(engineSource)} ${JSON.stringify(installed)}
/bin/chmod 700 ${JSON.stringify(installed)}
`)
    chmodSync(npm, 0o700)

    const result = await runPaneScript(
      script(recipe('npm install -g fixture', {
        names: ['harness-no-such-engine'],
        absolutePaths: [installed],
        npmGlobal: true,
      }), runtimeNode),
      'harness-no-such-engine',
      { PATH: emptyPath },
    )

    expect(result).toMatchObject({ code: 0, ranEngine: true })
    expect(result.stdout).toContain('enabling Harness managed Node.js/npm')
  })

  it('does not add the npm bootstrap to non-npm installers', () => {
    expect(script(recipe('true'))).not.toContain('managed Node.js/npm')
  })
})

/** Run one generated pane script under /bin/sh and report what it did. */
async function runPaneScript(
  paneScript: string,
  command = '/usr/bin/printf',
  env: NodeJS.ProcessEnv = process.env,
): Promise<{ code: number; stdout: string; ranEngine: boolean }> {
  const { execFile } = await import('node:child_process')
  const marker = 'HARNESS-TEST-ENGINE-RAN'
  return await new Promise((resolve) => {
    execFile(
      '/bin/sh',
      ['-c', paneScript, 'harness-engine', command, `${marker}\n`],
      { timeout: 10_000, env },
      (error, stdout) => {
        const code = error && typeof (error as { code?: unknown }).code === 'number'
          ? (error as unknown as { code: number }).code
          : 0
        resolve({ code, stdout, ranEngine: stdout.includes(marker) })
      },
    )
  })
}
