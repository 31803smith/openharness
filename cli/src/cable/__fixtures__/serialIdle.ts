// Runs in a separate process with ONE libuv worker. An idle blocking tty read would prevent
// both DNS and file I/O from completing, even though the event loop and existing sockets work.
import assert from 'node:assert/strict'
import { lookup } from 'node:dns/promises'
import { stat } from 'node:fs/promises'
import { createServer } from 'node:http'
import { SerialLink } from '../serial.js'

const server = createServer((_req, res) => res.end('ok'))
await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
const address = server.address() as { port: number }
const limit = <T>(work: Promise<T>) => Promise.race([
  work,
  new Promise<never>((_, reject) => setTimeout(() => reject(new Error('I/O blocked by idle serial port')), 1_000).unref()),
])

try {
  for (let i = 0; i < 8; i++) {
    let closed = 0
    const link = await SerialLink.open(process.argv[2]!, () => {}, () => closed++)
    await new Promise((resolve) => setTimeout(resolve, 20))
    await limit(Promise.all([
      lookup('localhost'),
      stat(process.execPath),
      fetch(`http://localhost:${address.port}`, { signal: AbortSignal.timeout(2_000) }).then((res) => res.text()),
    ]))
    await limit(Promise.all([link.close('silence'), link.close('silence')]))
    assert.equal(closed, 1)
    assert.equal(link.isOpen, false)
  }
  process.stdout.write('8 idle reopen cycles: DNS, HTTP, file I/O and close succeeded\n')
  process.exit(0)
} catch (error) {
  console.error(error)
  // The regression leaves a native read blocked forever; let the parent test finish in that case.
  process.exit(1)
}
