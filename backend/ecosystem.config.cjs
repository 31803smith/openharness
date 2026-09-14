module.exports = {
  apps: [
    {
      name: 'backend-worker',
      script: 'dist/worker.js',
      exec_mode: 'fork',
      instances: 1,
      wait_ready: true,
      listen_timeout: 120000,
      kill_timeout: 6000,
      env: { NODE_ENV: 'production' },
    },
    {
      name: 'backend',
      script: 'dist/server.js',
      exec_mode: 'cluster',
      instances: 'max',
      // Shutdown drains websockets (1012) before exit — give it room: 4s close grace + Redis quit.
      kill_timeout: 10000,
      // Each cluster worker has its own V8 heap, so the container's memory limit must cover
      // instances × heap (plus ~50% for buffers / native). Without an explicit ceiling V8 sizes the old
      // space from the HOST's RAM, and a leak on one worker surfaces as the OOM-killer taking the whole pod
      // instead of pm2 recycling one process. BACKEND_HEAP_MB / BACKEND_MAX_MEMORY tune both together.
      node_args: `--max-old-space-size=${process.env.BACKEND_HEAP_MB || 1024}`,
      max_memory_restart: process.env.BACKEND_MAX_MEMORY || '1536M',
      env: { NODE_ENV: 'production' },
    },
  ],
}
