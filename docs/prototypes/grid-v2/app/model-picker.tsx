'use client';

import { useRef, useState } from 'react';
import { CheckCircle2, ChevronDown, Plus, X } from 'lucide-react';
import {
  Command,
  CommandEmpty,
  CommandInput,
  CommandItem,
  CommandList,
} from '@/components/ui/command';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover';
import { getModel, type Agent, type Model } from './demo';

type Props = {
  agent: Agent;
  models: Model[];
  onAddModels: () => void;
  connectionNotice: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onChoose: (modelId: string) => void;
};

export function ModelPicker({
  agent,
  models,
  open,
  onOpenChange,
  onChoose,
  onAddModels,
  connectionNotice,
}: Props) {
  const active = getModel(agent.modelId, models);
  const [search, setSearch] = useState('');
  const searchInput = useRef<HTMLInputElement>(null);
  const openingSetup = useRef(false);

  return (
    <Popover
      open={open}
      onOpenChange={(nextOpen) => {
        setSearch('');
        onOpenChange(nextOpen);
      }}
    >
      <PopoverTrigger
        render={
          <button
            className="model-trigger"
            type="button"
            aria-label={'Change model for ' + agent.name + ': ' + active.name}
          />
        }
        title="Change model"
      >
        <span>{active.name}</span>
        <ChevronDown size={13} />
      </PopoverTrigger>
      <PopoverContent
        side="bottom"
        align="end"
        sideOffset={8}
        className="model-menu"
        aria-label={'Change model for ' + agent.name}
        initialFocus={searchInput}
        finalFocus={() => {
          if (openingSetup.current) {
            openingSetup.current = false;
            return false;
          }
          return true;
        }}
      >
        {connectionNotice && (
          <output className="connection-notice" aria-live="polite">
            <CheckCircle2 size={15} />
            <span>{connectionNotice}</span>
          </output>
        )}
        <Command
          className="model-command"
          label="Choose a model"
          defaultValue={active.id}
          loop
          filter={(_value, query, keywords) => {
            const text = (keywords ?? []).join(' ').toLowerCase();
            return query
              .toLowerCase()
              .trim()
              .split(/\s+/)
              .every((term) => text.includes(term))
              ? 1
              : 0;
          }}
        >
          <div className="model-search">
            <CommandInput
              ref={searchInput}
              placeholder="Search models, types, providers…"
              aria-label="Search models by name, type, or inference provider"
              value={search}
              onValueChange={setSearch}
            />
            {search && (
              <button
                className="clear-search"
                type="button"
                aria-label="Clear search"
                onKeyDown={(event) => {
                  if (event.key === 'Enter' || event.key === ' ')
                    event.stopPropagation();
                }}
                onClick={() => {
                  setSearch('');
                  searchInput.current?.focus();
                }}
              >
                <X size={14} />
              </button>
            )}
          </div>
          <div className="model-columns" aria-hidden="true">
            <span>Model</span>
            <span>Type</span>
            <span>Inference provider</span>
            <span />
          </div>
          <CommandList className="model-results" aria-label="Available models">
            <CommandEmpty className="model-empty">
              <strong>No models found</strong>
              <span>Try another model, type, or provider.</span>
            </CommandEmpty>
            {models.map((model) => (
              <CommandItem
                key={model.id}
                value={model.id}
                keywords={[model.name, model.type, model.source]}
                className="model-option"
                data-checked={model.id === active.id}
                aria-label={
                  model.name +
                  ', ' +
                  model.type +
                  ', ' +
                  model.source +
                  (model.id === active.id ? ', current model' : '')
                }
                onSelect={() => {
                  setSearch('');
                  onChoose(model.id);
                }}
              >
                <span className="model-name" title={model.name}>
                  {model.name}
                </span>
                <span className="model-type">{model.type}</span>
                <span className="model-provider" title={model.source}>
                  {model.source}
                </span>
              </CommandItem>
            ))}
          </CommandList>
        </Command>
        <button
          className="add-models-button"
          type="button"
          onClick={() => {
            openingSetup.current = true;
            setSearch('');
            onAddModels();
          }}
        >
          <Plus size={16} /> Add models
        </button>
      </PopoverContent>
    </Popover>
  );
}
