export type HeroStatus = 'working' | 'ready' | 'waiting';

export type HeroSession = {
  agent: string;
  machine: string;
  folder: string;
  branch: string;
  status: HeroStatus;
  completion?: readonly [string, string];
  seconds: number;
  cadence: number;
  lines: string[];
};

const lines = (value: string) => value.trim().split('\n');

export const HERO_MACHINES = [
  { id: 'macbook', name: 'MacBook Pro', location: 'Local' },
  { id: 'mini', name: 'Mac mini', location: 'Home' },
  { id: 'studio', name: 'Linux workstation', location: 'Office' },
  { id: 'cloud', name: 'Build server', location: 'Cloud' },
];

export const HERO_SESSIONS: HeroSession[] = [
  {
    agent: 'storefront',
    machine: 'macbook',
    folder: '~/work/storefront',
    branch: 'feat/collection',
    status: 'working',
    seconds: 252,
    cadence: 1650,
    lines: lines(`❯ Finish the collection page and check mobile.

⏺ Read app/collection/page.tsx
⏺ Read components/product-card.tsx
  Found the existing collection layout.

⏺ Update components/product-card.tsx
  @@ export function ProductCard({ product })
-   className="grid grid-cols-4 gap-8"
+   className="grid grid-cols-2 gap-4 lg:grid-cols-4"
    return products.map(renderProduct);

⏺ Bash npm run test -- product-card
  PASS components/product-card.test.tsx
  12 tests passed · 0 failures

⏺ Read styles/collection.css
+ .collection { container-type: inline-size; }
+ @container (max-width: 640px) {
+   .product-grid { gap: 16px; }
+ }

⏺ Bash npm run build
  Compiled successfully in 2.4s
  Checking the tablet and mobile breakpoints…
  /collection       4.2 kB     96 kB
⏺ Bash git diff --stat
  3 files changed, 64 insertions(+), 21 deletions(-)
  Reviewing the responsive layout…`),
  },
  {
    agent: 'api',
    machine: 'mini',
    folder: '~/services/catalog',
    branch: 'feat/catalog-cache',
    status: 'working',
    completion: ['Catalog cache added.', 'All tests passing.'],
    seconds: 198,
    cadence: 2150,
    lines: lines(`› Add caching to the catalog endpoints.

• Read src/routes/catalog.ts
• Read src/cache/redis.ts
  Existing cache client is connected.

• Update src/routes/catalog.ts
+ const key = catalogKey({ page, category });
+ const cached = await cache.get(key);
+ if (cached) return json(cached);
  const products = await catalog.list(query);
+ await cache.set(key, products, { ttl: 60 });

• Run pnpm test catalog
  PASS GET /catalog returns products
  PASS cache hit skips the database
  PASS expired entries are refreshed
  18 tests passed in 1.82s

• Run pnpm typecheck
  Found 0 errors.

• Read src/middleware/timing.ts
  p50  12ms   p95  34ms   p99  61ms
  Cache hit rate: 94.6%
• Run git diff --check
  Reviewing invalidation on product updates…`),
  },
  {
    agent: 'tests',
    machine: 'cloud',
    folder: '/srv/checkout',
    branch: 'test/checkout',
    status: 'working',
    seconds: 96,
    cadence: 1300,
    lines: lines(`❯ Run the checkout suite across browsers.

$ pnpm exec playwright test
  Running 48 tests using 4 workers

  ✓ cart › add an item                 812ms
  ✓ cart › update quantity             640ms
  ✓ cart › remove an item              502ms
  ✓ checkout › saved address           1.2s
  ✓ checkout › shipping estimate       944ms
  ✓ checkout › discount code           682ms

  chromium  16 / 16 passed
  firefox   16 / 16 passed
  webkit    10 / 16 running

  ✓ payment › valid card               1.4s
  ✓ payment › expired card             1.1s
  ✓ payment › retry after decline      962ms
  ✓ mobile › address form              734ms
  ✓ mobile › order summary             608ms
  ✓ mobile › confirmation              883ms

  48 passed (38.4s)
  Report saved to playwright-report/
$ pnpm exec playwright test --project=mobile
  Checking the small-screen checkout flow…`),
  },
  {
    agent: 'payments',
    machine: 'studio',
    folder: '~/work/checkout',
    branch: 'feat/payments',
    status: 'waiting',
    seconds: 374,
    cadence: 0,
    lines: lines(`› Connect checkout to Stripe.

• Read src/payments/checkout.ts
• Read src/payments/webhooks.ts
• Read .env.example

  Checkout and webhook handlers are ready.
  The existing account has test keys configured.

  src/payments/checkout.ts       +42 −8
  src/payments/webhooks.ts       +31 −4
  tests/payments.test.ts         +68

  24 tests passing.

? Use the existing Stripe account?
  Waiting for your decision to continue.

  Use existing account     Set up a new account`),
  },
  {
    agent: 'deploy',
    machine: 'cloud',
    folder: '/srv/preview',
    branch: 'ops/preview',
    status: 'ready',
    completion: ['Preview deployed.', 'All health checks pass.'],
    seconds: 63,
    cadence: 0,
    lines: lines(`❯ Deploy the preview and check its health.

$ docker build -t storefront:preview .
  [1/4] Install dependencies       CACHED
  [2/4] Compile application       4.2s
  [3/4] Collect static assets     1.1s
  [4/4] Export image              0.8s

$ ./deploy preview
  Uploaded 142 assets
  Rolling out release 8b3f1a2
  Health check: /health           200 OK
  Health check: /catalog          200 OK
  Health check: /checkout         200 OK

  Deployment complete.
  All health checks passing.

  Preview is ready for review.`),
  },
  {
    agent: 'observability',
    machine: 'mini',
    folder: '~/services/telemetry',
    branch: 'ops/tracing',
    status: 'working',
    seconds: 136,
    cadence: 2850,
    lines: lines(`› Check request traces after the rollout.

• Read src/tracing.ts
• Run node scripts/check-traces.mjs
  Connected to the metrics collector.

  14:32:01  GET /catalog       200   18ms
  14:32:02  GET /products/42   200   12ms
  14:32:03  POST /cart         201   26ms
  14:32:04  GET /checkout      200   31ms
  14:32:05  POST /checkout     200   84ms

  Requests/min     1,284
  Error rate       0.02%
  p95 latency      34ms
  Cache hit rate   94.6%

• Read dashboards/overview.json
+ "title": "Catalog response time"
+ "query": "http_request_duration_seconds"

  Dashboard updated.
  No regression detected after the rollout.
• Run node scripts/watch-health.mjs
  Watching the next batch of requests…`),
  },
];

// One timeline owns focus, output, and status on both physical screens.
// Finishing work changes its status without moving focus to another agent.
const HERO_SCENES = [
  { focused: 'api', duration: 6000 },
  { focused: 'api', duration: 4500 },
  { focused: 'storefront', duration: 6000 },
  { focused: 'tests', duration: 6000 },
  { focused: 'payments', duration: 6000 },
  { focused: 'deploy', duration: 6000 },
  { focused: 'observability', duration: 6000 },
] as const;

const API_COMPLETE_AT = HERO_SCENES[0].duration;
export const HERO_LOOP_MS = HERO_SCENES.reduce(
  (total, scene) => total + scene.duration,
  0,
);

export type HeroSessionFrame = {
  session: HeroSession;
  status: HeroStatus;
  outputTick: number;
  seconds: number;
};

export function getHeroFrame(elapsedMs: number) {
  const elapsed = Number.isFinite(elapsedMs) ? Math.max(0, elapsedMs) : 0;
  const cycleTime = elapsed % HERO_LOOP_MS;
  let phase = 0;
  let phaseTime = cycleTime;
  while (phaseTime >= HERO_SCENES[phase].duration) {
    phaseTime -= HERO_SCENES[phase].duration;
    phase += 1;
  }

  const sessions: HeroSessionFrame[] = HERO_SESSIONS.map((session) => {
    const finished = session.agent === 'api' && cycleTime >= API_COMPLETE_AT;
    const activeTime =
      session.status !== 'working' ? 0 : finished ? API_COMPLETE_AT : cycleTime;
    return {
      session,
      status: finished ? 'ready' : session.status,
      outputTick: session.cadence
        ? Math.floor(activeTime / session.cadence)
        : 0,
      seconds: session.seconds + Math.floor(activeTime / 1000),
    };
  });

  return {
    sessions,
    focused: sessions.find(
      (frame) => frame.session.agent === HERO_SCENES[phase].focused,
    )!,
  };
}
