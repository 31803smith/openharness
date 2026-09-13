import Cocoa
import FlutterMacOS
import ImageIO

/// Real AppKit controls in the title bar, beside the system traffic lights.
/// https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller/layoutattribute
final class SwarmTitlebar: NSObject, NSMenuItemValidation, NSMenuDelegate {
  private weak var window: NSWindow?
  private let channel: FlutterMethodChannel
  private let accessory = NSTitlebarAccessoryViewController()
  private let strip = SwarmTabStrip(frame: NSRect(x: 0, y: 0, width: 900, height: 40))
  private var observers: [NSObjectProtocol] = []
  private var configured = false
  private var actionsEnabled = false
  private var canReopen = false
  private var canFind = false
  private var canClosePane = false
  private var canCreateSwarm = false
  private let historyMenu = NSMenu(title: "History")
  private var canGoBack = false
  private var canGoForward = false
  private var history: [SwarmHistoryEntry] = []
  private var closedHistory: [SwarmHistoryEntry] = []
  private let historyIcons = SwarmHistoryIcons()
  private let modelsMenu = NSMenu(title: "Models")
  private var subscriptions: [SwarmSubscriptionEntry] = []

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(name: "harness/swarm_tabs", binaryMessenger: messenger)
    super.init()
    strip.emit = { [weak self] method, args in self?.channel.invokeMethod(method, arguments: args) }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "configure":
        self.configure()
        result(true)
      case "update":
        let state = call.arguments as? [String: Any] ?? [:]
        let wasEnabled = self.actionsEnabled
        self.actionsEnabled = state["enabled"] as? Bool == true
        if wasEnabled != self.actionsEnabled { self.updateModelsAvailability() }
        self.canReopen = state["canReopen"] as? Bool == true
        self.canFind = state["canFind"] as? Bool == true
        self.canClosePane = state["canClosePane"] as? Bool == true
        self.canGoBack = state["canGoBack"] as? Bool == true
        self.canGoForward = state["canGoForward"] as? Bool == true
        self.canCreateSwarm = (state["tabs"] as? [Any] ?? []).count < 24
        self.updateHistory(state["history"] as? [[String: Any]] ?? [], closed: state["closedHistory"] as? [[String: Any]] ?? [])
        self.strip.update(state)
        result(nil)
      case "focusSearch":
        self.strip.focusSearch(selectAll: (call.arguments as? [String: Any])?["selectAll"] as? Bool == true)
        result(nil)
      case "searchState":
        self.strip.setSearchState(call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "closeSearch":
        self.strip.closeSearch()
        result(nil)
      case "modelsState":
        let state = call.arguments as? [String: Any] ?? [:]
        self.updateModels(state["subscriptions"] as? [[String: Any]] ?? [])
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification,
                 NSWindow.didExitFullScreenNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
        [weak self] _ in self?.resize()
      })
    }
    // Keep an in-progress search and its native input owner across app switches.
    // Cancelling on window blur would return the next typed key to an agent.
  }

  deinit { observers.forEach(NotificationCenter.default.removeObserver) }

  private func configure() {
    guard let window, !configured else { return }
    configured = true
    NSWindow.allowsAutomaticWindowTabbing = false
    window.tabbingMode = .disallowed
    window.title = "Harness V2"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.styleMask.remove(.fullSizeContentView)
    window.backgroundColor = NSColor(srgbRed: 0.20, green: 0.16, blue: 0.21, alpha: 1)
    // AppKit fixes a right accessory's height to the title bar. A taller view
    // alone is clipped. A compact unified toolbar gives the native traffic
    // lights and the tab strip one 40-point row, without a second toolbar row.
    let toolbar = NSToolbar(identifier: "harness.swarm.titlebar")
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    window.toolbar = toolbar
    window.toolbarStyle = .unifiedCompact
    window.titlebarSeparatorStyle = .none
    accessory.layoutAttribute = .right
    accessory.view = strip
    window.addTitlebarAccessoryViewController(accessory)
    resize()
    installWorkspaceMenus()
    // An editable accessory must not become the window's initial input owner.
    window.makeFirstResponder(window.contentViewController)
  }

  private func resize() {
    guard let window else { return }
    // AppKit owns height; only width is configurable for a right accessory.
    strip.setFrameSize(NSSize(width: max(200, window.frame.width - 88), height: strip.frame.height))
    strip.needsLayout = true
  }

  private func installWorkspaceMenus() {
    guard let main = NSApp.mainMenu, main.item(withTitle: "Models") == nil else { return }
    // The stock Flutter nib includes a disabled Preferences placeholder. Make
    // the app-menu command work, and give ⌘, a single native owner.
    if let appMenu = main.item(at: 0)?.submenu {
      let settings = appMenu.items.first(where: { $0.keyEquivalent == "," }) ??
        NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ",")
      settings.title = "Settings…"
      settings.target = self
      settings.action = #selector(menuAction(_:))
      settings.representedObject = "settings"
      settings.keyEquivalentModifierMask = [.command]
      if settings.menu == nil { appMenu.insertItem(settings, at: min(2, appMenu.numberOfItems)) }
    }
    func add(_ menu: NSMenu, _ title: String, _ key: String, _ action: String, _ modifiers: NSEvent.ModifierFlags = [.command]) {
      let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      item.target = self
      item.representedObject = action
      menu.addItem(item)
    }
    func install(_ menu: NSMenu, at index: Int) {
      let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
      item.submenu = menu
      main.insertItem(item, at: index)
    }
    let file = NSMenu(title: "File")
    add(file, "New Swarm", "t", "new")
    add(file, "New Agent…", "", "newAgent")
    add(file, "Reopen Last Closed", "t", "reopen", [.command, .shift])
    file.addItem(.separator())
    add(file, "Link Machine…", "", "linkMachine")
    add(file, "Add Project…", "", "addProject")
    file.addItem(.separator())
    add(file, "Rename Swarm…", "r", "renameActive", [.command, .shift])
    add(file, "Remove Agent from Swarm", "w", "closePane", [.command, .shift])
    add(file, "Close Swarm", "w", "closeActive")
    install(file, at: 1)

    rebuildHistoryMenu()
    let windowIndex = main.items.firstIndex(where: { $0.title == "Window" }) ?? main.numberOfItems
    install(historyMenu, at: windowIndex)

    // Navigation chords remain in Flutter's terminal-safe shortcut table.
    // Search still needs a native owner when the titlebar field has focus.
    if let edit = main.item(withTitle: "Edit")?.submenu {
      edit.addItem(.separator())
      add(edit, "Search Agents, Swarms, Machines and Projects…", "p", "jump")
    }
    if let view = main.item(withTitle: "View")?.submenu {
      view.addItem(.separator())
      add(view, "Agents Needing Input…", "i", "notifications", [.command, .shift])
    }
    modelsMenu.autoenablesItems = false
    modelsMenu.delegate = self
    rebuildModelsMenu()
    install(modelsMenu, at: windowIndex + 1)
    installTerminalFindMenu(main)
  }

  func menuWillOpen(_ menu: NSMenu) {
    guard menu === modelsMenu, actionsEnabled else { return }
    // The native menu opens from its cache. Network/credential reads happen
    // asynchronously in Dart and never hold up AppKit's menu tracking.
    channel.invokeMethod("modelsOpened", arguments: nil)
  }

  private func updateModels(_ rows: [[String: Any]]) {
    let entries = rows.prefix(32).compactMap(SwarmSubscriptionEntry.init)
    guard entries != subscriptions else { return }
    subscriptions = entries
    rebuildModelsMenu()
  }

  private func rebuildModelsMenu() {
    modelsMenu.removeAllItems()
    func label(_ title: String, in menu: NSMenu) {
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    }
    func section(_ title: String) {
      if #available(macOS 14.0, *) {
        modelsMenu.addItem(NSMenuItem.sectionHeader(title: title))
      } else {
        label(title, in: modelsMenu)
      }
    }
    section("Subscription")
    for entry in subscriptions {
      let item = NSMenuItem(title: entry.title + " — " + entry.status, action: nil, keyEquivalent: "")
      item.image = historyIcons.image(engine: entry.engine, asset: entry.iconAsset)
      item.toolTip = entry.details.joined(separator: "\n")
      let detail = NSMenu(title: entry.title)
      detail.autoenablesItems = false
      for line in entry.details { label(line, in: detail) }
      item.submenu = detail
      item.isEnabled = actionsEnabled
      modelsMenu.addItem(item)
    }
    if subscriptions.isEmpty {
      label("Anthropic", in: modelsMenu)
      label("OpenAI", in: modelsMenu)
    }
    modelsMenu.addItem(.separator())
    section("API")
    label("OpenRouter API", in: modelsMenu)
    label("fal.ai API", in: modelsMenu)
    modelsMenu.addItem(.separator())
    section("Local")
    label("Local models", in: modelsMenu)
    modelsMenu.addItem(.separator())
    label("Add Model", in: modelsMenu)
  }

  private func updateModelsAvailability() {
    for item in modelsMenu.items where item.submenu != nil {
      item.isEnabled = actionsEnabled
    }
  }

  private func updateHistory(_ rows: [[String: Any]], closed: [[String: Any]] = []) {
    let entries = rows.prefix(64).compactMap(SwarmHistoryEntry.init)
    let closedEntries = closed.prefix(24).compactMap(SwarmHistoryEntry.init)
    guard entries != history || closedEntries != closedHistory else { return }
    history = entries
    closedHistory = closedEntries
    rebuildHistoryMenu()
  }

  private func rebuildHistoryMenu() {
    historyMenu.removeAllItems()
    func command(_ title: String, _ key: String, _ action: String) {
      let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: key)
      item.target = self
      item.representedObject = action
      item.keyEquivalentModifierMask = [.command]
      historyMenu.addItem(item)
    }
    command("Back", "[", "historyBack")
    command("Forward", "]", "historyForward")
    historyMenu.addItem(.separator())
    appendHistorySection("Recently Closed", entries: Array(closedHistory.prefix(10)), closed: true)
    historyMenu.addItem(.separator())
    appendHistorySection("Recently Visited", entries: Array(history.prefix(15)), closed: false)
    historyMenu.addItem(.separator())
    command("Show Full History", "y", "showHistory")
  }

  private func appendHistorySection(_ title: String, entries: [SwarmHistoryEntry], closed: Bool) {
    if #available(macOS 14.0, *) {
      historyMenu.addItem(NSMenuItem.sectionHeader(title: title))
    } else {
      let label = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      label.isEnabled = false
      historyMenu.addItem(label)
    }
    for entry in entries {
      let title = entry.title.count > 76 ? String(entry.title.prefix(48)) + "…" + String(entry.title.suffix(24)) : entry.title
      let item = NSMenuItem(title: title, action: closed ? #selector(closedHistoryAction(_:)) : #selector(historyAction(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = entry.id
      item.toolTip = entry.title + "\n" + entry.detail
      item.state = entry.current ? .on : .off
      item.image = entry.swarm
        ? NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: nil)
        : historyIcons.image(engine: entry.engine, asset: entry.iconAsset)
      historyMenu.addItem(item)
    }
    if entries.isEmpty {
      let item = NSMenuItem(title: closed ? "No Recently Closed Agents or Swarms" : "No Recent Visits", action: nil, keyEquivalent: "")
      item.isEnabled = false
      historyMenu.addItem(item)
    }
  }

  private func installTerminalFindMenu(_ main: NSMenu) {
    guard let edit = main.items.first(where: { $0.title == "Edit" })?.submenu,
          let find = edit.items.first(where: { $0.title == "Find" }) else { return }
    let menu = NSMenu(title: "Find")
    for (title, key, action, modifiers) in [
      ("Find in Terminal…", "f", "findTerminal", NSEvent.ModifierFlags.command),
      ("Find Next", "g", "findNext", NSEvent.ModifierFlags.command),
      ("Find Previous", "g", "findPrevious", NSEvent.ModifierFlags([.command, .shift])),
    ] {
      let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      item.target = self
      item.representedObject = action
      menu.addItem(item)
    }
    // The template's find/replace actions target an unused text-editor handler.
    // Terminal output is searchable; replacement belongs to the running tool.
    find.submenu = menu
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    let action = menuItem.representedObject as? String ?? ""
    if menuItem.action == #selector(historyAction(_:)) {
      return actionsEnabled && history.contains(where: { $0.id == action })
    }
    if menuItem.action == #selector(closedHistoryAction(_:)) {
      return actionsEnabled && closedHistory.contains(where: { $0.id == action && $0.canReopen })
    }
    return actionsEnabled && (action != "reopen" || canReopen) &&
      (action != "historyBack" || canGoBack) && (action != "historyForward" || canGoForward) &&
      (action != "new" || canCreateSwarm) && (action != "closePane" || canClosePane) &&
      (!["findTerminal", "findNext", "findPrevious"].contains(action) || canFind)
  }

  @objc private func menuAction(_ sender: NSMenuItem) {
    guard validateMenuItem(sender), let action = sender.representedObject as? String else { return }
    channel.invokeMethod(action, arguments: nil)
  }

  @objc private func historyAction(_ sender: NSMenuItem) {
    guard validateMenuItem(sender), let id = sender.representedObject as? String else { return }
    channel.invokeMethod("historyDestination", arguments: ["id": id])
  }

  @objc private func closedHistoryAction(_ sender: NSMenuItem) {
    guard validateMenuItem(sender), let id = sender.representedObject as? String else { return }
    channel.invokeMethod("reopenHistory", arguments: ["id": id])
  }
}

private struct SwarmSubscriptionEntry: Equatable {
  let title: String
  let status: String
  let details: [String]
  let engine: String?
  let iconAsset: String?

  init?(_ row: [String: Any]) {
    guard let title = row["title"] as? String, !title.isEmpty,
          let status = row["status"] as? String else { return nil }
    self.title = title
    self.status = status
    details = Array((row["details"] as? [String] ?? [status]).prefix(16))
    engine = row["engine"] as? String
    iconAsset = row["iconAsset"] as? String
  }
}

private struct SwarmHistoryEntry: Equatable {
  let id: String
  let title: String
  let detail: String
  let swarm: Bool
  let current: Bool
  let engine: String?
  let iconAsset: String?
  let canReopen: Bool
  init?(_ row: [String: Any]) {
    guard let id = row["id"] as? String, let title = row["title"] as? String else { return nil }
    self.id = id
    self.title = title
    detail = row["detail"] as? String ?? ""
    swarm = row["swarm"] as? Bool == true
    current = row["current"] as? Bool == true
    engine = (row["engine"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    iconAsset = row["iconAsset"] as? String
    canReopen = row["canReopen"] as? Bool == true
  }
}

/// Reuse the same bundled engine artwork as pane headers. Each menu mark is
/// decoded once to at most 32 pixels, rather than retaining a full-size bitmap
/// or reopening assets on every history/focus update.
private final class SwarmHistoryIcons {
  private let cache = NSCache<NSString, NSImage>()
  private let assetURL: (String) -> URL?

  init(assetURL: @escaping (String) -> URL? = { asset in
    let bundle = Bundle(identifier: "io.flutter.flutter.app") ?? Bundle.main
    let key = FlutterDartProject.lookupKey(forAsset: asset, from: bundle)
    return bundle.url(forResource: key, withExtension: nil)
  }) {
    self.assetURL = assetURL
    cache.countLimit = 32
  }

  func image(engine: String?, asset: String?) -> NSImage {
    let id = engine?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let key = "\(id):\(asset ?? "")" as NSString
    if let image = cache.object(forKey: key) { return image }
    let size = NSSize(width: 16, height: 16)
    let image: NSImage
    if let asset, asset.hasPrefix("assets/engine-icons/"),
       asset.hasSuffix(".png"), !asset.contains(".."),
       let url = assetURL(asset),
       let source = CGImageSourceCreateWithURL(url as CFURL, nil),
       let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
         kCGImageSourceCreateThumbnailFromImageAlways: true,
         kCGImageSourceCreateThumbnailWithTransform: true,
         kCGImageSourceThumbnailMaxPixelSize: 32,
         kCGImageSourceShouldCacheImmediately: true,
       ] as CFDictionary) {
      let bitmap = NSImage(cgImage: thumbnail, size: .zero)
      let scale = 16 / CGFloat(max(thumbnail.width, thumbnail.height))
      let width = CGFloat(thumbnail.width) * scale
      let height = CGFloat(thumbnail.height) * scale
      image = NSImage(size: size, flipped: false) { _ in
        bitmap.draw(in: NSRect(x: (16 - width) / 2, y: (16 - height) / 2, width: width, height: height))
        return true
      }
    } else if id == "claude" {
      // Same four round strokes, proportions and orange as EngineMark.
      image = NSImage(size: size, flipped: false) { _ in
        NSColor(srgbRed: 204.0 / 255, green: 124.0 / 255, blue: 94.0 / 255, alpha: 1).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 16 * 0.098
        path.lineCapStyle = .round
        for i in 0..<4 {
          let angle = CGFloat(i) * .pi / 4
          let dx = 16 * 0.39 * cos(angle), dy = 16 * 0.39 * sin(angle)
          path.move(to: NSPoint(x: 8 - dx, y: 8 - dy))
          path.line(to: NSPoint(x: 8 + dx, y: 8 + dy))
        }
        path.stroke()
        return true
      }
    } else {
      image = NSImage(size: size, flipped: false) { _ in
        let initial = String(id.first ?? "A").uppercased() as NSString
        let attributes: [NSAttributedString.Key: Any] = [
          .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
          .foregroundColor: NSColor.black,
        ]
        let bounds = initial.size(withAttributes: attributes)
        initial.draw(at: NSPoint(x: (16 - bounds.width) / 2, y: (16 - bounds.height) / 2), withAttributes: attributes)
        return true
      }
      image.isTemplate = true
    }
    cache.setObject(image, forKey: key)
    return image
  }
}

private let swarmPasteboardType = NSPasteboard.PasteboardType("ai.autonomous.harness.v2.swarm")
// Matches AppPalette.swarmField exactly, joining the tab to the terminal canvas.
private let swarmSelectedTabColor = NSColor(srgbRed: 70.0 / 255, green: 55.0 / 255, blue: 70.0 / 255, alpha: 1)
// Matches AppPalette.swarmSearchSurface so the input joins its results below.
private let swarmSearchSurface = NSColor(srgbRed: 61.0 / 255, green: 51.0 / 255, blue: 63.0 / 255, alpha: 1)

private final class SwarmSearchCell: NSSearchFieldCell {
  override func select(withFrame rect: NSRect, in controlView: NSView, editor: NSText,
                       delegate: Any?, start: Int, length: Int) {
    super.select(withFrame: searchTextRect(forBounds: rect), in: controlView,
      editor: editor, delegate: delegate, start: start, length: length)
  }
  override func edit(withFrame rect: NSRect, in controlView: NSView, editor: NSText,
                     delegate: Any?, event: NSEvent?) {
    super.edit(withFrame: searchTextRect(forBounds: rect), in: controlView,
      editor: editor, delegate: delegate, event: event)
  }
  override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
    NSRect(x: rect.minX + 12, y: rect.midY - 8, width: 16, height: 16)
  }
  override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
    NSRect(x: rect.maxX - 28, y: rect.midY - 8, width: 16, height: 16)
  }
  override func searchTextRect(forBounds rect: NSRect) -> NSRect {
    let font = font ?? NSFont.systemFont(ofSize: 13)
    let height = ceil(font.ascender - font.descender + font.leading)
    return NSRect(x: rect.minX + 36, y: rect.midY - height / 2,
      width: max(0, rect.width - 68), height: height)
  }
}

/// AppKit owns editing, selection, paste and IME. Only result-navigation keys
/// leave the field editor; ordinary terminal input never passes through here.
private final class SwarmSearchField: NSSearchField {
  var begin: (() -> Void)?
  var command: ((String) -> Void)?
  var scoped = false
  var searching = false { didSet { needsDisplay = true } }
  override init(frame: NSRect) {
    super.init(frame: frame)
    cell = SwarmSearchCell(textCell: "")
    font = NSFont.systemFont(ofSize: 13)
    controlSize = .regular
    appearance = NSAppearance(named: .darkAqua)
    isEditable = true
    isSelectable = true
    isBordered = false
    drawsBackground = false
    textColor = NSColor(white: 0.92, alpha: 1)
    placeholderString = "Search…"
    sendsSearchStringImmediately = true
    sendsWholeSearchString = false
    maximumRecents = 0
    searchMenuTemplate = nil
    focusRingType = .none
    if let search = cell as? NSSearchFieldCell {
      search.focusRingType = .none
      search.isScrollable = true
      search.searchButtonCell?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var mouseDownCanMoveWindow: Bool { false }
  override func becomeFirstResponder() -> Bool {
    begin?()
    return super.becomeFirstResponder()
  }
  override func mouseDown(with event: NSEvent) {
    begin?()
    super.mouseDown(with: event)
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let editor = currentEditor() as? NSTextView,
       event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command {
      if event.charactersIgnoringModifiers == "p" && !editor.hasMarkedText() {
        editor.selectAll(nil)
        return true
      }
      if let action = Self.resultCommand("insertNewline:", event: event, composing: editor.hasMarkedText()),
         event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\u{3}" {
        if !event.isARepeat { command?(action) }
        return true
      }
    }
    return super.performKeyEquivalent(with: event)
  }
  static func resultCommand(_ selector: String, event: NSEvent?, composing: Bool, scoped: Bool = false) -> String? {
    guard !composing else { return nil }
    let modifiers = event?.modifierFlags.intersection([.command, .option, .control, .shift]) ?? []
    if modifiers == .control {
      switch event?.charactersIgnoringModifiers?.lowercased() {
      case "n", "j": return "next"
      case "p", "k": return "previous"
      case "g": return "close"
      default: break
      }
    }
    if scoped && modifiers == .option && selector == "moveWordLeft:" { return "back" }
    switch selector {
    case "moveDown:": return "next"
    case "moveUp:": return "previous"
    case "insertNewline:", "insertNewlineIgnoringFieldEditor:": return modifiers == .command ? "add" : "submit"
    case "cancelOperation:", "complete:": return "close"
    default: return nil
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    let shape = NSBezierPath(roundedRect: bounds, xRadius: searching ? 10 : 16, yRadius: searching ? 10 : 16)
    swarmSearchSurface.setFill()
    shape.fill()
    if searching {
      // The strip continues the square bottom edge down to the result list.
      NSRect(x: 0, y: isFlipped ? bounds.midY : 0,
        width: bounds.width, height: bounds.height / 2).fill()
    } else {
      NSColor(white: 1, alpha: 0.16).setStroke()
      let rim = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
      rim.lineWidth = 1
      rim.stroke()
    }
    super.draw(dirtyRect)
    if !searching && stringValue.isEmpty && bounds.width >= 140 {
      let shortcut = "⌘P" as NSString
      let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.secondaryLabelColor]
      let size = shortcut.size(withAttributes: attrs)
      shortcut.draw(at: NSPoint(x: bounds.width - size.width - 12,
        y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
  }
}

private final class SwarmTabStrip: NSView, NSSearchFieldDelegate {
  var emit: ((String, Any?) -> Void)?
  private let scroll = NSScrollView()
  private let document = NSView()
  private let newButton = NSButton()
  private let searchField = SwarmSearchField()
  private var lastSearchWidth: CGFloat = 0
  private var tabs: [SwarmTabButton] = []
  private var activeId = ""
  private var actionsEnabled = false
  override var mouseDownCanMoveWindow: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    scroll.drawsBackground = false
    scroll.hasHorizontalScroller = false
    scroll.hasVerticalScroller = false
    scroll.documentView = document
    addSubview(scroll)
    func button(_ button: NSButton, _ symbol: String, _ label: String, _ action: Selector) {
      button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
      button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
      button.isBordered = false
      button.contentTintColor = NSColor(srgbRed: 0.80, green: 0.75, blue: 0.83, alpha: 1)
      button.target = self
      button.action = action
      button.toolTip = label
      button.setAccessibilityLabel(label)
      addSubview(button)
    }
    button(newButton, "plus", "New swarm (⌘T)", #selector(newSwarm))
    searchField.delegate = self
    searchField.isEnabled = false
    searchField.begin = { [weak self] in self?.beginSearch() }
    searchField.command = { [weak self] action in self?.emit?("searchCommand", ["command": action]) }
    searchField.toolTip = "Search agents, swarms, machines and projects (⌘P)"
    searchField.setAccessibilityLabel("Search agents, swarms, machines and projects")
    addSubview(searchField)
    registerForDraggedTypes([swarmPasteboardType])
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func update(_ state: [String: Any]) {
    actionsEnabled = state["enabled"] as? Bool == true
    let rows = state["tabs"] as? [[String: Any]] ?? []
    activeId = state["activeId"] as? String ?? ""
    let ids = rows.compactMap { $0["id"] as? String }
    let previousOrder = tabs.map(\.swarmId)
    for tab in tabs where !ids.contains(tab.swarmId) { tab.removeFromSuperview() }
    let previous = Dictionary(uniqueKeysWithValues: tabs.map { ($0.swarmId, $0) })
    tabs = rows.compactMap { row in
      guard let id = row["id"] as? String else { return nil }
      let tab = previous[id] ?? SwarmTabButton(id: id)
      tab.name = row["name"] as? String ?? "New swarm"
      tab.selected = id == activeId
      tab.actionsEnabled = actionsEnabled
      tab.attention = (row["attention"] as? Int ?? 0) > 0
      tab.emit = { [weak self] method, args in self?.emit?(method, args) }
      tab.hoverChanged = { [weak self] in self?.updateDividers() }
      if tab.superview == nil { document.addSubview(tab) }
      tab.needsDisplay = true
      return tab
    }
    updateDividers()
    // Moving frames alone leaves AppKit's child traversal in insertion order.
    document.setAccessibilityChildren(tabs)
    newButton.isEnabled = actionsEnabled && tabs.count < 24
    searchField.isEnabled = actionsEnabled
    if !actionsEnabled { closeSearch() }
    needsLayout = true
    layoutSubtreeIfNeeded()
    if ids != previousOrder {
      NSAccessibility.post(element: document, notification: .layoutChanged)
    }
  }

  private func updateDividers() {
    for (index, tab) in tabs.enumerated() {
      let next = index + 1 < tabs.count ? tabs[index + 1] : nil
      tab.showsDivider = !tab.selected && !tab.isHovered && next != nil &&
        next?.selected == false && next?.isHovered == false
    }
  }

  override func layout() {
    super.layout()
    let searchWidth: CGFloat = searchField.searching
      ? min(600, max(128, bounds.width - 184))
      : bounds.width < 480 ? 128 : bounds.width < 720 ? 156 : 200
    let available = max(132, bounds.width - searchWidth - 56)
    let width = min(220, max(132, available / CGFloat(max(1, tabs.count))))
    let occupied = min(available, CGFloat(tabs.count) * width)
    scroll.frame = NSRect(x: 0, y: 0, width: occupied, height: bounds.height)
    document.frame = NSRect(x: 0, y: 0, width: max(occupied, CGFloat(tabs.count) * width), height: bounds.height)
    for (index, tab) in tabs.enumerated() {
      tab.frame = NSRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height - 6)
      tab.contentCenterY = bounds.midY
    }
    let buttonY = (bounds.height - 28) / 2
    newButton.frame = NSRect(x: occupied + 4, y: buttonY, width: 28, height: 28)
    searchField.frame = NSRect(x: bounds.width - searchWidth - 8, y: (bounds.height - 32) / 2, width: searchWidth, height: 32)
    if searchField.searching && searchWidth != lastSearchWidth {
      lastSearchWidth = searchWidth
      emit?("searchGeometry", ["width": searchWidth])
    }
    if let active = tabs.first(where: { $0.swarmId == activeId }) {
      document.scrollToVisible(active.frame)
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    // The selected tab meets this edge; its bottom corners are shoulders,
    // rather than the rounded bottom of a separate pill.
    swarmSelectedTabColor.setFill()
    NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    if searchField.searching {
      swarmSearchSurface.setFill()
      NSRect(x: searchField.frame.minX, y: 0, width: searchField.frame.width,
        height: searchField.frame.minY + 1).fill()
    }
  }
  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 { window?.performZoom(nil) }
    else { window?.performDrag(with: event) }
  }
  @objc private func newSwarm() { emit?("new", nil) }
  private func beginSearch() {
    guard actionsEnabled, !searchField.searching else { return }
    searchField.searching = true
    needsDisplay = true
    needsLayout = true
    layoutSubtreeIfNeeded()
    emit?("searchBegin", ["width": searchField.frame.width])
  }
  func focusSearch(selectAll: Bool = false) {
    guard actionsEnabled else { return }
    beginSearch()
    if searchField.currentEditor() == nil { window?.makeFirstResponder(searchField) }
    if selectAll, let editor = searchField.currentEditor() as? NSTextView, !editor.hasMarkedText() { editor.selectAll(nil) }
  }
  func setSearchState(_ state: [String: Any]) {
    if let query = state["query"] as? String, query != searchField.stringValue {
      searchField.stringValue = query
      if let editor = searchField.currentEditor() as? NSTextView {
        editor.string = query
        editor.setSelectedRange(NSRange(location: (query as NSString).length, length: 0))
      }
    }
    searchField.placeholderString = state["hint"] as? String ?? "Search…"
    searchField.scoped = state["scoped"] as? Bool == true
  }
  func closeSearch() {
    guard searchField.searching else { return }
    searchField.searching = false
    needsDisplay = true
    if searchField.currentEditor() != nil {
      // Flutter's wrapper NSView does not accept first responder. Its public
      // view controller does, and routes the next event to Flutter's keyboard.
      let responder = window?.contentViewController as NSResponder? ?? window?.contentView
      window?.makeFirstResponder(responder)
    }
    searchField.stringValue = ""
    searchField.placeholderString = "Search…"
    lastSearchWidth = 0
    needsLayout = true
  }
  func controlTextDidChange(_ notification: Notification) {
    guard searchField.searching else { return }
    emit?("searchChanged", ["query": searchField.stringValue])
  }
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    let event = NSApp.currentEvent
    guard let action = SwarmSearchField.resultCommand(NSStringFromSelector(selector), event: event,
      composing: textView.hasMarkedText(), scoped: searchField.scoped) else { return false }
    if event?.isARepeat != true || !["submit", "add", "close"].contains(action) {
      emit?("searchCommand", ["command": action])
    }
    return true
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { actionsEnabled ? .move : [] }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { actionsEnabled ? .move : [] }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard actionsEnabled, let id = sender.draggingPasteboard.string(forType: swarmPasteboardType),
          tabs.contains(where: { $0.swarmId == id }) else { return false }
    let point = document.convert(sender.draggingLocation, from: nil)
    let index = tabs.firstIndex(where: { point.x < $0.frame.midX }) ?? tabs.count
    let old = tabs.firstIndex(where: { $0.swarmId == id })!
    emit?("reorder", ["id": id, "index": max(0, index > old ? index - 1 : index)])
    return true
  }
}

private final class SwarmTabButton: NSView, NSDraggingSource, NSMenuItemValidation {
  let swarmId: String
  var name = "New swarm" { didSet { if name != oldValue { invalidateLabel(); updateAccessibility() } } }
  var selected = false { didSet { if selected != oldValue { invalidateLabel(); updateAccessibility() } } }
  var attention = false
  var showsDivider = false { didSet { if showsDivider != oldValue { needsDisplay = true } } }
  var contentCenterY: CGFloat = 20
  var emit: ((String, Any?) -> Void)?
  var hoverChanged: (() -> Void)?
  var isHovered: Bool { hovered && actionsEnabled }
  private let closeButton = NSButton()
  private let selectButton = SwarmSelectButton()
  private var cachedLabel: NSAttributedString?
  var actionsEnabled = true {
    didSet {
      closeButton.isEnabled = actionsEnabled
      selectButton.isEnabled = actionsEnabled
    }
  }
  private var downPoint = NSPoint.zero
  private var hovered = false
  private var hoverTracking: NSTrackingArea?
  override var acceptsFirstResponder: Bool { false }
  override var mouseDownCanMoveWindow: Bool { false }

  init(id: String) {
    swarmId = id
    super.init(frame: .zero)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    selectButton.owner = self
    selectButton.title = ""
    selectButton.isBordered = false
    selectButton.target = self
    selectButton.action = #selector(selectSwarm)
    addSubview(selectButton)
    closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close swarm")
    closeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
    closeButton.contentTintColor = NSColor(white: 0.78, alpha: 1)
    closeButton.isBordered = false
    closeButton.target = self
    closeButton.action = #selector(closeSwarm)
    closeButton.toolTip = "Close swarm"
    addSubview(closeButton)
    let menu = NSMenu()
    for (title, action) in [("Rename Swarm…", #selector(renameSwarm)), ("Close Swarm", #selector(closeSwarm))] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    self.menu = menu
    updateAccessibility()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func layout() {
    super.layout()
    selectButton.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - 36), height: bounds.height)
    closeButton.frame = NSRect(x: bounds.width - 36, y: contentCenterY - 12, width: 24, height: 24)
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverTracking { removeTrackingArea(hoverTracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self, userInfo: nil)
    addTrackingArea(area)
    hoverTracking = area
  }
  override func mouseEntered(with event: NSEvent) { setHovered(true) }
  override func mouseExited(with event: NSEvent) { setHovered(false) }
  private func setHovered(_ value: Bool) {
    guard hovered != value else { return }
    hovered = value
    needsDisplay = true
    hoverChanged?()
  }
  private func invalidateLabel() {
    cachedLabel = nil
    needsDisplay = true
  }
  private var label: NSAttributedString {
    if let cachedLabel { return cachedLabel }
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    let label = NSAttributedString(string: name,
      attributes: [.font: NSFont.systemFont(ofSize: 13, weight: selected ? .medium : .regular),
        .foregroundColor: selected ? NSColor.white : NSColor(white: 0.76, alpha: 1), .paragraphStyle: paragraph])
    cachedLabel = label
    return label
  }
  override func draw(_ dirtyRect: NSRect) {
    if selected {
      let w = bounds.width, h = bounds.height
      let shape = NSBezierPath()
      shape.move(to: NSPoint(x: 0, y: 0))
      shape.curve(to: NSPoint(x: 8, y: 8), controlPoint1: NSPoint(x: 4.4, y: 0), controlPoint2: NSPoint(x: 8, y: 3.6))
      shape.line(to: NSPoint(x: 8, y: h - 10))
      shape.curve(to: NSPoint(x: 18, y: h), controlPoint1: NSPoint(x: 8, y: h - 4.5), controlPoint2: NSPoint(x: 12.5, y: h))
      shape.line(to: NSPoint(x: w - 18, y: h))
      shape.curve(to: NSPoint(x: w - 8, y: h - 10), controlPoint1: NSPoint(x: w - 12.5, y: h), controlPoint2: NSPoint(x: w - 8, y: h - 4.5))
      shape.line(to: NSPoint(x: w - 8, y: 8))
      shape.curve(to: NSPoint(x: w, y: 0), controlPoint1: NSPoint(x: w - 8, y: 3.6), controlPoint2: NSPoint(x: w - 4.4, y: 0))
      shape.close()
      swarmSelectedTabColor.setFill()
      shape.fill()
    } else if hovered && actionsEnabled {
      NSColor(white: 1, alpha: 0.05).setFill()
      let hoverRect = NSRect(x: 8, y: contentCenterY - 14, width: bounds.width - 16, height: 28)
      NSBezierPath(roundedRect: hoverRect, xRadius: 12, yRadius: 12).fill()
    }
    if showsDivider && !hovered {
      NSColor(white: 1, alpha: 0.16).setFill()
      NSBezierPath(roundedRect: NSRect(x: bounds.width - 0.5, y: contentCenterY - 8, width: 1, height: 16),
        xRadius: 0.5, yRadius: 0.5).fill()
    }
    let label = self.label
    let labelHeight = label.size().height
    label.draw(in: NSRect(x: 22, y: contentCenterY - labelHeight / 2,
      width: bounds.width - 64, height: labelHeight))
    if attention {
      NSColor.systemOrange.setFill()
      NSBezierPath(ovalIn: NSRect(x: 13, y: contentCenterY - 2, width: 4, height: 4)).fill()
    }
  }
  // Overflowed tabs might not be drawn. Their names and selection still need
  // to be available to VoiceOver and automation before they scroll into view.
  private func updateAccessibility() {
    setAccessibilityLabel(name)
    selectButton.setAccessibilityLabel("Select \(name)")
    selectButton.setAccessibilityValue(selected ? "Selected" : "")
    toolTip = "\(name) — double-click to rename"
    closeButton.setAccessibilityLabel("Close \(name)")
  }
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { actionsEnabled }
  override func mouseDown(with event: NSEvent) {
    guard actionsEnabled else { return }
    downPoint = event.locationInWindow
    if event.clickCount == 2 { renameSwarm() }
    else { emit?("select", ["id": swarmId]) }
  }
  override func mouseDragged(with event: NSEvent) {
    guard actionsEnabled else { return }
    if hypot(event.locationInWindow.x - downPoint.x, event.locationInWindow.y - downPoint.y) < 5 { return }
    let item = NSPasteboardItem()
    item.setString(swarmId, forType: swarmPasteboardType)
    let dragging = NSDraggingItem(pasteboardWriter: item)
    let snapshot = NSImage(size: bounds.size)
    snapshot.lockFocus()
    draw(bounds)
    snapshot.unlockFocus()
    dragging.setDraggingFrame(bounds, contents: snapshot)
    beginDraggingSession(with: [dragging], event: event, source: self)
  }
  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
  override func accessibilityChildren() -> [Any]? { [selectButton, closeButton] }
  @objc private func selectSwarm() { if actionsEnabled { emit?("select", ["id": swarmId]) } }
  @objc private func closeSwarm() { if actionsEnabled { emit?("close", ["id": swarmId]) } }
  @objc private func renameSwarm() { if actionsEnabled { emit?("rename", ["id": swarmId]) } }
}

/// Selection and closing are sibling accessibility buttons, so VoiceOver and
/// UI automation can reach the close action without treating the tab as a leaf.
private final class SwarmSelectButton: NSButton {
  weak var owner: SwarmTabButton?
  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    owner?.mouseDown(with: event)
  }
  override func mouseDragged(with event: NSEvent) {
    guard isEnabled else { return }
    owner?.mouseDragged(with: event)
  }
}
