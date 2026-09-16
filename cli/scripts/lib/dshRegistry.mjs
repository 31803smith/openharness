// Read `dsh/registry/<owner>/<name>.json` for the build's `__DSH_REGISTRY__` define. Mirrors
// `readRegistryDir` in src/dsh/registry.ts (the runtime dev fallback); kept in plain ESM so both
// build scripts can import it without a TypeScript step.
import { readdirSync, readFileSync, statSync } from 'fs'
import { join } from 'path'
import { fileURLToPath } from 'url'

export function readDshRegistry(dir) {
  const root = dir instanceof URL ? fileURLToPath(dir) : dir
  const out = []
  let owners
  try { owners = readdirSync(root) } catch { return out }
  for (const owner of owners) {
    const ownerDir = join(root, owner)
    let files
    try {
      if (!statSync(ownerDir).isDirectory()) continue
      files = readdirSync(ownerDir)
    } catch { continue }
    for (const file of files) {
      if (!file.endsWith('.json')) continue
      out.push(JSON.parse(readFileSync(join(ownerDir, file), 'utf8')))
    }
  }
  return out
}
