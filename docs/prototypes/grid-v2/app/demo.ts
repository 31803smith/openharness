export type GridId = 'private' | 'team' | 'public';
export type Connections = Record<GridId, boolean>;
export type Model = {
  id: string;
  name: string;
  type: 'Subscription' | 'API' | 'Local';
  kind: 'cloud' | 'local' | 'grid';
  source: string;
  detail: string;
  gridId?: GridId;
};
export type Turn = {
  id: number;
  modelId: string;
  prompt?: string;
  text: string;
};
export type Agent = {
  id: string;
  name: string;
  project: string;
  branch: string;
  engine: string;
  computer: string;
  folder: string;
  defaultModelId: string;
  modelId: string;
  task: string;
  files: string[];
  turns: Turn[];
  nextTurn: number;
  pendingRequest?: string;
};
export const grids: {
  id: GridId;
  name: string;
  kind: string;
  access: string;
}[] = [
  {
    id: 'private',
    name: 'My computers',
    kind: 'Private',
    access: 'Your Mac Studio and Mac mini',
  },
  {
    id: 'team',
    name: 'Autonomous.ai',
    kind: 'Team',
    access: 'Employee account · dee@autonomous.ai',
  },
  {
    id: 'public',
    name: 'Omagrid',
    kind: 'Public',
    access: 'Open community · Anyone can join',
  },
];
export function initialConnections(): Connections {
  return { private: true, team: true, public: true };
}

// Illustrative choices, not a live catalog or an adapter compatibility claim.
export const models: Model[] = [
  {
    id: 'opus',
    name: 'Opus 5',
    type: 'Subscription',
    kind: 'cloud',
    source: 'Anthropic',
    detail: 'Uses cloud allowance',
  },
  {
    id: 'astra',
    name: 'Astra 6',
    type: 'Subscription',
    kind: 'cloud',
    source: 'OpenAI',
    detail: 'Uses cloud allowance',
  },
  {
    id: 'fable',
    name: 'Fable 5',
    type: 'Subscription',
    kind: 'cloud',
    source: 'Anthropic',
    detail: 'Uses cloud allowance',
  },
  {
    id: 'deepseek-api',
    name: 'DeepSeek V3',
    type: 'API',
    kind: 'cloud',
    source: 'DeepSeek',
    detail: 'DeepSeek API · Separate API billing',
  },
  {
    id: 'qwen-local',
    name: 'Qwen3 8B',
    type: 'Local',
    kind: 'local',
    source: 'MacBook Pro',
    detail: 'Local model · Keeps cloud allowance',
  },
  {
    id: 'qwen-private',
    name: 'Qwen3 Coder',
    type: 'Local',
    kind: 'grid',
    source: 'Mac Studio',
    detail: 'Private · Mac Studio',
    gridId: 'private',
  },
  {
    id: 'deepseek-team',
    name: 'DeepSeek V3',
    type: 'Local',
    kind: 'grid',
    source: 'Autonomous.ai GPUs',
    detail: 'Autonomous.ai · Self-hosted',
    gridId: 'team',
  },
  {
    id: 'llama-public',
    name: 'Llama 3.3',
    type: 'Local',
    kind: 'grid',
    source: 'Omagrid',
    detail: 'Public · Community providers receive requests',
    gridId: 'public',
  },
];
export const seedAgents: Agent[] = [
  {
    id: 'store',
    name: 'Build the storefront',
    project: 'storefront',
    branch: 'keyboard-nav',
    engine: 'OpenCode',
    computer: 'MacBook Pro M2',
    folder: '~/code/storefront',
    defaultModelId: 'opus',
    modelId: 'opus',
    task: 'Add keyboard navigation to the product gallery.',
    files: ['src/components/Gallery.tsx', 'src/styles/gallery.css'],
    turns: [
      {
        id: 1,
        modelId: 'opus',
        text: 'Arrow-key navigation is in place. Ready to check focus order and edge cases.',
      },
    ],
    nextTurn: 2,
  },
  {
    id: 'api',
    name: 'Review the API',
    project: 'catalog-api',
    branch: 'pagination',
    engine: 'Pi',
    computer: 'Dev server',
    folder: '~/services/catalog',
    defaultModelId: 'astra',
    modelId: 'astra',
    task: 'Review the pagination changes for edge cases.',
    files: ['routes/products.ts', 'tests/pagination.test.ts'],
    turns: [
      {
        id: 1,
        modelId: 'astra',
        text: 'Found an empty-page case to check. The cursor handling needs one more pass.',
      },
    ],
    nextTurn: 2,
  },
  {
    id: 'notes',
    name: 'Write release notes',
    project: 'storefront',
    branch: 'release-notes',
    engine: 'Hermes',
    computer: 'MacBook Pro',
    folder: '~/code/storefront',
    defaultModelId: 'fable',
    modelId: 'fable',
    task: 'Draft a short release note from the sample changes.',
    files: ['CHANGELOG.md'],
    turns: [
      {
        id: 1,
        modelId: 'fable',
        text: 'Draft: Navigate the product gallery with your keyboard. Clearer empty states make browsing easier.',
      },
    ],
    nextTurn: 2,
  },
];
export function getModel(id: string, catalog: Model[] = models): Model {
  const model = catalog.find((m) => m.id === id);
  if (!model) throw new Error('Unknown model.');
  return model;
}
export function unavailableReason(
  modelId: string,
  opusLimited: boolean,
  connections: Connections,
  catalog: Model[] = models,
): string | null {
  const model = getModel(modelId, catalog);
  if (modelId === 'opus' && opusLimited) return 'Cloud limit reached';
  if (model.gridId && !connections[model.gridId])
    return 'Disconnected from ' + model.source;
  return null;
}
export function initialAgents(): Agent[] {
  return seedAgents.map((agent) => ({
    ...agent,
    files: [...agent.files],
    turns: agent.turns.map((t) => ({ ...t })),
  }));
}
export function changeAgentModel(
  agents: Agent[],
  agentId: string,
  modelId: string,
  opusLimited: boolean,
  connections: Connections,
  catalog: Model[] = models,
) {
  getModel(modelId, catalog);
  if (!agents.some((a) => a.id === agentId)) throw new Error('Unknown agent.');
  const reason = unavailableReason(modelId, opusLimited, connections, catalog);
  if (reason) throw new Error(reason + '. Choose an available model.');
  return agents.map((agent) =>
    agent.id === agentId ? { ...agent, modelId } : agent,
  );
}
export function sendMessage(
  agents: Agent[],
  agentId: string,
  message: string,
  opusLimited: boolean,
  connections: Connections,
  catalog: Model[] = models,
) {
  const agent = agents.find((a) => a.id === agentId);
  if (!agent) throw new Error('Unknown agent.');
  const reason = unavailableReason(
    agent.modelId,
    opusLimited,
    connections,
    catalog,
  );
  if (reason) throw new Error(reason + '. Choose an available model.');
  const prompt = message.trim();
  if (!prompt) throw new Error('Enter a message.');
  const turn = {
    id: agent.nextTurn,
    modelId: agent.modelId,
    prompt,
    text:
      'Sample reply: continuing this task with ' +
      getModel(agent.modelId, catalog).name +
      '. The earlier conversation is still here.',
  };
  return agents.map((a) =>
    a.id === agentId
      ? {
          ...a,
          turns: [...a.turns, turn],
          nextTurn: a.nextTurn + 1,
          pendingRequest: undefined,
        }
      : a,
  );
}

export function resumeAgent(
  agents: Agent[],
  agentId: string,
  modelId: string,
  opusLimited: boolean,
  connections: Connections,
) {
  const agent = agents.find((a) => a.id === agentId);
  if (!agent?.pendingRequest) throw new Error('This agent has no paused step.');
  const next = changeAgentModel(
    agents,
    agentId,
    modelId,
    opusLimited,
    connections,
  );
  return sendMessage(
    next,
    agentId,
    agent.pendingRequest,
    opusLimited,
    connections,
  );
}
