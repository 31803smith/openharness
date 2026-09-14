'use client';

import { useState } from 'react';
import { RotateCcw } from 'lucide-react';
import { AgentPane } from './agent-pane';
import { AddModels } from './add-models';
import {
  addModelConnection,
  initialModelAccess,
  type ModelConnection,
} from './model-access';
import {
  changeAgentModel,
  getModel,
  initialAgents,
  initialConnections,
  sendMessage,
  type Agent,
} from './demo';
import { useGridTools } from './use-grid-tools';

// Availability is determined by the connected model catalog below.
const connections = initialConnections();

export default function Home() {
  const [agents, setAgents] = useState(initialAgents);
  const [access, setAccess] = useState(initialModelAccess);
  const [editing, setEditing] = useState<string | null>(null);
  const [addingFor, setAddingFor] = useState<string | null>(null);
  const [connectionNotice, setConnectionNotice] = useState('');
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [notice, setNotice] = useState('');
  const models = access.flatMap((connection) => connection.models);

  function chooseModel(agent: Agent, modelId: string) {
    setAgents((old) =>
      changeAgentModel(old, agent.id, modelId, false, connections, models),
    );
    setEditing(null);
    setConnectionNotice('');
    const model = getModel(modelId, models);
    setNotice(
      agent.name + ' now uses ' + model.name + ' · ' + model.source + '.',
    );
    return { simulated: true, agentId: agent.id, modelId, status: 'applied' };
  }
  function submitMessage(agent: Agent, message: string) {
    setAgents((old) =>
      sendMessage(old, agent.id, message, false, connections, models),
    );
    setDrafts((old) => ({ ...old, [agent.id]: '' }));
  }
  function reset() {
    setAgents(initialAgents());
    setAccess(initialModelAccess());
    setEditing(null);
    setAddingFor(null);
    setConnectionNotice('');
    setDrafts({});
    setNotice('Prototype reset.');
  }
  function openAddModels(agentId: string) {
    setEditing(null);
    setConnectionNotice('');
    setAddingFor(agentId);
  }
  function returnToPicker() {
    setEditing(addingFor);
    setAddingFor(null);
  }
  function connect(connection: ModelConnection) {
    const result = addModelConnection(access, connection);
    const count = result.connection.models.length;
    setAccess(result.connections);
    setConnectionNotice(
      result.connection.name +
        (result.added ? ' connected · ' : ' is already connected · ') +
        count +
        (count === 1 ? ' model' : ' models') +
        (result.added ? ' added' : ' available'),
    );
    returnToPicker();
  }
  useGridTools(
    () => ({ simulated: true, agents, models, connections: access }),
    (input) => {
      if (!input || typeof input !== 'object' || Array.isArray(input))
        throw new Error('Expected agentId and modelId.');
      const value = input as Record<string, unknown>;
      if (
        Object.keys(value).some((key) => !['agentId', 'modelId'].includes(key))
      )
        throw new Error('Unknown input field.');
      const agent = agents.find((a) => a.id === value.agentId);
      const model = models.find((m) => m.id === value.modelId);
      if (!agent || !model)
        throw new Error('Choose an agent and model from get_grid_study.');
      return chooseModel(agent, model.id);
    },
  );

  return (
    <main className="app">
      <header className="titlebar">
        <strong>Harness</strong>
        <span className="window-title">Workshop · Swarm</span>
      </header>
      <section className="panes panes-3" aria-label="Workshop Swarm">
        {agents.map((agent) => (
          <div className="pane-slot" key={agent.id}>
            <AgentPane
              agent={agent}
              catalog={models}
              connectionNotice={connectionNotice}
              onAddModels={() => openAddModels(agent.id)}
              draft={drafts[agent.id] ?? ''}
              onDraftChange={(draft) =>
                setDrafts((old) => ({ ...old, [agent.id]: draft }))
              }
              onSend={(message) => submitMessage(agent, message)}
              modelMenuOpen={editing === agent.id}
              onModelMenuOpen={(open) => {
                if (open) setConnectionNotice('');
                setEditing((old) =>
                  open ? agent.id : old === agent.id ? null : old,
                );
              }}
              onModelChange={(modelId) => chooseModel(agent, modelId)}
            />
          </div>
        ))}
      </section>
      <footer className="statusbar">
        <span>Local prototype · simulated</span>
        <button className="text-button" onClick={reset}>
          <RotateCcw size={13} /> Reset
        </button>
      </footer>
      {addingFor && (
        <AddModels
          connections={access}
          onConnect={connect}
          onClose={returnToPicker}
        />
      )}
      <output className="sr-only" aria-live="polite">
        {notice}
      </output>
    </main>
  );
}
