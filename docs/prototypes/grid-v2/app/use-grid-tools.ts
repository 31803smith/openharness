'use client';

import { useEffect, useLayoutEffect, useRef } from 'react';
import { flushSync } from 'react-dom';

type Tool = {
  name: string;
  title: string;
  description: string;
  inputSchema: object;
  annotations: { readOnlyHint: boolean; untrustedContentHint: boolean };
  execute: (input: unknown) => unknown;
};
type ToolDocument = Document & {
  modelContext?: {
    registerTool: (
      tool: Tool,
      options: { signal: AbortSignal },
    ) => void | Promise<void>;
  };
};

// An optional second entry point into the same simulated state and actions.
export function useGridTools(
  read: () => unknown,
  change: (input: unknown) => unknown,
) {
  const actions = useRef({ read, change });
  useLayoutEffect(() => {
    actions.current = { read, change };
  });
  useEffect(() => {
    const context = (document as ToolDocument).modelContext;
    if (!context?.registerTool) return;
    const lifecycle = new AbortController();
    const tools: Tool[] = [
      {
        name: 'get_grid_study',
        title: 'Read the Grid prototype',
        description:
          'Read the sample terminal panes and model catalog, including each model’s inference provider. No live computers are connected.',
        inputSchema: {
          type: 'object',
          properties: {},
          additionalProperties: false,
        },
        annotations: { readOnlyHint: true, untrustedContentHint: false },
        execute(input) {
          if (
            !input ||
            typeof input !== 'object' ||
            Array.isArray(input) ||
            Object.keys(input).length
          )
            throw new Error('Expected an empty object.');
          return actions.current.read();
        },
      },
      {
        name: 'set_agent_model',
        title: 'Choose a sample agent’s model',
        description:
          'Set the model for one agent’s next reply. Its task and previous replies remain. The model stays selected until explicitly changed. Simulation only.',
        inputSchema: {
          type: 'object',
          properties: {
            agentId: { type: 'string' },
            modelId: { type: 'string' },
          },
          required: ['agentId', 'modelId'],
          additionalProperties: false,
        },
        annotations: { readOnlyHint: false, untrustedContentHint: false },
        execute(input) {
          let result: unknown;
          flushSync(() => {
            result = actions.current.change(input);
          });
          return result;
        },
      },
    ];
    for (const tool of tools) {
      try {
        void Promise.resolve(
          context.registerTool(tool, { signal: lifecycle.signal }),
        ).catch(() => {});
      } catch {
        /* Browsers without a compatible registry keep the normal UI. */
      }
    }
    return () => lifecycle.abort();
  }, []);
}
