'use client';

import { Globe2, House, Users } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';
import { Switch } from '@/components/ui/switch';
import {
  grids,
  models,
  unavailableReason,
  type Connections,
  type GridId,
} from './demo';

type Props = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  connections: Connections;
  opusLimited: boolean;
  onChange: (id: GridId, connected: boolean) => void;
};

export function GridConnections({
  open,
  onOpenChange,
  connections,
  opusLimited,
  onChange,
}: Props) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="connections-dialog">
        <div className="connections-heading">
          <DialogTitle>Models</DialogTitle>
          <DialogDescription>
            Available to all your agents. Choose a model inside each agent.
          </DialogDescription>
        </div>
        <div className="connected-models">
          {models
            .filter((model) => model.kind !== 'grid')
            .map((model) => (
              <div className="connected-model" key={model.id}>
                <strong>{model.name}</strong>
                <span>
                  {model.kind === 'cloud'
                    ? model.source === 'Cloud'
                      ? 'Cloud account'
                      : model.source
                    : 'This machine'}
                </span>
                <small>
                  {unavailableReason(model.id, opusLimited, connections) ??
                    'Available'}
                </small>
              </div>
            ))}
        </div>
        <div className="connection-list">
          <h3 className="shared-models-title">Shared models</h3>
          {grids.map((grid) => {
            const Icon = { private: House, team: Users, public: Globe2 }[
              grid.id
            ];
            const offered = models.filter((m) => m.gridId === grid.id);
            return (
              <div className="connection-row" key={grid.id}>
                <Icon size={18} />
                <label htmlFor={'connect-' + grid.id}>
                  <strong>
                    {grid.name}
                    <span>{grid.kind}</span>
                  </strong>
                  <small>{offered.map((model) => model.name).join(', ')}</small>
                  <small>{grid.access}</small>
                  <span className="connection-state">
                    {connections[grid.id]
                      ? 'Connected · all models available'
                      : 'Disconnected'}
                  </span>
                </label>
                <Switch
                  id={'connect-' + grid.id}
                  checked={connections[grid.id]}
                  onCheckedChange={(connected) => onChange(grid.id, connected)}
                />
              </div>
            );
          })}
        </div>
        <div className="connections-footer">
          <p>
            Connecting makes every model from that source available. Each agent
            keeps its own model choice.
          </p>
          <small>
            Local simulation · accounts and connections are examples
          </small>
        </div>
      </DialogContent>
    </Dialog>
  );
}
