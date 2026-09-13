// Compiled after HarnessKeymap.swift by check_keymap_native.sh.
struct KeymapCheckFailure: Error { let message: String }
var keymapChecks = 0
func checkKeymap(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  guard condition() else { throw KeymapCheckFailure(message: message) }
  keymapChecks += 1
}
func stroke(_ key: String) -> HarnessKeyStroke { HarnessKeyStroke(key)! }

let source = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let fixture = try JSONSerialization.jsonObject(with: source) as! [String: [String: Any]]
let defaults = HarnessNativeKeymap(fixture["defaults"]!)!
let changed = HarnessNativeKeymap(fixture["changed"]!)!
for (key, command) in [
  ("cmd+h", "pane.focus_left"), ("cmd+j", "pane.focus_below"),
  ("cmd+k", "pane.focus_above"), ("cmd+l", "pane.focus_right"),
  ("cmd+s", "pane.layout"), ("cmd+r", "machines.refresh"),
  ("cmd+b", "task.route"), ("cmd+p", "navigation.quick_open"),
] {
  try checkKeymap(defaults.match([stroke(key)], context: "workspace").binding?.command == command,
    "Preserve the current default for \(key)")
}
for context in ["workspace", "terminal", "picker"] {
  try checkKeymap(changed.match([stroke("cmd+p")], context: context).binding == nil,
    "Native context honors inherited unbinding")
  let search = changed.match([stroke("cmd+o")], context: context).binding
  try checkKeymap(search?.command == "navigation.quick_open" && search?.hint == "⌘O" && search?.menuAction == "jump",
    "The new key, menu owner and displayed hint agree")
  try checkKeymap(changed.match([stroke("cmd+k")], context: context).prefix,
    "User sequence prefix replaces the shorter command")
}
try checkKeymap(changed.match([stroke("cmd+h")], context: "terminal").binding == nil,
  "Terminal-only unbinding does not leak its workspace binding")
try checkKeymap(changed.match([stroke("cmd+h")], context: "workspace").binding != nil,
  "Workspace keeps its own context")
try checkKeymap(changed.match([stroke("down")], context: "picker").binding == nil,
  "Picker unbinding removes the original arrow action")
try checkKeymap(changed.match([stroke("ctrl+j")], context: "picker").binding?.command == "picker.previous",
  "Picker remapping wins")
try checkKeymap(defaults.match([stroke("cmd+i")], context: "picker").binding?.command == "picker.preview",
  "The shipped optional-preview shortcut joins the catalog")

let dispatcher = HarnessNativeKeyDispatch(changed)
let field = NSObject(), otherField = NSObject()
func send(_ key: String?, _ code: UInt16 = 1, repeated: Bool = false, composing: Bool = false,
          owner: NSObject = field, context: String = "picker", modifier: Bool = false,
          executable: Bool = true) -> (handled: Bool, command: String?) {
  dispatcher.dispatch(key.map(stroke), keyCode: code, repeated: repeated, modifier: modifier,
    composing: composing, context: context, owner: owner, canExecute: { _ in executable })
}
try checkKeymap(send("cmd+k").handled && dispatcher.pending.count == 1, "Prefix is claimed synchronously")
try checkKeymap(send("cmd+k", repeated: true).command == nil && dispatcher.pending.count == 1,
  "A held prefix does not advance a sequence")
try checkKeymap(!send(nil, 2, modifier: true).handled && dispatcher.pending.count == 1,
  "Modifiers retain normal delivery during a prefix")
try checkKeymap(send("cmd+n", 3).command == "swarm.new" && dispatcher.pending.isEmpty,
  "Completing a sequence dispatches exactly one named command")
try checkKeymap(dispatcher.release(3) && !dispatcher.release(3), "Consumed key-up is paired once")
_ = send("cmd+k")
try checkKeymap(send("x", 4).handled && dispatcher.pending.isEmpty,
  "A failed sequence is consumed rather than typed into an agent")
try checkKeymap(!send("x", 4).handled, "The next ordinary character is not swallowed")
_ = send("cmd+k")
try checkKeymap(send("escape", 5).handled && dispatcher.pending.isEmpty, "Escape cancels a prefix")
_ = send("cmd+k")
try checkKeymap(!send("x", 4, owner: otherField).handled && dispatcher.pending.isEmpty,
  "A different input owner cannot complete the previous field's sequence")
_ = send("cmd+k")
try checkKeymap(!send("enter", 6, composing: true).handled && dispatcher.pending.isEmpty,
  "IME composition keeps input and cancels the prefix")
try checkKeymap(send("cmd+o", executable: false).handled && send("cmd+o", executable: false).command == nil,
  "An unavailable mapped action cannot fall through as input")
try checkKeymap(send("cmd+o", repeated: true).command == nil, "Search does not repeat")
try checkKeymap(send("ctrl+j", repeated: true).command == "picker.previous", "Result movement repeats")
_ = send("cmd+k")
dispatcher.suspend()
try checkKeymap(dispatcher.pending.isEmpty && !dispatcher.release(1), "Window blur clears pending and held keys")
dispatcher.update(defaults)
try checkKeymap(send("cmd+p").command == "navigation.quick_open", "Reload installs the new resolved map")

try checkKeymap(HarnessKeyStroke.fromCharacters("P", modifiers: [.command, .capsLock]) == stroke("cmd+p"),
  "Caps Lock does not change a Command binding")
try checkKeymap(HarnessKeyStroke.fromCharacters("1", modifiers: [.command, .shift]) == stroke("cmd+shift+1"),
  "Shift stays in modifiers after layout translation")
try checkKeymap(HarnessKeyStroke.fromCharacters("\u{f702}", modifiers: .command) == stroke("cmd+left"),
  "AppKit arrow characters map to the same logical keys")
try checkKeymap(HarnessKeyStroke.fromCharacters("木", modifiers: []) == nil,
  "Unsupported composed text is not guessed as a QWERTY key")
try checkKeymap(stroke("cmd+shift+left").menuEquivalent == "\u{f702}" && stroke("f24").menuEquivalent == "\u{f71b}",
  "Native menu equivalents preserve function keys")

func payload(_ rows: [[String: Any]]) -> [String: Any] {
  ["version": 1, "contexts": ["workspace": rows, "terminal": rows, "picker": rows]]
}
let prefix: [String: Any] = ["keys": ["cmd+k"], "command": "example", "hint": "⌘K", "repeatable": false]
let sequence: [String: Any] = ["keys": ["cmd+k", "cmd+n"], "command": "example", "hint": "⌘K ⌘N", "repeatable": false]
try checkKeymap(HarnessNativeKeymap(payload([prefix, sequence])) == nil, "Reject ambiguous prefixes atomically")
try checkKeymap(HarnessNativeKeymap(payload([prefix, prefix])) == nil, "Reject duplicate strokes atomically")
try checkKeymap(HarnessNativeKeymap(payload(Array(repeating: prefix, count: 641))) == nil, "Bound incoming binding counts")
try checkKeymap(HarnessNativeKeymap(["version": 2, "contexts": [:]]) == nil, "Reject unsupported snapshots")
for value in ["cmd+cmd+p", "cmd+", "cmd+not-a-key", "ctrl+alt+shift+cmd+fn+p", "f01"] {
  try checkKeymap(HarnessKeyStroke(value) == nil, "Reject malformed native stroke \(value)")
}
print("Native keyboard bridge: \(keymapChecks) checks passed against Dart's exported bindings; no windows or agents opened.")
