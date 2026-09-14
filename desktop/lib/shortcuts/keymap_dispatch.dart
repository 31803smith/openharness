import 'keymap.dart';

enum KeymapKeyPhase { down, repeat, up }

class KeymapDispatchResult {
  const KeymapDispatchResult({this.handled = false, this.command});
  final bool handled;
  final String? command;
}

/// Dispatch is synchronous and bounded. An unmatched sequence is consumed,
/// never replayed into an agent. Modifiers still follow their normal route.
class KeymapDispatch {
  KeymapDispatch(this._map);
  ResolvedKeymap _map;
  final _prefix = <KeyStroke>[];
  final _pressed = <Object>{};
  Object? _owner;
  KeymapContext? _context;

  List<KeyStroke> get pending => List.unmodifiable(_prefix);
  bool get hasPending => _prefix.isNotEmpty;
  bool release(Object physicalKey) => _pressed.remove(physicalKey);

  void update(ResolvedKeymap map) {
    if (identical(_map, map)) return;
    _map = map;
    cancel();
  }

  void cancel() {
    _prefix.clear();
    _owner = null;
    _context = null;
  }

  /// Called on window blur, when the platform may never deliver held key-ups.
  void suspend() {
    cancel();
    _pressed.clear();
  }

  KeymapDispatchResult dispatch({
    required KeyStroke? stroke,
    required Object physicalKey,
    required KeymapKeyPhase phase,
    required KeymapContext context,
    required Object owner,
    required bool Function(String) canExecute,
    bool Function(String)? canRepeat,
    bool composing = false,
    bool modifier = false,
  }) {
    if (phase == KeymapKeyPhase.up) {
      return KeymapDispatchResult(handled: release(physicalKey));
    }
    if (composing) {
      cancel();
      return const KeymapDispatchResult();
    }
    if (hasPending && (!identical(owner, _owner) || context != _context)) {
      cancel();
    }
    if (stroke == null) {
      if (!modifier && hasPending) {
        cancel();
        _pressed.add(physicalKey);
        return const KeymapDispatchResult(handled: true);
      }
      return const KeymapDispatchResult();
    }
    if (phase == KeymapKeyPhase.repeat && hasPending) {
      return KeymapDispatchResult(handled: _pressed.contains(physicalKey));
    }
    final wasPending = hasPending;
    if (wasPending && stroke == const KeyStroke('escape')) {
      cancel();
      _pressed.add(physicalKey);
      return const KeymapDispatchResult(handled: true);
    }
    final sequence = [..._prefix, stroke];
    final match = _map.match(context, sequence);
    if (match.prefix) {
      _prefix.add(stroke);
      _owner = owner;
      _context = context;
      _pressed.add(physicalKey);
      return const KeymapDispatchResult(handled: true);
    }
    cancel();
    final command = match.command;
    if (command != null) {
      _pressed.add(physicalKey);
      return KeymapDispatchResult(
        handled: true,
        command:
            canExecute(command) &&
                (phase != KeymapKeyPhase.repeat ||
                    canRepeat?.call(command) == true)
            ? command
            : null,
      );
    }
    if (wasPending) _pressed.add(physicalKey);
    return KeymapDispatchResult(handled: wasPending);
  }
}
