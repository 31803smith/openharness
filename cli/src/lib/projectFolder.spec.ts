import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { parseProjectFolder, prepareProjectFolder, ProjectFolderError } from './projectFolder.js'

describe('project folder preparation', () => {
  let root: string
  beforeEach(async () => { root = await mkdtemp(join(tmpdir(), 'harness-project-test-')) })
  afterEach(async () => { await rm(root, { recursive: true, force: true }) })

  it('accepts the existing GitHub forms and rejects credentials, helpers and ambiguous source choices', () => {
    expect(parseProjectFolder({})).toBeNull()
    expect(parseProjectFolder({ projectSource: 'new' })).toEqual({ source: 'new' })
    for (const url of ['owner/repo', 'https://github.com/owner/repo.git', 'git@github.com:owner/repo']) {
      expect(parseProjectFolder({ projectSource: 'remote', repositoryUrl: url })).toMatchObject({ source: 'remote', name: 'repo' })
    }
    for (const url of ['ext::bad', '/tmp/repo', '--upload-pack=bad', 'https://user:secret@github.com/owner/repo', 'owner/repo;command', 'https://github.com/owner/repo?token=secret']) {
      expect(() => parseProjectFolder({ projectSource: 'remote', repositoryUrl: url })).toThrow(ProjectFolderError)
    }
    expect(() => parseProjectFolder({ projectSource: 'new', repositoryUrl: 'owner/repo' })).toThrow(ProjectFolderError)
  })

  it('creates different folders for two deliberate new projects', async () => {
    const folders = await Promise.all([prepareProjectFolder({ source: 'new' }, { root }), prepareProjectFolder({ source: 'new' }, { root })])
    expect(new Set(folders).size).toBe(2)
    expect(new Set(folders)).toEqual(new Set([join(root, 'harness-1'), join(root, 'harness-2')]))
    expect(await readdir(root)).toHaveLength(2)
  })

  it('continues numbering past existing folders and files without changing them', async () => {
    await mkdir(join(root, 'agent-2'))
    await writeFile(join(root, 'agent-4'), 'keep')
    expect(await prepareProjectFolder({ source: 'new' }, { root })).toBe(join(root, 'harness-5'))
    expect(await readFile(join(root, 'agent-4'), 'utf8')).toBe('keep')
  })

  it('publishes a complete clone and never replaces existing files or starts a second clone', async () => {
    const project = parseProjectFolder({ projectSource: 'remote', repositoryUrl: 'owner/repo' })!
    const clone = vi.fn(async (url: string, destination: string) => {
      expect(url).toBe('https://github.com/owner/repo.git')
      await mkdir(destination)
      await writeFile(join(destination, 'README.md'), 'saved checkout')
    })
    const folder = await prepareProjectFolder(project, { root, clone })
    expect(folder).toBe(join(root, 'repo'))
    expect(await readFile(join(folder, 'README.md'), 'utf8')).toBe('saved checkout')
    expect(await readdir(root)).toEqual(['repo'])
    await expect(prepareProjectFolder(project, { root, clone })).rejects.toMatchObject({ code: 'PROJECT_EXISTS' })
    expect(clone).toHaveBeenCalledTimes(1)
    expect(await readFile(join(folder, 'README.md'), 'utf8')).toBe('saved checkout')
  })

  it('cleans only its private staging on failure and preserves a concurrently created destination', async () => {
    const project = parseProjectFolder({ projectSource: 'remote', repositoryUrl: 'owner/repo' })!
    await expect(prepareProjectFolder(project, { root, clone: async (_, destination) => {
      await mkdir(destination)
      throw new ProjectFolderError('CLONE_FAILED', 'Could not clone')
    } })).rejects.toMatchObject({ code: 'CLONE_FAILED' })
    expect(await readdir(root)).toEqual([])
    await expect(prepareProjectFolder(project, { root, clone: async (_, destination) => {
      await mkdir(destination)
      await mkdir(join(root, 'repo'))
      await writeFile(join(root, 'repo', 'draft'), 'keep me')
    } })).rejects.toMatchObject({ code: 'PROJECT_EXISTS' })
    expect(await readFile(join(root, 'repo', 'draft'), 'utf8')).toBe('keep me')
    expect(await readdir(root)).toEqual(['repo'])
  })
})
