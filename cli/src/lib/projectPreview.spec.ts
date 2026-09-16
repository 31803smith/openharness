import { execFile } from 'node:child_process'
import { mkdtemp, readFile, rm, symlink, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { promisify } from 'node:util'
import { afterEach, beforeEach, expect, it } from 'vitest'
import { env } from '../config/env.js'
import { ENCRYPTED_DOWN_TYPES, ENCRYPTED_RPC_RESULT_TYPES } from './e2ee/core.js'
import { projectPreview } from './projectPreview.js'

const exec = promisify(execFile)
let root: string
const unrestricted = env.HARNESS_FS_BROWSE_UNRESTRICTED
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'harness-preview-'))
  env.HARNESS_FS_BROWSE_UNRESTRICTED = undefined
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
  env.HARNESS_FS_BROWSE_UNRESTRICTED = unrestricted
})
const git = (args: string[]) => exec('git', ['-C', root, ...args])

it('previews existing Git content without running a configured fsmonitor hook', async () => {
  await git(['init', '-b', 'preview'])
  await writeFile(join(root, 'README.md'), '# Project\nExisting content')
  await git(['add', 'README.md'])
  await git(['-c', 'user.name=Preview Author', '-c', 'user.email=preview@example.invalid', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-m', 'First commit'])
  await writeFile(join(root, 'README.md'), '# Project\nUpdated content')
  await git(['config', 'core.fsmonitor', `touch ${join(root, 'monitor-ran')}`])
  expect(await projectPreview(root, [root])).toMatchObject({
    readme: '# Project\nUpdated content', branch: 'preview', changedFiles: 1,
    commit: { subject: 'First commit', author: 'Preview Author' }, contributors: ['Preview Author'],
  })
  await expect(readFile(join(root, 'monitor-ran'))).rejects.toMatchObject({ code: 'ENOENT' })
})

it('bounds README reads and does not follow README symlinks', async () => {
  const readme = join(root, 'README.md')
  await writeFile(readme, 'a'.repeat(40000))
  const preview = await projectPreview(root, [root])
  expect('readme' in preview && preview.readme?.length).toBe(32768)
  await rm(readme)
  await writeFile(join(root, 'private.txt'), 'private')
  await symlink(join(root, 'private.txt'), readme)
  expect(await projectPreview(root, [root])).not.toHaveProperty('readme', 'private')
})

it('rejects unscoped paths and keeps remote content inside the encrypted RPC', async () => {
  expect(await projectPreview(root)).toEqual({ error: 'FORBIDDEN' })
  expect(await projectPreview('relative')).toEqual({ error: 'INVALID_PATH' })
  expect(await projectPreview(`${root}\n`, [root])).toEqual({ error: 'INVALID_PATH' })
  expect(ENCRYPTED_DOWN_TYPES.has('project_preview')).toBe(true)
  expect(ENCRYPTED_RPC_RESULT_TYPES.has('project_preview_result')).toBe(true)
})
