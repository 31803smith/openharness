import Cocoa

/// Canonical logical strokes match Dart's KeyStroke. No QWERTY letter table:
/// AppKit translates the event through the current keyboard layout.
struct HarnessKeyStroke: Hashable {
  let key: String
  let modifiers: NSEvent.ModifierFlags
  static let modifierMask: NSEvent.ModifierFlags = [.control, .option, .command, .shift]
  static let named: Set<String> = ["enter", "escape", "left", "right", "up", "down",
    "pageup", "pagedown", "home", "end", "delete", "backspace", "tab", "space",
    "comma", "period", "slash", "backslash", "semicolon", "quote", "backquote",
    "bracketleft", "bracketright", "minus", "equal", "insert"]

  init?(_ canonical: String) {
    let pieces = canonical.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    guard let last = pieces.last, Self.validKey(last), pieces.count <= 5 else { return nil }
    var flags: NSEvent.ModifierFlags = []
    for part in pieces.dropLast() {
      let flag: NSEvent.ModifierFlags
      switch part {
      case "ctrl": flag = .control
      case "alt": flag = .option
      case "cmd": flag = .command
      case "shift": flag = .shift
      default: return nil
      }
      guard !flags.contains(flag) else { return nil }
      flags.insert(flag)
    }
    key = last
    modifiers = flags
  }

  private init(key: String, modifiers: NSEvent.ModifierFlags) {
    self.key = key
    self.modifiers = modifiers.intersection(Self.modifierMask)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(key)
    hasher.combine(modifiers.rawValue)
  }

  private static func validKey(_ key: String) -> Bool {
    if named.contains(key) { return true }
    if key.count == 1, let value = key.unicodeScalars.first?.value {
      return (97...122).contains(value) || (48...57).contains(value)
    }
    guard key.first == "f", let number = Int(key.dropFirst()) else { return false }
    return (1...24).contains(number) && key == "f\(number)"
  }

  private static let characterNames: [String: String] = [
      "\r": "enter", "\u{3}": "enter", "\u{1b}": "escape", "\u{7f}": "backspace",
      "\u{8}": "backspace", "\t": "tab", "\u{19}": "tab", " ": "space",
      ",": "comma", ".": "period", "/": "slash", "\\": "backslash",
      ";": "semicolon", "'": "quote", "`": "backquote", "[": "bracketleft",
      "]": "bracketright", "-": "minus", "=": "equal",
      "\u{f700}": "up", "\u{f701}": "down", "\u{f702}": "left", "\u{f703}": "right",
      "\u{f727}": "insert", "\u{f728}": "delete", "\u{f729}": "home",
      "\u{f72b}": "end", "\u{f72c}": "pageup", "\u{f72d}": "pagedown",
  ]

  static func fromCharacters(_ characters: String, modifiers: NSEvent.ModifierFlags) -> Self? {
    let lowered = characters.lowercased()
    let key: String
    if let scalar = characters.unicodeScalars.first, characters.unicodeScalars.count == 1,
       (0xf704...0xf71b).contains(scalar.value) {
      key = "f\(scalar.value - 0xf704 + 1)"
    } else {
      key = characterNames[characters] ?? lowered
    }
    guard validKey(key) else { return nil }
    return Self(key: key, modifiers: modifiers)
  }

  static func fromEvent(_ event: NSEvent) -> Self? {
    guard event.type == .keyDown || event.type == .keyUp else { return nil }
    // Remove Shift/Option from translation, but keep them in the stroke. This
    // resolves Shift-1 through the user's layout without treating '!' as a key.
    guard let text = event.characters(byApplyingModifiers: event.modifierFlags.intersection(.command))
      ?? event.charactersIgnoringModifiers else { return nil }
    return fromCharacters(text, modifiers: event.modifierFlags)
  }

  var menuEquivalent: String {
    let special: [String: String] = [
      "enter": "\r", "escape": "\u{1b}", "backspace": "\u{8}", "tab": "\t", "space": " ",
      "comma": ",", "period": ".", "slash": "/", "backslash": "\\", "semicolon": ";",
      "quote": "'", "backquote": "`", "bracketleft": "[", "bracketright": "]", "minus": "-", "equal": "=",
      "up": "\u{f700}", "down": "\u{f701}", "left": "\u{f702}", "right": "\u{f703}",
      "insert": "\u{f727}", "delete": "\u{f728}", "home": "\u{f729}", "end": "\u{f72b}",
      "pageup": "\u{f72c}", "pagedown": "\u{f72d}",
    ]
    if let value = special[key] { return value }
    if key.first == "f", let number = Int(key.dropFirst()), (1...24).contains(number) {
      return String(UnicodeScalar(0xf704 + number - 1)!)
    }
    return key
  }
}

struct HarnessNativeBinding {
  let keys: [HarnessKeyStroke]
  let command: String
  let hint: String
  let repeatable: Bool
  let menuAction: String?
}

private final class HarnessKeyNode {
  var binding: HarnessNativeBinding?
  var children: [HarnessKeyStroke: HarnessKeyNode] = [:]
}

/// Reject a malformed snapshot as a whole, leaving the caller's last good map.
/// Defaults and overrides are already resolved in Dart, including unbinding.
final class HarnessNativeKeymap {
  private var roots: [String: HarnessKeyNode] = [:]
  private(set) var bindings: [String: [HarnessNativeBinding]] = [:]

  init?(_ payload: [String: Any]) {
    guard payload["version"] as? Int == 1,
          let contexts = payload["contexts"] as? [String: Any],
          Set(contexts.keys) == Set(["workspace", "terminal", "picker"]) else { return nil }
    for (context, raw) in contexts {
      guard let rows = raw as? [[String: Any]], rows.count <= 640 else { return nil }
      let root = HarnessKeyNode()
      var parsed: [HarnessNativeBinding] = []
      for row in rows {
        guard let keys = row["keys"] as? [String], (1...4).contains(keys.count),
              let command = row["command"] as? String, !command.isEmpty, command.utf8.count <= 120,
              let hint = row["hint"] as? String, hint.utf8.count <= 160,
              let repeatable = row["repeatable"] as? Bool else { return nil }
        let strokes = keys.compactMap(HarnessKeyStroke.init)
        guard strokes.count == keys.count else { return nil }
        let binding = HarnessNativeBinding(keys: strokes, command: command, hint: hint,
          repeatable: repeatable, menuAction: row["menuAction"] as? String)
        var node = root
        for stroke in strokes {
          guard node.binding == nil else { return nil }
          if node.children[stroke] == nil { node.children[stroke] = HarnessKeyNode() }
          node = node.children[stroke]!
        }
        guard node.children.isEmpty && node.binding == nil else { return nil }
        node.binding = binding
        parsed.append(binding)
      }
      roots[context] = root
      bindings[context] = parsed
    }
  }

  func match(_ keys: [HarnessKeyStroke], context: String) -> (binding: HarnessNativeBinding?, prefix: Bool) {
    guard var node = roots[context] else { return (nil, false) }
    for key in keys {
      guard let child = node.children[key] else { return (nil, false) }
      node = child
    }
    return (node.binding, !node.children.isEmpty)
  }
}

/// Synchronous native-field dispatcher. Mirrors KeymapDispatch: cancelled or
/// failed prefixes are consumed, never replayed into the query or an agent.
final class HarnessNativeKeyDispatch {
  private var map: HarnessNativeKeymap
  private(set) var pending: [HarnessKeyStroke] = []
  private var pressed: Set<UInt16> = []
  private var owner: ObjectIdentifier?
  private var context: String?

  init(_ map: HarnessNativeKeymap) { self.map = map }
  func update(_ next: HarnessNativeKeymap) { map = next; cancel() }
  func cancel() { pending.removeAll(keepingCapacity: true); owner = nil; context = nil }
  func suspend() { cancel(); pressed.removeAll(keepingCapacity: true) }
  func release(_ keyCode: UInt16) -> Bool { pressed.remove(keyCode) != nil }

  func dispatch(_ stroke: HarnessKeyStroke?, keyCode: UInt16, repeated: Bool = false,
                modifier: Bool = false, composing: Bool = false, context: String,
                owner: AnyObject, canExecute: (String) -> Bool = { _ in true }) -> (handled: Bool, command: String?) {
    if composing { cancel(); return (false, nil) }
    let ownerID = ObjectIdentifier(owner)
    if !pending.isEmpty && (self.owner != ownerID || self.context != context) { cancel() }
    guard let stroke else {
      if !modifier && !pending.isEmpty { cancel(); pressed.insert(keyCode); return (true, nil) }
      return (false, nil)
    }
    if repeated && !pending.isEmpty { return (pressed.contains(keyCode), nil) }
    let wasPending = !pending.isEmpty
    if wasPending && stroke == HarnessKeyStroke("escape")! {
      cancel(); pressed.insert(keyCode); return (true, nil)
    }
    let sequence = pending + [stroke]
    let match = map.match(sequence, context: context)
    if match.prefix {
      pending = sequence; self.owner = ownerID; self.context = context
      pressed.insert(keyCode)
      return (true, nil)
    }
    cancel()
    if let binding = match.binding {
      pressed.insert(keyCode)
      return (true, canExecute(binding.command) && (!repeated || binding.repeatable) ? binding.command : nil)
    }
    if wasPending { pressed.insert(keyCode) }
    return (wasPending, nil)
  }
}
