import { afterEach, describe, expect, it } from 'vitest'
import { dshShellArgv } from './shell.js'

describe('dshShellArgv', () => {
  const original = process.env.SHELL
  afterEach(() => { if (original === undefined) delete process.env.SHELL; else process.env.SHELL = original })

  it('runs a bash user\'s setup and doctor as a LOGIN shell, where .bash_profile (and nvm) live', () => {
    process.env.SHELL = '/bin/bash'
    expect(dshShellArgv('./doctor.sh')).toEqual({ path: '/bin/bash', args: ['-lic', './doctor.sh'] })
  })

  it('keeps zsh as it already was', () => {
    process.env.SHELL = '/bin/zsh'
    expect(dshShellArgv('./doctor.sh')).toEqual({ path: '/bin/zsh', args: ['-lic', './doctor.sh'] })
  })
})
