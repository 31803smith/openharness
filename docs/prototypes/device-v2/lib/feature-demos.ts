import { demoReducer, initialState, type DemoState } from './demo-state.ts';

export type Feature = 'focus' | 'voice' | 'attention' | 'updates';

export function initialFeatureState(feature: Feature): DemoState {
  const state = { ...initialState(), answered: true, announcement: '' };
  if (feature === 'attention') {
    return {
      ...state,
      answered: false,
      focused: 'notes',
      focusMemory: { ...state.focusMemory, workshop: 'notes' },
      scroll: { notes: 6 },
    };
  }
  if (feature === 'updates') {
    return {
      ...demoReducer(state, { type: 'completion-notify', agent: 'api' }),
      announcement: '',
    };
  }
  return state;
}
