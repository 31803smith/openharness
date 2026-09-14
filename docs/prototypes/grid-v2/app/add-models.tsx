'use client';

import { useEffect, useRef, useState } from 'react';
import {
  ArrowLeft,
  ChevronRight,
  CreditCard,
  KeyRound,
  Laptop,
  Users,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  apiProviders,
  createModelConnection,
  subscriptionProviders,
  type AccessMethod,
  type ModelConnection,
} from './model-access';

const methods = [
  {
    id: 'subscription',
    title: 'Connect a subscription',
    description: 'Use an account with an existing subscription.',
    icon: CreditCard,
  },
  {
    id: 'api',
    title: 'Add an API',
    description: 'Connect a provider with an API key.',
    icon: KeyRound,
  },
  {
    id: 'local',
    title: 'Connect local models',
    description: 'Use a model server on this or another computer.',
    icon: Laptop,
  },
  {
    id: 'shared',
    title: 'Join shared models',
    description: 'Get access through your team or a public community.',
    icon: Users,
  },
] as const;

type Props = {
  connections: ModelConnection[];
  onConnect: (connection: ModelConnection) => void;
  onClose: () => void;
};

export function AddModels({ connections, onConnect, onClose }: Props) {
  const [method, setMethod] = useState<AccessMethod | null>(null);
  const [provider, setProvider] = useState('google');
  const [name, setName] = useState('');
  const [endpoint, setEndpoint] = useState('');
  const [audience, setAudience] = useState<'team' | 'public'>('team');
  const [error, setError] = useState('');
  const fields = useRef<HTMLDivElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const current = methods.find((item) => item.id === method);
  const known = connections.find((item) => item.id === method + ':' + provider);

  useEffect(() => {
    const container = method ? fields.current : menu.current;
    container?.querySelector<HTMLElement>('select, input, button')?.focus();
  }, [method]);

  function chooseMethod(next: AccessMethod) {
    setMethod(next);
    setError('');
    setAudience('team');
    const options =
      next === 'subscription' ? subscriptionProviders : apiProviders;
    setProvider(
      options.find(
        (item) => !connections.some((c) => c.id === next + ':' + item.id),
      )?.id ?? options[0].id,
    );
    setName(
      next === 'local'
        ? 'Mac Studio'
        : next === 'shared'
          ? 'Autonomous.ai'
          : 'Custom API',
    );
    setEndpoint(
      next === 'local'
        ? 'http://mac-studio.local:11434'
        : next === 'shared'
          ? 'https://models.example.com/autonomous'
          : 'https://api.example.com/v1',
    );
  }

  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open) onClose();
      }}
    >
      <DialogContent className="add-models-dialog" finalFocus={false}>
        <div className="setup-heading">
          {method && (
            <button
              className="setup-back"
              type="button"
              onClick={() => {
                setMethod(null);
                setError('');
              }}
            >
              <ArrowLeft size={14} /> Add models
            </button>
          )}
          <DialogTitle>{current?.title ?? 'Add models'}</DialogTitle>
          <DialogDescription>
            {method
              ? 'All models from this connection will be available to your agents.'
              : 'Connect an account, a model server, or a shared collection.'}
          </DialogDescription>
        </div>
        {!method ? (
          <div className="setup-methods" ref={menu}>
            {methods.map(({ id, title, description, icon: Icon }) => (
              <button
                className="setup-method"
                type="button"
                key={id}
                onClick={() => chooseMethod(id)}
              >
                <Icon size={19} />
                <span>
                  <strong>{title}</strong>
                  <small>{description}</small>
                </span>
                <ChevronRight size={16} />
              </button>
            ))}
          </div>
        ) : (
          <form
            className="setup-form"
            onSubmit={(event) => {
              event.preventDefault();
              try {
                onConnect(
                  createModelConnection({
                    method,
                    provider,
                    name,
                    endpoint,
                    audience,
                  }),
                );
              } catch (cause) {
                setError(
                  cause instanceof Error
                    ? cause.message
                    : 'Check the connection details.',
                );
              }
            }}
          >
            <div className="setup-fields" ref={fields}>
              {(method === 'subscription' || method === 'api') && (
                <div className="setup-field">
                  <label htmlFor="access-provider">Provider</label>
                  <select
                    id="access-provider"
                    value={provider}
                    onChange={(event) => {
                      setProvider(event.target.value);
                      setError('');
                    }}
                  >
                    {(method === 'subscription'
                      ? subscriptionProviders
                      : apiProviders
                    ).map((item) => (
                      <option value={item.id} key={item.id}>
                        {item.name}
                        {connections.some(
                          (c) => c.id === method + ':' + item.id,
                        )
                          ? ' · Connected'
                          : ''}
                      </option>
                    ))}
                  </select>
                </div>
              )}
              {known ? (
                <p className="setup-connected">
                  {known.name} is connected. {known.models.length}
                  {known.models.length === 1 ? ' model is' : ' models are'}{' '}
                  already available.
                </p>
              ) : (
                <>
                  {method === 'subscription' && (
                    <div className="setup-field">
                      <label htmlFor="subscription-email">Account email</label>
                      <Input
                        id="subscription-email"
                        type="email"
                        defaultValue="dee@autonomous.ai"
                        autoComplete="off"
                        required
                      />
                    </div>
                  )}
                  {method === 'shared' && (
                    <fieldset className="setup-audience">
                      <legend>Access</legend>
                      {(['team', 'public'] as const).map((option) => (
                        <label key={option}>
                          <input
                            type="radio"
                            name="audience"
                            value={option}
                            checked={audience === option}
                            onChange={() => {
                              setAudience(option);
                              setName(
                                option === 'team' ? 'Autonomous.ai' : 'Omagrid',
                              );
                              setEndpoint(
                                option === 'team'
                                  ? 'https://models.example.com/autonomous'
                                  : 'https://omagrid.example/join',
                              );
                              setError('');
                            }}
                          />
                          {option === 'team' ? 'Team' : 'Public community'}
                        </label>
                      ))}
                    </fieldset>
                  )}
                  {(method === 'local' ||
                    method === 'shared' ||
                    (method === 'api' && provider === 'custom')) && (
                    <>
                      <div className="setup-field">
                        <label htmlFor="access-name">
                          {method === 'local'
                            ? 'Computer name'
                            : method === 'shared'
                              ? 'Team or community name'
                              : 'Connection name'}
                        </label>
                        <Input
                          id="access-name"
                          value={name}
                          onChange={(event) => setName(event.target.value)}
                          required
                          maxLength={60}
                          autoComplete="off"
                        />
                      </div>
                      <div className="setup-field">
                        <label htmlFor="access-endpoint">
                          {method === 'shared'
                            ? 'Invitation or server URL'
                            : 'Server URL'}
                        </label>
                        <Input
                          id="access-endpoint"
                          type="url"
                          value={endpoint}
                          onChange={(event) => setEndpoint(event.target.value)}
                          required
                          autoComplete="off"
                          spellCheck={false}
                        />
                      </div>
                    </>
                  )}
                  {method === 'api' && (
                    <div className="setup-field">
                      <label htmlFor="access-key">API key</label>
                      <Input
                        id="access-key"
                        type="password"
                        defaultValue="demo-key"
                        required
                        autoComplete="off"
                      />
                      <small>
                        A sample key is filled in for this prototype.
                      </small>
                    </div>
                  )}
                  {method === 'shared' && audience === 'team' && (
                    <div className="setup-field">
                      <label htmlFor="team-email">Work email</label>
                      <Input
                        id="team-email"
                        type="email"
                        defaultValue="dee@autonomous.ai"
                        autoComplete="off"
                        required
                      />
                    </div>
                  )}
                </>
              )}
            </div>
            {error && (
              <p className="setup-error" role="alert">
                {error}
              </p>
            )}
            <div className="setup-actions">
              <Button className="setup-submit" type="submit">
                {known
                  ? 'View models'
                  : method === 'subscription'
                    ? 'Sign in & connect'
                    : method === 'api'
                      ? 'Connect API'
                      : method === 'local'
                        ? 'Connect server'
                        : 'Join models'}
              </Button>
            </div>
          </form>
        )}
        <div className="setup-demo">
          Simulated setup · Sample details are ready to use.
        </div>
      </DialogContent>
    </Dialog>
  );
}
