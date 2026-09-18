/** Harness-only RPC extensions. The shared, pinned crypto core remains byte-identical across clients.
 * Both the originating machine relay and receiving daemon use these classifications. Older clients
 * do not send these frames; older targets answer UNSUPPORTED before any command is attempted. */
import { ENCRYPTED_RPC_RESULT_TYPES, isEncryptedDownType } from './core.js'

const FLEET_REQUESTS = new Set(['grid_fleet_capabilities', 'grid_fleet_run', 'grid_fleet_cancel'])
const FLEET_RESULTS = new Set([...FLEET_REQUESTS].map(type => `${type}_result`))
export const encryptDownFrame = (type: string): boolean => isEncryptedDownType(type) || FLEET_REQUESTS.has(type)
export const encryptRpcResult = (type: string): boolean => ENCRYPTED_RPC_RESULT_TYPES.has(type) || FLEET_RESULTS.has(type)
