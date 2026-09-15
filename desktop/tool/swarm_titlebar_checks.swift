
// Appended to SwarmTitlebar.swift by check_swarm_titlebar.sh. Same-file
// extensions can inspect private controls without exposing them in the app API.
private struct TitlebarCheckFailure: Error {
  let message: String
}

private var titlebarCheckCount = 0
private func checkTitlebar(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  guard condition() else { throw TitlebarCheckFailure(message: message) }
  titlebarCheckCount += 1
}

private extension SwarmTabButton {
  func checkAccessibility(expectedName: String, active: Bool) throws {
    try checkTitlebar(accessibilityLabel() == expectedName, "Tab group name is available before paint")
    let children = accessibilityChildren()?.compactMap { $0 as? NSButton } ?? []
    try checkTitlebar(children.count == 2, "Selection and close are separate accessible buttons")
    try checkTitlebar(children[0].accessibilityLabel() == "Select \(expectedName)", "Selection button has current name")
    try checkTitlebar(children[0].accessibilityValue() as? String == (active ? "Selected" : ""), "Selection value is current")
    try checkTitlebar(children[1].accessibilityLabel() == "Close \(expectedName)", "Close button has current name")
  }

  func checkEnabled(_ enabled: Bool) throws {
    try checkTitlebar(selectButton.isEnabled == enabled, "Select button obeys modal state")
    try checkTitlebar(closeButton.isEnabled == enabled, "Close button obeys modal state")
    for item in menu?.items ?? [] {
      try checkTitlebar(validateMenuItem(item) == enabled, "Tab context menu obeys modal state")
    }
  }

  func checkCloseVisibility(_ visible: Bool) throws {
    try checkTitlebar(closeButton.showsGlyph == visible,
      "A tab reveals its close mark only for hover or keyboard focus")
    try checkTitlebar(!closeButton.isHidden && closeButton.accessibilityLabel() == "Close \(name)",
      "A quiet close mark remains an accessible action")
  }

  func clickBothActions() {
    selectButton.performClick(nil)
    closeButton.performClick(nil)
  }
}

private extension SwarmTabStrip {
  func checkAgentIdentity() throws {
    func show(_ count: Int, engine: String? = nil) {
      var row: [String: Any] = ["id": "agent-tab", "name": "Login flow", "agentCount": count]
      if let engine { row["engine"] = engine }
      update(["tabs": [row], "activeId": "agent-tab", "enabled": true])
    }
    show(1, engine: "claude")
    let tab = tabs[0]
    let engineIcon = tab.icon
    try checkTitlebar(engineIcon != nil && engineIcon?.isTemplate == false, "A single-agent tab shows its engine mark")
    show(2)
    try checkTitlebar(tabs[0] === tab && tab.icon === SwarmIdentity.menuIcon, "Adding an agent changes the icon while retaining the tab control")
    show(1, engine: "claude")
    try checkTitlebar(tabs[0] === tab && tab.icon === engineIcon, "Closing back to one agent restores the cached engine icon")
  }

  func checkStartupPalette(_ expected: SwarmNativePalette) throws {
    try checkTitlebar(palette == expected && newButton.contentTintColor == expected.accent && notificationButton.contentTintColor == expected.accent &&
      newButton.contentTintColor == expected.accent,
      "Initial search and new-swarm colors use the saved palette")
    try checkTitlebar(tabs.isEmpty && !actionsEnabled && !newButton.isEnabled && !notificationButton.isEnabled,
      "Initial palette setup does not create or enable workspace controls")
  }

  func checkWindowGeometry(_ window: NSWindow) throws {
    let stripFrame = convert(bounds, to: nil)
    let close = window.standardWindowButton(.closeButton)!
    let zoom = window.standardWindowButton(.zoomButton)!
    let closeFrame = close.convert(close.bounds, to: nil)
    let zoomFrame = zoom.convert(zoom.bounds, to: nil)
    let newFrame = newButton.convert(newButton.bounds, to: nil)
    try checkTitlebar(bounds.height >= 48, "Native title bar leaves room around the pill actions")
    for button in [createButton, openButton] {
      let labelWidth = (button.title as NSString).size(withAttributes: [.font: button.font!]).width
      try checkTitlebar(button.frame.minY >= 6 && bounds.height - button.frame.maxY >= 6 && button.frame.width - labelWidth >= 32,
        "\(button.title) has vertical breathing room and readable horizontal padding")
    }
    try checkTitlebar(stripFrame.minX >= zoomFrame.maxX + 12, "Tab row leaves room beside native traffic lights")
    try checkTitlebar(abs(newFrame.midY - closeFrame.midY) <= 1, "Tab controls align vertically with native traffic lights")
    try checkTitlebar(abs(stripFrame.minY - window.contentLayoutRect.maxY) <= 1, "Tab row meets content without a second toolbar row")
    try checkActiveVisible()
  }

  func checkActiveVisible() throws {
    guard let active = tabs.first(where: { $0.swarmId == activeId }) else {
      throw TitlebarCheckFailure(message: "Selected tab exists")
    }
    let visible = scroll.documentVisibleRect
    try checkTitlebar(active.frame.minX >= visible.minX - 1, "Selected tab's leading edge is visible after layout")
    try checkTitlebar(active.frame.maxX <= visible.maxX + 1, "Selected tab's trailing edge is visible after layout")
  }

  func runChecks() throws {
    let rows = (0..<24).map { ["id": "swarm-\($0)", "name": "Swarm \($0)"] }
    var events: [String] = []
    emit = { method, _ in events.append(method) }
    func state(_ rows: [[String: String]], active: String, enabled: Bool = true) -> [String: Any] {
      ["tabs": rows, "activeId": active, "enabled": enabled, "attention": 2]
    }
    update(state(rows, active: "swarm-11"))
    let hover = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
      timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
    func click(_ count: Int, at point: NSPoint, time: TimeInterval) -> NSEvent {
      NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
        timestamp: time, windowNumber: 0, context: nil, eventNumber: count,
        clickCount: count, pressure: 1)!
    }
    try checkTitlebar(!ownsBackgroundDoubleClick(click(2, at: NSPoint(x: 40, y: 20), time: 1)),
      "A second click displaced from a closed tab cannot zoom the window")
    try checkTitlebar(!ownsBackgroundDoubleClick(click(1, at: NSPoint(x: 40, y: 20), time: 2)),
      "The first titlebar-background click starts a local sequence")
    try checkTitlebar(ownsBackgroundDoubleClick(click(2, at: NSPoint(x: 40, y: 20), time: 2.1)),
      "A double-click wholly on titlebar background still zooms the window")
    try checkTitlebar(tabs[0].showsDivider && tabs[1].showsDivider, "Idle neighboring tabs have separators")
    try tabs[1].checkCloseVisibility(false)
    tabs[1].mouseEntered(with: hover)
    try tabs[1].checkCloseVisibility(true)
    try tabs[0].checkCloseVisibility(false)
    try checkTitlebar(!tabs[0].showsDivider && !tabs[1].showsDivider, "Hover clears separators on both sides of the tab")
    tabs[1].mouseExited(with: hover)
    try tabs[1].checkCloseVisibility(false)
    try checkTitlebar(tabs[0].showsDivider && tabs[1].showsDivider, "Separators return when the pointer leaves")
    try checkTitlebar(!tabs[10].showsDivider && !tabs[11].showsDivider, "Selected tab remains joined without neighboring separators")
    try checkTitlebar(tabs.count == 24, "All overflow tabs exist")
    try checkTitlebar(!newButton.isEnabled, "New Harness is disabled at capacity")
    for (index, tab) in tabs.enumerated() {
      try tab.checkAccessibility(expectedName: "Swarm \(index)", active: index == 11)
    }
    try checkActiveVisible()
    scroll.contentView.scroll(to: .zero)
    scroll.reflectScrolledClipView(scroll.contentView)
    let browsingOrigin = scroll.documentVisibleRect.origin
    var refreshed = state(rows, active: "swarm-11")
    var renamedRows = rows
    renamedRows[0]["name"] = "Background task renamed"
    refreshed["tabs"] = renamedRows
    update(refreshed)
    try checkTitlebar(scroll.documentVisibleRect.origin == browsingOrigin,
      "A background title update preserves the tabs the user scrolled to")
    refreshed["palette"] = ["workspace": Int64(0xff252d43)]
    update(refreshed)
    try checkTitlebar(scroll.documentVisibleRect.origin == browsingOrigin,
      "A palette update does not undo manual tab scrolling")
    update(state(rows, active: "swarm-23"))
    try checkActiveVisible()
    setFrameSize(NSSize(width: 320, height: 52))
    needsLayout = true
    layoutSubtreeIfNeeded()
    try checkActiveVisible()

    let original = tabs[0]
    let reversed = Array(rows.reversed())
    update(state(reversed, active: "swarm-0"))
    try checkTitlebar(tabs.last === original, "Reordering retains existing tab controls")
    try checkTitlebar(tabs.map(\.swarmId) == reversed.map { $0["id"]! }, "Tab order follows the saved Swarm order")
    let accessibleTabs = document.accessibilityChildren()?.compactMap { $0 as? SwarmTabButton } ?? []
    try checkTitlebar(accessibleTabs.map(\.swarmId) == tabs.map(\.swarmId), "Accessible tab order follows visual order after reordering")
    try checkActiveVisible()

    update(state([["id": "swarm-0", "name": "Renamed tab"]], active: "swarm-0"))
    try checkTitlebar(tabs.count == 1 && tabs[0] === original, "Closing tabs retains the surviving control")
    try original.checkAccessibility(expectedName: "Renamed tab", active: true)
    try checkTitlebar(newButton.isEnabled, "New Harness returns below capacity")
    try checkTitlebar(newButton.toolTip == nil && createButton.toolTip == nil && openButton.toolTip == nil,
      "Titlebar actions add no hover hints")
    try checkTitlebar(notificationButton.frame.maxX <= scroll.frame.minX,
      "The bell is before the tabs beside the traffic lights")
    try checkTitlebar((newButton.isHidden || newButton.frame.maxX <= createButton.frame.minX) && scroll.frame.maxX <= createButton.frame.minX && createButton.frame.maxX < openButton.frame.minX,
      "New and Open Harness have separate targets on the right")
    try checkTitlebar(createButton.title == "New Harness" && openButton.title == "Open Harness",
      "Creation and opening are explicit in the titlebar")
    try checkTitlebar(!subviews.contains(where: { $0 is NSTextField }), "The titlebar has no competing text editor")
    events.removeAll()
    newButton.performClick(nil)
    notificationButton.performClick(nil)
    createButton.performClick(nil)
    openButton.performClick(nil)
    try checkTitlebar(events == ["new", "notifications", "newAgent", "addAgent"],
      "The new tab, notification, create and open buttons dispatch separate actions once")
    try checkTitlebar(notificationButton.hasAttention, "The bell represents pending agent attention")
    let oldButton = newButton
    var themedState = state([["id": "swarm-0", "name": "Renamed tab"]], active: "swarm-0")
    themedState["palette"] = ["workspace": Int64(0xff252d43), "search": Int64(0xff262f46)]
    update(themedState)
    try checkTitlebar(newButton === oldButton && tabs[0] === original,
      "Palette changes retain native control identity")
    try checkTitlebar(newButton.contentTintColor == palette.accent && notificationButton.contentTintColor == palette.accent,
      "Both toolbar icons receive the coordinated palette")
    events.removeAll()
    try original.checkEnabled(true)
    original.clickBothActions()
    try checkTitlebar(events == ["select", "close"], "Native selection and close dispatch once each")

    events.removeAll()
    update(state([["id": "swarm-0", "name": "Renamed tab"]], active: "swarm-0", enabled: false))
    try original.checkEnabled(false)
    try checkTitlebar(!newButton.isEnabled && !notificationButton.isEnabled && !createButton.isEnabled && !openButton.isEnabled, "Titlebar actions disable with a modal")
    original.clickBothActions()
    newButton.performClick(nil)
    notificationButton.performClick(nil)
    createButton.performClick(nil)
    openButton.performClick(nil)
    try checkTitlebar(events.isEmpty, "Disabled controls emit no actions")
    try checkDragOperations()
  }
}

private extension SwarmTabStrip {
  func checkTabKeyboardFocus(_ window: NSWindow, messenger: TitlebarCheckMessenger) throws {
    update(["enabled": true, "activeId": "keyboard-23",
      "tabs": (0..<24).map { ["id": "keyboard-\($0)", "name": "Keyboard \($0)"] }])
    let tab = tabs[0]
    let buttons = tab.accessibilityChildren()!.compactMap { $0 as? NSButton }
    for button in buttons {
      try checkTitlebar(window.makeFirstResponder(button), "An enabled tab action accepts keyboard focus")
      try tab.checkCloseVisibility(true)
      try checkTitlebar(scroll.documentVisibleRect.contains(tab.frame),
        "Keyboard focus reveals the entire overflowed tab and close control")
      try checkTitlebar(activeId == "keyboard-23", "Focusing a tab control does not activate its swarm")
      let before = messenger.calls.count
      messenger.holdReplies = true
      button.performClick(nil)
      try checkTitlebar(window.firstResponder === button,
        "Typing stays out of the old workspace until the tab action is acknowledged")
      messenger.finishNextReply()
      try checkTitlebar(window.firstResponder === window.contentViewController,
        "Activating a tab action returns the next key to Flutter content")
      try tab.checkCloseVisibility(false)
      try checkTitlebar(messenger.calls.count == before + 1, "Each native tab activation sends one action")
    }
    tab.attention = true
    try checkTitlebar(buttons[0].accessibilityHelp()?.contains("needing input") == true,
      "The attention dot has an accessible description")
    tab.attention = false
    try checkTitlebar(buttons[0].accessibilityHelp() == nil, "Resolved attention clears its accessible description")
    try checkTitlebar(window.makeFirstResponder(buttons[0]), "Rename starts from an actual focused control")
    let rename = tab.menu!.items.first!
    NSApp.sendAction(rename.action!, to: rename.target, from: rename)
    messenger.finishNextReply()
    try checkTitlebar(window.firstResponder === window.contentViewController && messenger.calls.last?.method == "rename",
      "Renaming gives the Flutter form native keyboard ownership")
    let stale = tab
    update(["enabled": true, "activeId": "survivor", "tabs": [["id": "survivor", "name": "Survivor"]]])
    let beforeStale = messenger.calls.count
    stale.clickBothActions()
    try checkTitlebar(messenger.calls.count == beforeStale, "A removed tab's retained controls cannot dispatch actions")
    try checkTitlebar(window.makeFirstResponder(newButton), "New swarm accepts keyboard focus")
    newButton.performClick(nil)
    messenger.finishNextReply()
    try checkTitlebar(window.firstResponder === window.contentViewController && messenger.calls.last?.method == "new",
      "New swarm returns keyboard ownership to the workspace")
    let current = tabs[0].accessibilityChildren()!.first as! NSButton
    window.makeFirstResponder(current)
    current.performClick(nil)
    window.makeFirstResponder(newButton)
    newButton.performClick(nil)
    messenger.finishNextReply()
    try checkTitlebar(window.firstResponder === newButton,
      "A delayed tab reply cannot steal focus from a newer search action")
    messenger.finishNextReply()
    try checkTitlebar(window.firstResponder === window.contentViewController,
      "The search button hands the next keystroke to the shared Flutter picker")
    window.makeFirstResponder(current)
    current.performClick(nil)
    current.performClick(nil)
    messenger.finishNextReply()
    try checkTitlebar(window.firstResponder === current, "An older tab action cannot release a newer action's focus")
    messenger.finishNextReply()
    try checkTitlebar(window.firstResponder === window.contentViewController,
      "The latest acknowledged tab action restores content focus")
    for (button, method) in [(notificationButton, "notifications")] {
      window.makeFirstResponder(button)
      let before = messenger.calls.count
      button.performClick(nil)
      try checkTitlebar(messenger.calls.count == before + 1 && messenger.calls.last?.method == method,
        "The toolbar action dispatches once")
      try checkTitlebar(window.firstResponder === button,
        "The toolbar waits for Flutter's destination focus tree")
      messenger.finishNextReply()
      try checkTitlebar(window.firstResponder === window.contentViewController,
        "Notification control returns keyboard ownership to Flutter")
    }
    messenger.holdReplies = false
  }
}

private final class TitlebarCheckDrag: NSObject, NSDraggingInfo {
  var draggingDestinationWindow: NSWindow?
  var draggingSourceOperationMask: NSDragOperation = .move
  var draggingLocation = NSPoint.zero
  var draggedImageLocation = NSPoint.zero
  var draggedImage: NSImage? { nil }
  let draggingPasteboard = NSPasteboard.withUniqueName()
  var draggingSource: Any?
  var draggingSequenceNumber: Int { 1 }
  var draggingFormation: NSDraggingFormation = .none
  var animatesToDestination = false
  var numberOfValidItemsForDrop = 1
  var springLoadingHighlight: NSSpringLoadingHighlight { .none }
  func slideDraggedImage(to screenPoint: NSPoint) {}
  override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
  func resetSpringLoading() {}
  func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass],
    searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
  deinit { draggingPasteboard.releaseGlobally() }
}

private extension SwarmTabStrip {
  func checkDragOperations() throws {
    setFrameSize(NSSize(width: 900, height: 52))
    let rows = (0..<4).map { ["id": "drag-\($0)", "name": "Drag \($0)"] }
    update(["tabs": rows, "activeId": "drag-0", "enabled": true])
    var moves: [[String: Any]] = []
    emit = { method, args in if method == "reorder", let args = args as? [String: Any] { moves.append(args) } }
    let info = TitlebarCheckDrag()
    info.draggingSource = tabs[0]
    info.draggingPasteboard.setString("drag-0", forType: swarmPasteboardType)
    info.draggingLocation = document.convert(NSPoint(x: tabs[2].frame.midX + 1, y: 20), to: nil)
    try checkTitlebar(draggingEntered(info) == .move && draggingUpdated(info) == .move,
      "An owned tab can move within the visible tab area")
    try checkTitlebar(performDragOperation(info) && moves.last?["index"] as? Int == 2,
      "Moving right accounts for removing the source tab first")
    moves.removeAll()
    info.draggingLocation = document.convert(NSPoint(x: tabs[0].frame.midX - 1, y: 20), to: nil)
    try checkTitlebar(performDragOperation(info) && moves.isEmpty, "Dropping in place performs no redundant reorder")
    info.draggingSource = tabs[3]
    info.draggingPasteboard.setString("drag-3", forType: swarmPasteboardType)
    try checkTitlebar(performDragOperation(info) && moves.last?["index"] as? Int == 0,
      "Moving left preserves the requested first position")
    moves.removeAll()
    func rejected(_ reason: String) throws {
      try checkTitlebar(draggingEntered(info).isEmpty && draggingUpdated(info).isEmpty && !performDragOperation(info), reason)
      try checkTitlebar(moves.isEmpty, "Rejected drag emits no reorder")
    }
    info.draggingLocation = convert(NSPoint(x: newButton.frame.midX, y: 20), to: nil)
    try rejected("Search is not a tab drop target")
    info.draggingLocation = document.convert(NSPoint(x: tabs[0].frame.midX, y: 20), to: nil)
    info.draggingSource = SwarmTabButton(id: "drag-3")
    try rejected("A foreign tab with a matching ID cannot reorder this strip")
    info.draggingSource = tabs[3]
    info.draggingSourceOperationMask = .copy
    try rejected("A copy-only source is not advertised as movable")
    info.draggingSourceOperationMask = .move
    info.draggingPasteboard.setString("drag-0", forType: swarmPasteboardType)
    try rejected("The pasteboard identity must match the actual dragged tab")
    info.draggingPasteboard.setString("drag-3", forType: swarmPasteboardType)
    update(["tabs": rows, "activeId": "drag-0", "enabled": false])
    try rejected("A modal rejects a pending tab drop")
    update(["tabs": Array(rows.prefix(3)), "activeId": "drag-0", "enabled": true])
    try rejected("A removed source cannot finish its pending drag")
  }
}

// No engine, account, terminal or transport is involved in native layout.
private final class TitlebarCheckMessenger: NSObject, FlutterBinaryMessenger {
  var calls: [FlutterMethodCall] = []
  private var handlers: [String: FlutterBinaryMessageHandler] = [:]
  var holdReplies = false
  var replies: [FlutterBinaryReply] = []
  func finishNextReply() {
    replies.removeFirst()(FlutterStandardMethodCodec.sharedInstance().encodeSuccessEnvelope(nil))
  }
  func send(onChannel channel: String, message: Data?) {
    if let message { calls.append(FlutterStandardMethodCodec.sharedInstance().decodeMethodCall(message)) }
  }
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    send(onChannel: channel, message: message)
    if let callback {
      if holdReplies { replies.append(callback) }
      else { callback(FlutterStandardMethodCodec.sharedInstance().encodeSuccessEnvelope(nil)) }
    }
  }
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    handlers[channel] = handler
    return 1
  }
  func receive(_ method: String, arguments: [String: Any]) throws -> Data? {
    guard let handler = handlers["harness/swarm_tabs"] else {
      throw TitlebarCheckFailure(message: "Native channel handler is installed")
    }
    var reply: Data?
    let message = FlutterStandardMethodCodec.sharedInstance().encode(
      FlutterMethodCall(methodName: method, arguments: arguments))
    handler(message) { reply = $0 }
    return reply
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

private extension SwarmTitlebar {
  func checkKeymapRuntime(_ fixture: [String: [String: Any]], messenger: TitlebarCheckMessenger) throws {
    guard let window, let defaults = HarnessNativeKeymap(fixture["defaults"]!),
          let changed = HarnessNativeKeymap(fixture["changed"]!) else {
      throw TitlebarCheckFailure(message: "Exported runtime keymaps exist")
    }
    let original = NSApp.mainMenu!
    let edit = original.item(withTitle: "Edit")!.submenu!
    let agent = original.item(withTitle: "File")!.submenu!
    let newSwarm = agent.items.first(where: { $0.representedObject as? String == "new" })!
    let nativeCopy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(nativeCopy)
    setKeymap(defaults)
    let main = NSApp.mainMenu as! HarnessKeymapMenu
    try checkTitlebar(main !== original && main.item(withTitle: "Edit")?.submenu === edit,
      "The main-menu dispatcher retains the actual Edit submenu and its targets")
    try checkTitlebar(newSwarm.keyEquivalent == "t" && newSwarm.toolTip == nil,
      "Native shortcuts display in the menu without duplicate hover hints")
    setKeymap(changed)
    try checkTitlebar(NSApp.mainMenu === main && newSwarm.keyEquivalent == "o",
      "Hot reload updates the existing menu to the remapped key")
    try checkTitlebar(nativeCopy.keyEquivalent == "c" && nativeCopy.action == #selector(NSText.copy(_:)),
      "Standard native editing remains intact")
    // The inherited default is still first; a sequence is not falsely shown
    // as a second one-stroke accelerator in AppKit's shortcut column.
    let onlySequence = HarnessNativeKeymap(["version": 1, "contexts": Dictionary(uniqueKeysWithValues:
      ["workspace", "terminal", "picker"].map { ($0, [["keys": ["cmd+k", "n"], "command": "swarm.new",
        "hint": "⌘K N", "repeatable": false, "menuAction": "new"]]) })])!
    setKeymap(onlySequence)
    try checkTitlebar(newSwarm.keyEquivalent.isEmpty && newSwarm.toolTip == nil,
      "Sequences add no hover hints or misleading first-key menu shortcut")
    setKeymap(HarnessNativeKeymap(["version": 1, "contexts": ["workspace": [], "terminal": [], "picker": []]])!)
    try checkTitlebar(newSwarm.keyEquivalent.isEmpty && newSwarm.toolTip == nil,
      "Unbinding clears the old native shortcut and hint")
    rebuildHistoryMenu()
    try checkTitlebar(historyMenu.items.allSatisfy { $0.keyEquivalent.isEmpty },
      "Rebuilt History rows retain effective unbindings")
    setKeymap(changed)
    actionsEnabled = true
    func event(_ text: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
      NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: text,
        charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    }
    let open = event("o", 31, .command)
    let oldOpen = event("t", 17, .command)
    try checkTitlebar(main.defersToInput(open) && !main.defersToInput(oldOpen),
      "The menu yields the remapped search shortcut to Flutter")
    try checkTitlebar(!main.performKeyEquivalent(with: open), "Menu equivalents defer before input dispatch")
    setKeymap(defaults)
    try checkTitlebar(strip.newButton.toolTip == nil, "Keymap reload does not restore hover hints")
    try checkTitlebar(strip.newButton.accessibilityLabel() == "New Tab", "The plus announces New Harness")
    try checkTitlebar(!main.defersToInput(event("p", 35, .command)), "Command-P no longer opens Navigate")
    try checkTitlebar(main.defersToInput(event("p", 35, [.command, .shift])), "Command-Shift-P reaches command search")
    flutterKeyContext = "picker"
    syncMenuKeys()
    try checkTitlebar(!main.performKeyEquivalent(with: event("\u{f701}", 125)), "Result arrows are owned by the shared picker")
    try checkTitlebar(!main.defersToInput(event("a", 0, .command)), "Standard select-all retains native text-editing dispatch")
  }

  func checkNativeContainer(messenger: TitlebarCheckMessenger) throws {
    guard let window else { throw TitlebarCheckFailure(message: "Native test window exists") }
    let main = NSMenu()
    let appItem = NSMenuItem(title: "Harness", action: nil, keyEquivalent: "")
    appItem.submenu = NSMenu(title: "Harness")
    appItem.submenu?.addItem(NSMenuItem(title: "Preferences…", action: nil, keyEquivalent: ","))
    main.addItem(appItem)
    let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    edit.submenu = NSMenu(title: "Edit")
    let find = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
    find.submenu = NSMenu(title: "Find")
    find.submenu?.addItem(NSMenuItem(title: "Find and Replace…", action: nil, keyEquivalent: "f"))
    edit.submenu?.addItem(find)
    main.addItem(edit)
    for title in ["View", "Window", "Help"] {
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.submenu = NSMenu(title: title)
      main.addItem(item)
    }
    NSApp.mainMenu = main
    let startupColors: [String: Any] = [
      "tabBar": Int64(0xff1b2720), "workspace": Int64(0xff2b3b31),
      "search": Int64(0xff293a31), "accent": Int64(0xffb4d8be),
    ]
    let reply = try messenger.receive("configure", arguments: ["palette": startupColors])
    try checkTitlebar(reply == FlutterStandardMethodCodec.sharedInstance().encodeSuccessEnvelope(true),
      "Native configure acknowledges the initial palette synchronously")
    let startupPalette = SwarmNativePalette(startupColors)
    try checkTitlebar(strip.palette == startupPalette && window.backgroundColor == startupPalette.tabBar,
      "The saved palette reaches native chrome before any workspace update")
    try strip.checkStartupPalette(startupPalette)
    configure()
    try checkTitlebar(strip.palette == startupPalette && window.titlebarAccessoryViewControllers.count == 1,
      "Repeated configuration preserves the saved palette and one titlebar accessory")
    _ = try messenger.receive("update", arguments: [
      "tabs": [["id": "startup-check", "name": "Synthetic swarm"]],
      "activeId": "startup-check", "enabled": true, "palette": startupColors,
    ])
    // SwarmScreen.dispose sends this when sign-in or setup takes its place.
    _ = try messenger.receive("update", arguments: ["tabs": [], "enabled": false])
    try checkTitlebar(window.backgroundColor == startupPalette.tabBar,
      "Leaving the workspace preserves the saved native background")
    try strip.checkStartupPalette(startupPalette)
    try checkTitlebar(window.firstResponder === window.contentViewController,
      "Adding toolbar buttons does not take initial keyboard focus from the workspace")
    try checkTitlebar(main.items.map(\.title) == ["Harness", "File", "Edit", "View", "History", "Models", "Machines", "Window", "Help"], "File leads the standard macOS menus, with Machines after Models")
    let settings = appItem.submenu!.items[0]
    try checkTitlebar(settings.title == "Settings…" && settings.representedObject as? String == "settings", "Settings stays in the application menu")
    let agent = main.item(withTitle: "File")!.submenu!
    let historyMenu = main.item(withTitle: "History")!.submenu!
    try checkTitlebar(agent.items.map { $0.isSeparatorItem ? "separator" : ($0.representedObject as? String ?? "") } == ["new", "newAgent", "addAgent", "renameActive", "closeActive", "separator", "splitRight", "splitDown", "zoomPane", "closePane"], "File groups Harness and Pane actions, without Pin or Add Project clutter")
    try checkTitlebar(agent.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.image != nil && $0.toolTip == nil },
      "Every File action has a native icon and no hover hint")
    try checkTitlebar(agent.items.contains { $0.title == "Rename Harness…" && $0.representedObject as? String == "renameActive" }, "Rename Harness preserves its command")
    try checkTitlebar(agent.items.contains { $0.title == "Close Harness" && $0.representedObject as? String == "closeActive" }, "Close Harness preserves its command")
    let commands = edit.submenu!.items.first(where: { $0.representedObject as? String == "commands" })!
    try checkTitlebar(commands.keyEquivalent == "p" && commands.keyEquivalentModifierMask == [.command, .shift], "Command search keeps its native menu owner")
    try checkTitlebar(edit.submenu!.items.allSatisfy { $0.representedObject as? String != "jump" }, "Edit has no Navigate action")
    try checkTitlebar(agent.items.first?.title == "New Tab" && agent.items.first?.keyEquivalent == "t", "New Tab opens the chooser with Command-T")
    let reopen = historyMenu.items.first(where: { $0.representedObject as? String == "reopen" })!
    actionsEnabled = true
    canReopen = false
    try checkTitlebar(!validateMenuItem(reopen), "Closed-Swarm recovery is disabled with an empty history")
    canReopen = true
    try checkTitlebar(validateMenuItem(reopen), "Closed-Swarm recovery becomes available")
    let closePane = agent.items.first(where: { $0.representedObject as? String == "closePane" })!
    canClosePane = false
    try checkTitlebar(!validateMenuItem(closePane), "Remove Agent is disabled in New swarm")
    canClosePane = true
    try checkTitlebar(validateMenuItem(closePane), "Remove Agent is enabled for a focused pane")
    let create = agent.items.first(where: { $0.representedObject as? String == "new" })!
    canCreateSwarm = false
    try checkTitlebar(!validateMenuItem(create), "Native New Swarm respects the tab capacity")
    canCreateSwarm = true
    try checkTitlebar(validateMenuItem(create), "Native New Swarm returns below capacity")
    let machineRows: [[String: Any]] = [
      ["id": "office", "name": "iMac – Office", "status": "Online", "local": true],
      ["id": "home", "name": "iMac – Home", "status": "Offline", "local": false],
    ]
    updateMachines(machineRows)
    let machineMenu = main.item(withTitle: "Machines")!.submenu!
    let manager = machineMenu.items.first!
    try checkTitlebar(manager.title == "Open Machines Manager" && manager.representedObject as? String == "manageMachines" && machineMenu.items[1].isSeparatorItem,
      "Machines Manager leads the menu before linked computers")
    menuAction(manager)
    try checkTitlebar(messenger.calls.last?.method == "manageMachines",
      "Machines Manager opens through the Flutter command bridge")
    let destinations = machineMenu.items.filter { $0.action == #selector(machineAction(_:)) }
    try checkTitlebar(destinations.map { $0.representedObject as? String } == ["office", "home"],
      "Machines lists each linked computer as a destination")
    try checkTitlebar(destinations[0].attributedTitle?.string.contains("Online") == true &&
      destinations[1].attributedTitle?.string.contains("Offline") == true,
      "Machine availability is visible before opening its agent search")
    try checkTitlebar(machineMenu.items.compactMap { $0.representedObject as? String }.suffix(2) == ["linkMachine", "refreshMachines"],
      "Machines exposes Link and Refresh after the computer list")
    let machineCallCount = messenger.calls.count
    machineAction(destinations[0])
    try checkTitlebar(messenger.calls.count == machineCallCount + 1 &&
      messenger.calls.last?.method == "machineDestination" &&
      (messenger.calls.last?.arguments as? [String: String])?["id"] == "office",
      "A computer sends its stable id to the shared agent search")
    actionsEnabled = false
    machineAction(destinations[1])
    try checkTitlebar(!validateMenuItem(destinations[1]) && messenger.calls.count == machineCallCount + 1,
      "A modal blocks machine destinations")
    actionsEnabled = true
    updateMachines(machineRows)
    try checkTitlebar(machineMenu.items.contains(where: { $0 === destinations[0] }),
      "Unchanged machine data retains menu controls")
    updateMachines([])
    try checkTitlebar(!validateMenuItem(destinations[0]) &&
      machineMenu.item(withTitle: "No Machines Linked")?.isEnabled == false,
      "Unlinking computers clears destinations and invalidates stale actions")
    let recentRows: [[String: Any]] = (0..<20).map { index -> [String: Any] in
      ["id": "agent:\(index)", "title": "Agent \(index) — Machine",
       "detail": "Project \(index)", "current": index == 0,
       "engine": index == 0 ? "claude" : "codex"]
    } + [["id": "swarm:recent", "title": "Recent Swarm", "swarm": true]]
    let closedRows: [[String: Any]] = (0..<14).map {
      ["id": "closed-\($0)", "title": "Closed Swarm \($0)", "detail": "3 agents", "swarm": true, "canReopen": true]
    }
    updateHistory(recentRows, closed: closedRows)
    let recentItems = historyMenu.items.filter { $0.action == #selector(historyAction(_:)) }
    let closedItems = historyMenu.items.filter { $0.action == #selector(closedHistoryAction(_:)) }
    try checkTitlebar(recentItems.count == 15 && closedItems.count == 10, "Chrome-style direct History sections remain bounded")
    try checkTitlebar(historyMenu.items.filter { !$0.isSeparatorItem }.prefix(2).map(\.title) == ["Back", "Forward"], "History begins with Back and Forward")
    try checkTitlebar(historyMenu.items.last?.title == "Show Full History" && historyMenu.items.last?.keyEquivalent == "y", "Full History uses Command-Y")
    try checkTitlebar(historyMenu.items.allSatisfy { $0.submenu == nil }, "Recent work is available without nested menus")
    let recent = recentItems[0]
    let closed = closedItems[0]
    try checkTitlebar(recent.image?.size == NSSize(width: 16, height: 16) && recent.image?.isTemplate == false,
      "History uses the colored Claude mark at native menu size")
    try checkTitlebar(recent.state == .on && recent.toolTip == nil, "History adds no hover hints")
    updateHistory(recentRows, closed: closedRows)
    try checkTitlebar(historyMenu.items.contains(where: { $0 === recent }), "Unchanged history retains native menu items")
    try checkTitlebar(validateMenuItem(closed), "A specific closed Swarm can be restored")
    canReopen = false
    try checkTitlebar(validateMenuItem(closed), "A chosen closure uses its own capacity, independently of the latest closure")
    var unavailableRows = closedRows
    unavailableRows[0]["canReopen"] = false
    updateHistory(recentRows, closed: unavailableRows)
    try checkTitlebar(!validateMenuItem(closed), "Specific restore respects its destination capacity")
    updateHistory(recentRows, closed: closedRows)
    canReopen = true
    let back = historyMenu.items[0]
    let forward = historyMenu.items[1]
    canGoBack = false
    canGoForward = true
    try checkTitlebar(!validateMenuItem(back) && validateMenuItem(forward), "Back and Forward have independent navigation availability")
    try checkTitlebar(validateMenuItem(recent), "Recent navigation is available in the shell")
    actionsEnabled = false
    try checkTitlebar(!validateMenuItem(recent) && !validateMenuItem(commands) && !validateMenuItem(settings), "History, commands and Settings cannot act behind a modal")
    for item in agent.items where !item.isSeparatorItem {
      try checkTitlebar(!validateMenuItem(item), "Workspace commands cannot act behind a modal")
    }
    actionsEnabled = true
    let iconRows: [[String: Any]] = [
      ["id": "single-harness", "title": "Architecture", "swarm": true,
       "agentCount": 1, "engine": "claude"],
      ["id": "group-harness", "title": "Project", "swarm": true,
       "agentCount": 2],
    ]
    updateHistory(iconRows, closed: iconRows)
    let singleItems = historyMenu.items.filter { $0.representedObject as? String == "single-harness" }
    let groupItems = historyMenu.items.filter { $0.representedObject as? String == "group-harness" }
    try checkTitlebar(singleItems.count == 2 && singleItems.allSatisfy {
      $0.image === historyIcons.image(engine: "claude", asset: nil)
    }, "Recently visited and closed single-agent harnesses show their agent icon")
    try checkTitlebar(groupItems.count == 2 && groupItems.allSatisfy {
      $0.image === SwarmIdentity.menuIcon
    }, "Multiple-agent harnesses retain the group icon")
    updateHistory([])
    try checkTitlebar(!validateMenuItem(recent), "A stale recent menu item cannot dispatch after its view disappears")
    try checkTitlebar(!validateMenuItem(closed), "A stale closed entry cannot restore another Swarm")
    try checkTitlebar(historyMenu.items.first(where: { $0.title == "No Recent Visits" })?.isEnabled == false, "An empty history is an inert placeholder")
    guard let menu = main.items.first(where: { $0.title == "View" })?.submenu,
          let attention = menu.items.first(where: { $0.representedObject as? String == "notifications" }) else {
      throw TitlebarCheckFailure(message: "View menu exposes harnesses needing input")
    }
    try checkTitlebar(attention.title == "Harnesses Needing Input…", "Native command names its destination")
    try checkTitlebar(attention.keyEquivalent == "i" && attention.keyEquivalentModifierMask == [.command, .shift], "Native attention shortcut matches Flutter")
    try checkTitlebar(attention.target === self && attention.action == #selector(menuAction(_:)), "Native attention command uses the guarded channel handler")
    actionsEnabled = false
    try checkTitlebar(!validateMenuItem(attention), "Native attention shortcut is disabled behind a modal")
    actionsEnabled = true
    try checkTitlebar(validateMenuItem(attention), "Native attention shortcut returns when the modal closes")
    try checkTitlebar(main.items.compactMap(\.submenu).flatMap(\.items).allSatisfy {
      !["Next Swarm", "Previous Swarm"].contains($0.title)
    }, "Next and Previous Swarm have no redundant menu rows")
    let modelRows: [[String: Any]] = [
      ["title": "Anthropic", "account": "aabbcc", "status": "12% remaining", "engine": "claude",
       "details": ["Limiting window: Session", "Session — 12% remaining · resets in 2h"]],
      ["title": "OpenAI", "status": "Not signed in", "engine": "codex",
       "details": ["Sign in to Codex to see usage"]],
    ]
    updateModels(modelRows)
    let models = main.item(withTitle: "Models")!.submenu!
    try checkTitlebar(models.items.filter { !$0.isSeparatorItem }.map(\.title) == [
      "Subscription", "Anthropic, aabbcc, 12% remaining", "OpenAI, Not signed in",
      "API", "OpenRouter", "fal.ai", "Local", "DeepSeek V4 Flash", "Qwen3.8-27B", "Add Model"
    ], "Models has the three requested sections and Add Model last")
    try checkTitlebar(models.items.filter(\.isSeparatorItem).count == 3,
      "Native separators distinguish the sections and future Add Model action")
    for title in ["OpenRouter", "fal.ai", "DeepSeek V4 Flash", "Qwen3.8-27B", "Add Model"] {
      let item = models.item(withTitle: title)!
      try checkTitlebar(!item.isEnabled && item.action == nil && item.target == nil && item.submenu == nil,
        "\(title) is greyed out and cannot dispatch or open anything")
    }
    let subscription = models.items.first(where: { $0.view is SwarmSubscriptionView })!
    let row = subscription.view as! SwarmSubscriptionView
    try checkTitlebar(subscription.submenu == nil && subscription.action == nil && !subscription.isEnabled,
      "Subscription balances have no arrow or fake action")
    try checkTitlebar(row.identity.stringValue == "Anthropic  aabbcc" && row.balance.stringValue == "12% remaining",
      "Provider and account are on the left; usage is a separate right column")
    try checkTitlebar(row.identity.frame.maxX + 24 <= row.balance.frame.minX && row.balance.frame.maxX == row.bounds.width - 18,
      "Account and balance have a clear gap and a consistent trailing inset")
    try checkTitlebar(row.identity.frame.midY == row.balance.frame.midY,
      "Both columns share a vertical center")
    try checkTitlebar(row.accessibilityLabel() == subscription.title,
      "VoiceOver can read the provider, account and remaining usage together")
    let secondRow = models.items.compactMap { $0.view as? SwarmSubscriptionView }.last!
    for view in [row, secondRow] {
      let cell = view.balance.cell!
      let drawing = cell.drawingRect(forBounds: view.balance.bounds)
      let glyphWidth = (view.balance.stringValue as NSString).size(withAttributes: [.font: view.balance.font!]).width
      try checkTitlebar(view.bounds.width >= 440 && drawing.width >= glyphWidth,
        "Remaining usage and sign-in status have enough actual text-cell width to display in full")
    }
    try checkTitlebar(secondRow.balance.frame.maxX == row.balance.frame.maxX,
      "Different balances align on their right edges")
    updateModels(modelRows)
    try checkTitlebar(models.items.contains(where: { $0 === subscription }),
      "Unchanged subscription data reuses native menu items")
    updateModels([])
    try checkTitlebar(models.items.allSatisfy { !$0.title.contains("12%") && $0.submenu == nil },
      "Signing out clears cached native account readings")
    let findItems = find.submenu?.items ?? []
    try checkTitlebar(findItems.map(\.title) == ["Find in Terminal…", "Find Next", "Find Previous"], "Find replaces the unused editor actions with terminal commands")
    try checkTitlebar(findItems.map(\.keyEquivalent) == ["f", "g", "g"], "Native find shortcuts match Flutter")
    try checkTitlebar(findItems.last?.keyEquivalentModifierMask == [.command, .shift], "Previous match uses Shift-Command-G")
    for item in findItems {
      canFind = false
      try checkTitlebar(!validateMenuItem(item), "Find is disabled without a focused terminal")
      canFind = true
      try checkTitlebar(validateMenuItem(item), "Find is enabled for a focused terminal")
      actionsEnabled = false
      try checkTitlebar(!validateMenuItem(item), "Find cannot run behind a modal")
      actionsEnabled = true
      try checkTitlebar(item.target === self && item.action == #selector(menuAction(_:)), "Find uses the guarded channel handler")
    }
    strip.update([
      "enabled": true, "activeId": "swarm-11",
      "tabs": (0..<12).map { ["id": "swarm-\($0)", "name": "Swarm \($0)"] },
    ])
    for width in [880.0, 1280.0, 1920.0] {
      window.setContentSize(NSSize(width: width, height: 700))
      window.contentView?.superview?.layoutSubtreeIfNeeded()
      resize()
      window.contentView?.superview?.layoutSubtreeIfNeeded()
      strip.layoutSubtreeIfNeeded()
      try strip.checkWindowGeometry(window)
    }
    try strip.checkTabKeyboardFocus(window, messenger: messenger)
    try checkTitlebar(!window.isVisible, "Native layout check never displays its window")
  }
}

private final class TitlebarCheckContentController: NSViewController {
  override var acceptsFirstResponder: Bool { true }
}

let titlebarCheckApp = NSApplication.shared
titlebarCheckApp.setActivationPolicy(.prohibited)
titlebarCheckApp.appearance = NSAppearance(named: .darkAqua)
do {
  let paletteValues: [String: Any] = [
    "tabBar": Int64(0xff1b2030), "workspace": Int64(0xff252d43),
    "search": Int64(0xff262f46), "accent": Int64(0xffb1c7f5),
  ]
  let palette = SwarmNativePalette(paletteValues)
  let searchColor = palette.search.usingColorSpace(.sRGB)!
  try checkTitlebar(abs(searchColor.redComponent - 38.0 / 255) < 0.0001 && abs(searchColor.blueComponent - 70.0 / 255) < 0.0001,
    "Native search uses the exact palette channels supplied by Flutter")
  try checkTitlebar(SwarmNativePalette(["search": -1, "tabBar": "invalid"]) == SwarmNativePalette(),
    "Malformed palette data retains readable native defaults")
  let historyRow = SwarmHistoryEntry([
    "id": "agent", "title": "Build a toy", "machineName": "MacBook Pro M2", "engine": "codex",
  ])!
  let label = historyRow.menuTitle
  try checkTitlebar(label.string == "Build a toy\tMacBook Pro M2", "Agent and machine occupy separate native menu columns")
  let paragraph = label.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
  try checkTitlebar(paragraph.tabStops.count == 1 && paragraph.tabStops[0].alignment == .right && paragraph.tabStops[0].location == 660,
    "Machine labels share a right-aligned column")
  let longRow = SwarmHistoryEntry(["id": "long", "title": String(repeating: "Long title ", count: 100), "machineName": "Mac"])!
  try checkTitlebar(longRow.menuTitle.string.contains("…\tMac"), "Long titles truncate before the machine column")
  let swarmRow = SwarmHistoryEntry(["id": "swarm", "title": "My swarm", "swarm": true])!
  try checkTitlebar(swarmRow.menuTitle.string == "My swarm", "Empty swarm rows have no invented machine label")
  let sharedSwarm = SwarmHistoryEntry(["id": "shared", "title": "Workshop", "swarm": true, "machineName": "2 machines"])!
  try checkTitlebar(sharedSwarm.menuTitle.string == "Workshop\t2 machines", "Swarm machine counts use the same trailing column as agent machines")
  var assetReads = 0
  let icons = SwarmHistoryIcons(assetURL: { asset in
    assetReads += 1
    guard let root = ProcessInfo.processInfo.environment["HARNESS_TITLEBAR_ASSETS"] else { return nil }
    return URL(fileURLWithPath: root).appendingPathComponent(String(asset.dropFirst("assets/".count)))
  })
  for engine in ["codex", "grok", "cursor", "opencode"] {
    let asset = "assets/engine-icons/\(engine).png"
    let icon = icons.image(engine: engine, asset: asset)
    try checkTitlebar(icon.size == NSSize(width: 16, height: 16) && !icon.isTemplate, "\(engine) uses its colored bundled mark")
    try checkTitlebar(icons.image(engine: engine, asset: asset) === icon, "Repeated \(engine) history reuses its decoded icon")
  }
  try checkTitlebar(assetReads == 4, "Native history loads each bundled mark only once")
  let unknown = icons.image(engine: "custom", asset: nil)
  try checkTitlebar(unknown.isTemplate && unknown.size == NSSize(width: 16, height: 16), "Unknown engines have a native-size adaptive initial")
  let strip = SwarmTabStrip(frame: NSRect(x: 0, y: 0, width: 900, height: 52))
  try strip.runChecks()
  try strip.checkAgentIdentity()
  try checkTitlebar(titlebarCheckApp.windows.isEmpty, "Checks never open an application window")
  if CommandLine.arguments.contains("--window-layout") {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 700),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let content = TitlebarCheckContentController()
    content.view = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 700))
    window.contentViewController = content
    let messenger = TitlebarCheckMessenger()
    let titlebar = SwarmTitlebar(window: window, messenger: messenger)
    try titlebar.checkNativeContainer(messenger: messenger)
    if let path = ProcessInfo.processInfo.environment["HARNESS_TITLEBAR_KEYMAP_FIXTURE"] {
      let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: [String: Any]]
      try titlebar.checkKeymapRuntime(fixture, messenger: messenger)
    }
    window.close()
    print("AppKit Swarm titlebar: \(titlebarCheckCount) checks passed, including native window layout; no windows displayed.")
  } else {
    print("AppKit Swarm titlebar: \(titlebarCheckCount) checks passed; no windows opened.")
  }
} catch {
  let message = (error as? TitlebarCheckFailure)?.message ?? String(describing: error)
  FileHandle.standardError.write(Data("AppKit Swarm titlebar failed: \(message)\n".utf8))
  exit(1)
}
