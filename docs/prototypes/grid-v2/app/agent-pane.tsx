'use client';

import { useEffect, useRef } from 'react';
import { ArrowUp, GitBranch, Terminal } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { getModel, type Agent, type Model } from './demo';
import { ModelPicker } from './model-picker';

type Props = {
  agent: Agent;
  catalog: Model[];
  onAddModels: () => void;
  connectionNotice: string;
  draft: string;
  onDraftChange: (draft: string) => void;
  onSend: (message: string) => void;
  modelMenuOpen: boolean;
  onModelMenuOpen: (open: boolean) => void;
  onModelChange: (modelId: string) => void;
};

export function AgentPane(props: Props) {
  const { agent } = props;
  const output = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (output.current) output.current.scrollTop = output.current.scrollHeight;
  }, [agent.nextTurn]);

  return (
    <article className="terminal-pane" aria-label={agent.name + ' agent'}>
      <header className="pane-header">
        <h2 className="pane-title">
          <span className="terminal-icon">
            <Terminal size={16} />
          </span>
          <strong title={agent.project}>{agent.project}</strong>
        </h2>
        <span className="pane-branch" title={agent.branch}>
          <GitBranch size={14} />
          <span>{agent.branch}</span>
        </span>
        <span className="pane-machine" title={agent.computer}>
          {agent.computer}
        </span>
        <ModelPicker
          agent={agent}
          models={props.catalog}
          onAddModels={props.onAddModels}
          connectionNotice={props.connectionNotice}
          open={props.modelMenuOpen}
          onOpenChange={props.onModelMenuOpen}
          onChoose={props.onModelChange}
        />
      </header>
      <div className="terminal-output" ref={output}>
        <div className="terminal-session">
          <strong>{agent.engine}</strong>
          <span>{agent.folder}</span>
        </div>
        <p className="terminal-prompt">
          <b>›</b>
          {agent.task}
        </p>
        <div className="terminal-files">
          <p>Read</p>
          {agent.files.map((file) => (
            <p key={file}> {file}</p>
          ))}
        </div>
        {agent.turns.map((turn) => (
          <div className="terminal-turn" key={turn.id}>
            {turn.prompt && (
              <p className="terminal-prompt">
                <b>›</b>
                {turn.prompt}
              </p>
            )}
            <span className="response-model">
              {getModel(turn.modelId, props.catalog).name} ·{' '}
              {getModel(turn.modelId, props.catalog).source}
            </span>
            <p>{turn.text}</p>
          </div>
        ))}
      </div>
      <form
        className="composer"
        onSubmit={(event) => {
          event.preventDefault();
          if (props.draft.trim()) props.onSend(props.draft);
        }}
      >
        <span aria-hidden="true">›</span>
        <Input
          aria-label={'Message ' + agent.name}
          placeholder={'Message ' + agent.engine + '…'}
          value={props.draft}
          onChange={(event) => props.onDraftChange(event.target.value)}
        />
        <button
          type="submit"
          className="send-button"
          disabled={!props.draft.trim()}
          aria-label={'Send message to ' + agent.name}
        >
          <ArrowUp size={16} />
        </button>
      </form>
    </article>
  );
}
