export type SwarmId = 'workshop' | 'launch' | 'infra';
export type View = 'focus' | 'swarms' | 'question' | 'voice';
export type VoicePhase = 'idle' | 'listening' | 'transcribing' | 'sent';
export type Agent = {
  id: string;
  name: string;
  engine: 'Claude' | 'Codex' | 'Cursor';
  machine: string;
  branch: string;
  activity: string;
  result: string;
  elapsed: string;
  color: string;
} & (
  | { status: 'working' | 'waiting' }
  | { status: 'ready'; completion: readonly [string, string] }
);

export const AGENTS: Record<string, Agent> = {
  storefront: {
    id: 'storefront',
    name: 'Storefront',
    engine: 'Claude',
    machine: 'MacBook Pro',
    branch: 'feat/storefront',
    status: 'working',
    activity: 'Making room for the details.',
    result: 'The new collection is taking shape. Responsive layouts are next.',
    elapsed: '4m 12s',
    color: '#d99772',
  },
  api: {
    id: 'api',
    name: 'The API',
    engine: 'Codex',
    machine: 'Mac mini',
    branch: 'feat/catalog-api',
    status: 'ready',
    completion: ['Three endpoints built.', 'All tests passing.'],
    activity: 'The catalog is ready.',
    result: 'Three endpoints. Every test passing. Ready when you are.',
    elapsed: 'Just finished',
    color: '#b6dfc9',
  },
  tests: {
    id: 'tests',
    name: 'Test suite',
    engine: 'Cursor',
    machine: 'Studio server',
    branch: 'test/checkout',
    status: 'working',
    activity: 'Checking every little thing.',
    result: 'Checkout, shipping, and the happy path. 42 of 48 checks complete.',
    elapsed: '2m 38s',
    color: '#d6c8f3',
  },
  notes: {
    id: 'notes',
    name: 'Release notes',
    engine: 'Claude',
    machine: 'MacBook Pro',
    branch: 'docs/launch',
    status: 'ready',
    completion: ['Launch notes drafted.', 'Key changes documented.'],
    activity: 'A good story, ready to tell.',
    result: 'The launch notes are drafted. All the details, without the noise.',
    elapsed: 'Ready to read',
    color: '#d99772',
  },
  payments: {
    id: 'payments',
    name: 'Payments',
    engine: 'Codex',
    machine: 'Mac mini',
    branch: 'feat/payments',
    status: 'waiting',
    activity: 'One small decision.',
    result: 'Should checkout use the existing Stripe account or a new one?',
    elapsed: 'Needs input',
    color: '#b6dfc9',
  },
  launch: {
    id: 'launch',
    name: 'Launch page',
    engine: 'Claude',
    machine: 'MacBook Pro',
    branch: 'feat/launch',
    status: 'working',
    activity: 'Getting ready for the world.',
    result: 'The page is built. Checking the last few responsive details.',
    elapsed: '6m 04s',
    color: '#d99772',
  },
  deploy: {
    id: 'deploy',
    name: 'Deployment',
    engine: 'Cursor',
    machine: 'Studio server',
    branch: 'ops/preview',
    status: 'ready',
    completion: ['Preview deployed.', 'All health checks pass.'],
    activity: 'Everything is in its place.',
    result: 'The preview is deployed. Health checks are green.',
    elapsed: 'Just finished',
    color: '#d6c8f3',
  },
  observability: {
    id: 'observability',
    name: 'Observability',
    engine: 'Codex',
    machine: 'Studio server',
    branch: 'ops/tracing',
    status: 'working',
    activity: 'Keeping an eye on things.',
    result: 'Traces and dashboards are connected. Watching the first requests.',
    elapsed: '3m 16s',
    color: '#b6dfc9',
  },
};

export const SWARMS: {
  id: SwarmId;
  name: string;
  agents: string[];
  caption: string;
}[] = [
  {
    id: 'workshop',
    name: 'Workshop',
    agents: ['storefront', 'api', 'tests', 'notes'],
    caption: 'A little of everything. All together.',
  },
  {
    id: 'launch',
    name: 'Launch',
    agents: ['payments', 'launch'],
    caption: 'The last mile before the big day.',
  },
  {
    id: 'infra',
    name: 'Infrastructure',
    agents: ['deploy', 'observability'],
    caption: 'Good foundations. Quiet confidence.',
  },
];

export type DemoState = {
  swarm: SwarmId;
  focused: string;
  focusMemory: Record<SwarmId, string>;
  view: View;
  voice: VoicePhase;
  voiceTarget: string | null;
  voiceText: string;
  answered: boolean;
  completionNotice: string | null;
  returnTo: { swarm: SwarmId; focused: string } | null;
  scroll: Record<string, number>;
  scrollLimits: Record<string, number>;
  sentTo: string | null;
  startedAgents: string[];
  announcement: string;
};

export function getAgentStatus(
  state: DemoState,
  agent: Agent,
): Agent['status'] {
  return state.startedAgents?.includes(agent.id) ||
    state.sentTo === agent.id ||
    (state.answered && agent.id === 'payments')
    ? 'working'
    : agent.status;
}

export function visibleAgentIds(state: DemoState): string[] {
  const agents = SWARMS.find((item) => item.id === state.swarm)!.agents;
  const start = Math.floor(agents.indexOf(state.focused) / 2) * 2;
  return agents.slice(start, start + 2);
}

export function initialState(): DemoState {
  return {
    swarm: 'workshop',
    focused: 'storefront',
    focusMemory: {
      workshop: 'storefront',
      launch: 'payments',
      infra: 'deploy',
    },
    view: 'focus',
    voice: 'idle',
    voiceTarget: null,
    voiceText: '',
    answered: false,
    completionNotice: null,
    returnTo: null,
    scroll: {},
    scrollLimits: {},
    sentTo: null,
    startedAgents: [],
    announcement: 'Workshop. Storefront is in focus.',
  };
}

export type DemoAction =
  | { type: 'focus'; agent: string }
  | { type: 'step'; direction: number }
  | { type: 'swarm'; swarm: SwarmId }
  | { type: 'view'; view: View }
  | { type: 'voice-start' }
  | { type: 'voice-text'; text: string }
  | { type: 'voice-transcribe' }
  | { type: 'voice-send' }
  | { type: 'voice-close' }
  | { type: 'inspect-question' }
  | { type: 'completion-notify'; agent: string }
  | { type: 'inspect-completion' }
  | { type: 'answer' }
  | { type: 'return' }
  | { type: 'scroll'; delta: number }
  | { type: 'scroll-position'; agent: string; position: number }
  | { type: 'scroll-limit'; agent: string; limit: number }
  | { type: 'reset' };

function focus(state: DemoState, swarm: SwarmId, agent: string): DemoState {
  const group = SWARMS.find((item) => item.id === swarm);
  if (!group?.agents.includes(agent)) return state;
  return {
    ...state,
    swarm,
    focused: agent,
    focusMemory: { ...state.focusMemory, [swarm]: agent },
    view: state.voice === 'idle' ? 'focus' : 'voice',
    announcement: `${group.name}. ${AGENTS[agent].name} is in focus.`,
  };
}

export function demoReducer(state: DemoState, action: DemoAction): DemoState {
  switch (action.type) {
    case 'focus':
      return focus(state, state.swarm, action.agent);
    case 'step': {
      if (state.voice !== 'idle') return state;
      const group = SWARMS.find((item) => item.id === state.swarm)!;
      const index = group.agents.indexOf(state.focused);
      return focus(
        state,
        state.swarm,
        group.agents[
          (((index + action.direction) % group.agents.length) +
            group.agents.length) %
            group.agents.length
        ],
      );
    }
    case 'swarm':
      return focus(state, action.swarm, state.focusMemory[action.swarm]);
    case 'view':
      return state.voice === 'idle' ? { ...state, view: action.view } : state;
    case 'voice-start':
      return state.voice !== 'idle'
        ? state
        : {
            ...state,
            view: 'voice',
            voice: 'listening',
            voiceTarget: state.focused,
            voiceText: '',
            announcement: `Voice demo. Listening for ${AGENTS[state.focused].name}.`,
          };
    case 'voice-text':
      return state.voice === 'listening'
        ? { ...state, voiceText: action.text }
        : state;
    case 'voice-transcribe':
      return state.voice === 'listening'
        ? {
            ...state,
            voice: 'transcribing',
            voiceText:
              state.voiceText ||
              'Check the layout on mobile before wrapping up.',
            announcement: 'Transcribing your demo message.',
          }
        : state;
    case 'voice-send':
      return state.voice === 'transcribing'
        ? {
            ...state,
            voice: 'sent',
            sentTo: state.voiceTarget,
            completionNotice:
              state.completionNotice === state.voiceTarget
                ? null
                : state.completionNotice,
            startedAgents: [
              ...new Set([
                ...(state.startedAgents ??
                  (state.sentTo ? [state.sentTo] : [])),
                state.voiceTarget!,
              ]),
            ],
            announcement: `Demo message sent to ${AGENTS[state.voiceTarget!].name}.`,
          }
        : state;
    case 'voice-close':
      return { ...state, voice: 'idle', voiceTarget: null, view: 'focus' };
    case 'completion-notify': {
      const agent = AGENTS[action.agent];
      if (!agent || getAgentStatus(state, agent) !== 'ready') return state;
      return {
        ...state,
        completionNotice: agent.id,
        announcement: `${agent.name} finished. Your current agent stays in focus.`,
      };
    }
    case 'inspect-completion': {
      const agent = state.completionNotice && AGENTS[state.completionNotice];
      if (
        !agent ||
        agent.status !== 'ready' ||
        getAgentStatus(state, agent) !== 'ready' ||
        state.voice !== 'idle'
      )
        return state;
      const swarm = SWARMS.find((item) => item.agents.includes(agent.id))!.id;
      return {
        ...focus(state, swarm, agent.id),
        completionNotice: null,
        returnTo:
          state.returnTo ||
          (state.focused === agent.id
            ? null
            : { swarm: state.swarm, focused: state.focused }),
        announcement: `${agent.name}. ${agent.completion.join(' ')}`,
      };
    }
    case 'inspect-question':
      return state.answered || state.voice !== 'idle'
        ? state
        : {
            ...state,
            returnTo: state.returnTo || {
              swarm: state.swarm,
              focused: state.focused,
            },
            swarm: 'launch',
            focused: 'payments',
            focusMemory: { ...state.focusMemory, launch: 'payments' },
            view: 'question',
            announcement:
              'Payments needs a decision. Your previous place is saved.',
          };
    case 'answer':
      return state.view !== 'question'
        ? state
        : {
            ...state,
            answered: true,
            view: 'focus',
            announcement:
              'Payments is using the existing account. You can return to your previous agent.',
          };
    case 'return':
      return state.returnTo
        ? {
            ...focus(
              { ...state, voice: 'idle', voiceTarget: null },
              state.returnTo.swarm,
              state.returnTo.focused,
            ),
            returnTo: null,
            announcement: `Back to ${AGENTS[state.returnTo.focused].name}, right where you left off.`,
          }
        : { ...state, view: 'focus' };
    case 'scroll':
      return {
        ...state,
        scroll: {
          ...state.scroll,
          [state.focused]: Math.max(
            0,
            Math.min(
              state.scrollLimits?.[state.focused] ?? 20,
              (state.scroll[state.focused] || 0) + action.delta,
            ),
          ),
        },
      };
    case 'scroll-position':
      return !AGENTS[action.agent] ||
        Math.abs((state.scroll[action.agent] || 0) - action.position) < 0.01
        ? state
        : {
            ...state,
            scroll: {
              ...state.scroll,
              [action.agent]: Math.max(
                0,
                Math.min(
                  state.scrollLimits?.[action.agent] ?? 20,
                  action.position,
                ),
              ),
            },
          };
    case 'scroll-limit': {
      if (!AGENTS[action.agent] || !Number.isFinite(action.limit)) return state;
      const limit = Math.max(0, action.limit);
      const position = Math.min(state.scroll[action.agent] || 0, limit);
      if (
        Math.abs((state.scrollLimits?.[action.agent] ?? -1) - limit) < 0.01 &&
        position === (state.scroll[action.agent] || 0)
      )
        return state;
      return {
        ...state,
        scrollLimits: { ...state.scrollLimits, [action.agent]: limit },
        scroll: { ...state.scroll, [action.agent]: position },
      };
    }
    case 'reset':
      return initialState();
  }
}
