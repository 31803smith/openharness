import { models as examples, type Model } from './demo';

export type AccessMethod = 'subscription' | 'api' | 'local' | 'shared';
export type ModelConnection = {
  id: string;
  name: string;
  method: AccessMethod;
  models: Model[];
};
export type ConnectionInput = {
  method: AccessMethod;
  provider: string;
  name: string;
  endpoint: string;
  audience: 'team' | 'public';
};

export const subscriptionProviders = [
  { id: 'anthropic', name: 'Anthropic' },
  { id: 'openai', name: 'OpenAI' },
  { id: 'google', name: 'Google' },
];
export const apiProviders = [
  { id: 'deepseek', name: 'DeepSeek' },
  { id: 'anthropic', name: 'Anthropic' },
  { id: 'openai', name: 'OpenAI' },
  { id: 'custom', name: 'Custom endpoint' },
];

export function initialModelAccess(): ModelConnection[] {
  return [
    {
      id: 'subscription:anthropic',
      name: 'Anthropic',
      method: 'subscription',
      models: examples.filter((m) => ['opus', 'fable'].includes(m.id)),
    },
    {
      id: 'subscription:openai',
      name: 'OpenAI',
      method: 'subscription',
      models: examples.filter((m) => m.id === 'astra'),
    },
    {
      id: 'local:this-mac',
      name: 'MacBook Pro',
      method: 'local',
      models: examples.filter((m) => m.id === 'qwen-local'),
    },
  ];
}

function endpointIdentity(value: string): string {
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    throw new Error('Enter a full server or invitation URL.');
  }
  if (!['http:', 'https:'].includes(url.protocol))
    throw new Error('Use an http:// or https:// address.');
  return url.origin + url.pathname.replace(/\/+$/, '');
}

// Only sample catalogs are discovered. Inputs never initiate network requests.
// Account emails and API keys deliberately stay outside connection state.
export function createModelConnection(input: ConnectionInput): ModelConnection {
  let id: string;
  let name: string;
  let names: string[];
  let type: Model['type'];
  if (input.method === 'subscription') {
    const provider = subscriptionProviders.find((p) => p.id === input.provider);
    if (!provider) throw new Error('Choose a subscription provider.');
    id = 'subscription:' + provider.id;
    name = provider.name;
    type = 'Subscription';
    names =
      provider.id === 'anthropic'
        ? ['Opus 5', 'Fable 5']
        : provider.id === 'openai'
          ? ['Astra 6']
          : ['Gemini 2.5 Pro', 'Gemini 2.5 Flash'];
  } else if (input.method === 'api') {
    const provider = apiProviders.find((p) => p.id === input.provider);
    if (!provider) throw new Error('Choose an API provider.');
    const custom = provider.id === 'custom';
    id = 'api:' + (custom ? endpointIdentity(input.endpoint) : provider.id);
    name = custom ? input.name.trim() : provider.name;
    type = 'API';
    names =
      provider.id === 'anthropic'
        ? ['Opus 5', 'Fable 5']
        : provider.id === 'openai'
          ? ['Astra 6']
          : provider.id === 'deepseek'
            ? ['DeepSeek V3', 'DeepSeek R1']
            : ['Qwen3 Coder', 'DeepSeek V3'];
  } else if (input.method === 'local' || input.method === 'shared') {
    id = input.method + ':' + endpointIdentity(input.endpoint);
    name = input.name.trim();
    type = 'Local';
    names =
      input.method === 'local'
        ? ['Qwen3 Coder', 'Qwen3 8B']
        : input.audience === 'team'
          ? ['DeepSeek V3', 'Qwen3 Coder', 'Llama 3.3']
          : ['Llama 3.3', 'Qwen3 Coder'];
  } else {
    throw new Error('Choose a connection method.');
  }
  if (!name) throw new Error('Give this connection a name.');
  return {
    id,
    name,
    method: input.method,
    models: names.map((modelName) => ({
      id: id + ':' + modelName.toLowerCase().replace(/[^a-z0-9]+/g, '-'),
      name: modelName,
      type,
      kind: type === 'Local' ? 'local' : 'cloud',
      source: name,
      detail: 'Illustrative model from a simulated connection',
    })),
  };
}

export function addModelConnection(
  existing: ModelConnection[],
  connection: ModelConnection,
) {
  const previous = existing.find((item) => item.id === connection.id);
  if (previous)
    return { connections: existing, connection: previous, added: false };
  return { connections: [...existing, connection], connection, added: true };
}
