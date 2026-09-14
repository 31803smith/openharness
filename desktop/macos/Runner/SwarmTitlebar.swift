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
  private var keymap: HarnessNativeKeymap?
  private var flutterKeyContext = "workspace"
  private var tabActionGeneration = 0

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(name: "harness/swarm_tabs", binaryMessenger: messenger)
    super.init()
    strip.emit = { [weak self] method, args in
      guard let self else { return }
      self.sendTabAction(method, arguments: args)
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "configure":
        let state = call.arguments as? [String: Any] ?? [:]
        self.configure(palette: state["palette"] as? [String: Any])
        result(true)
      case "update":
        let state = call.arguments as? [String: Any] ?? [:]
        self.actionsEnabled = state["enabled"] as? Bool == true
        self.canReopen = state["canReopen"] as? Bool == true
        self.canFind = state["canFind"] as? Bool == true
        self.canClosePane = state["canClosePane"] as? Bool == true
        self.canGoBack = state["canGoBack"] as? Bool == true
        self.canGoForward = state["canGoForward"] as? Bool == true
        self.canCreateSwarm = (state["tabs"] as? [Any] ?? []).count < 24
        self.updateHistory(state["history"] as? [[String: Any]] ?? [], closed: state["closedHistory"] as? [[String: Any]] ?? [])
        self.strip.update(state)
        self.window?.backgroundColor = self.strip.palette.tabBar
        result(nil)
      case "modelsState":
        let state = call.arguments as? [String: Any] ?? [:]
        self.updateModels(state["subscriptions"] as? [[String: Any]] ?? [])
        result(nil)
      case "keymapState":
        guard let payload = call.arguments as? [String: Any],
              let map = HarnessNativeKeymap(payload) else {
          result(FlutterError(code: "INVALID_KEYMAP", message: "Invalid keyboard configuration", details: nil))
          return
        }
        self.setKeymap(map)
        result(nil)
      case "keymapContext":
        if let context = (call.arguments as? [String: Any])?["context"] as? String,
           ["workspace", "terminal", "picker"].contains(context) {
          self.flutterKeyContext = context
          self.syncMenuKeys()
        }
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

  }

  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
  }

  private func sendTabAction(_ method: String, arguments: Any?) {
    guard ["select", "close", "new", "rename", "jump", "commands", "notifications", "newAgent", "splitRight", "splitDown", "zoomPane", "pinPane"].contains(method) else {
      channel.invokeMethod(method, arguments: arguments)
      return
    }
    tabActionGeneration += 1
    let generation = tabActionGeneration
    // Keyboard/VoiceOver activation can leave a button as responder. Wait for
    // Flutter to apply the action before giving the next key to its content.
    channel.invokeMethod(method, arguments: arguments) { [weak self, weak responder = window?.firstResponder] result in
      guard let self, let window = self.window, generation == self.tabActionGeneration,
            !(result is FlutterError), result as? NSObject !== FlutterMethodNotImplemented,
            window.firstResponder === responder || window.firstResponder === window else { return }
      window.makeFirstResponder(window.contentViewController)
    }
  }

  private func setKeymap(_ map: HarnessNativeKeymap) {
    keymap = map
    let hint = map.hint(for: "navigation.quick_open", context: "workspace")
    strip.searchButton.toolTip = hint.map { "Navigate (\($0))" } ?? "Navigate"
    // The ⌘, baked into the button at construction is only the factory binding;
    // once a keymap arrives the tooltip has to say what THIS user's key is.
    let settingsHint = map.hint(for: "app.settings", context: "workspace")
    strip.settingsButton.toolTip = settingsHint.map { "Settings (\($0))" } ?? "Settings"
    if let main = NSApp.mainMenu, let window {
      let menu = main as? HarnessKeymapMenu ?? HarnessKeymapMenu.replacing(main)
      if NSApp.mainMenu !== menu { NSApp.mainMenu = menu }
      menu.update(map, window: window)
    }
    syncMenuKeys()
  }

  private func syncMenuKeys() {
    guard let keymap, let main = NSApp.mainMenu else { return }
    keymap.applyMenuKeys(to: main, context: flutterKeyContext)
  }

  private func configure(palette: [String: Any]? = nil) {
    // Appearance is loaded before the workspace exists. Apply it before the
    // explicit show request, without inventing tabs or enabling their actions.
    if let palette {
      strip.updatePalette(palette)
      window?.backgroundColor = strip.palette.tabBar
    }
    guard let window, !configured else { return }
    configured = true
    NSWindow.allowsAutomaticWindowTabbing = false
    window.tabbingMode = .disallowed
    window.title = "Harness"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.styleMask.remove(.fullSizeContentView)
    window.backgroundColor = strip.palette.tabBar
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
    if let keymap { setKeymap(keymap) }
    // Toolbar controls must not become the window's initial input owner.
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
      settings.identifier = NSUserInterfaceItemIdentifier(HarnessKeymapMenu.actionPrefix + "settings")
      settings.keyEquivalentModifierMask = [.command]
      if settings.menu == nil { appMenu.insertItem(settings, at: min(2, appMenu.numberOfItems)) }
    }
    func add(_ menu: NSMenu, _ title: String, _ key: String, _ action: String, _ modifiers: NSEvent.ModifierFlags = [.command]) {
      let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      item.target = self
      item.representedObject = action
      item.identifier = NSUserInterfaceItemIdentifier(HarnessKeymapMenu.actionPrefix + action)
      menu.addItem(item)
    }
    func install(_ menu: NSMenu, at index: Int) {
      let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
      item.submenu = menu
      main.insertItem(item, at: index)
    }
    if let file = main.item(withTitle: "File") { main.removeItem(file) }
    let swarm = NSMenu(title: "Swarm")
    add(swarm, "New Swarm", "t", "new")
    add(swarm, "Rename Swarm…", "r", "renameActive", [.command, .shift])
    add(swarm, "Close Swarm", "w", "closeActive")
    swarm.addItem(.separator())
    add(swarm, "Link Machine…", "", "linkMachine")
    add(swarm, "Add Project…", "", "addProject")
    install(swarm, at: 1)
    let agent = NSMenu(title: "Agent")
    add(agent, "New Agent…", "n", "newAgent")
    agent.addItem(.separator())
    add(agent, "Split Right…", "", "splitRight")
    add(agent, "Split Down…", "", "splitDown")
    agent.addItem(.separator())
    add(agent, "Zoom Agent", "", "zoomPane")
    add(agent, "Pin or Unpin Agent", "", "pinPane")
    agent.addItem(.separator())
    add(agent, "Close Agent", "w", "closePane", [.command, .shift])
    install(agent, at: 2)

    rebuildHistoryMenu()
    install(historyMenu, at: 3)

    // Native menu hints mirror Flutter; the shared picker owns all editing.
    if let edit = main.item(withTitle: "Edit")?.submenu {
      edit.addItem(.separator())
      add(edit, "Navigate to Agent or Swarm…", "p", "jump")
      add(edit, "Search Commands…", "p", "commands", [.command, .shift])
    }
    if let view = main.item(withTitle: "View")?.submenu {
      view.addItem(.separator())
      add(view, "Agents Needing Input…", "i", "notifications", [.command, .shift])
    }
    modelsMenu.autoenablesItems = false
    modelsMenu.delegate = self
    rebuildModelsMenu()
    install(modelsMenu, at: 3)
    installTerminalFindMenu(main)
  }

  func menuWillOpen(_ menu: NSMenu) {
    syncMenuKeys()
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
    let rowWidth = subscriptions.map(SwarmSubscriptionView.preferredWidth).max() ?? 440
    for entry in subscriptions {
      let item = NSMenuItem(title: entry.accessibilityLabel, action: nil, keyEquivalent: "")
      let icon = historyIcons.image(engine: entry.engine, asset: entry.iconAsset)
      item.view = SwarmSubscriptionView(entry: entry, icon: icon, width: rowWidth)
      item.toolTip = entry.details.joined(separator: "\n")
      item.isEnabled = false
      modelsMenu.addItem(item)
    }
    if subscriptions.isEmpty {
      label("Anthropic", in: modelsMenu)
      label("OpenAI", in: modelsMenu)
    }
    modelsMenu.addItem(.separator())
    section("API")
    label("OpenRouter", in: modelsMenu)
    label("fal.ai", in: modelsMenu)
    modelsMenu.addItem(.separator())
    section("Local")
    label("DeepSeek V4 Flash", in: modelsMenu)
    label("Qwen3.8-27B", in: modelsMenu)
    modelsMenu.addItem(.separator())
    label("Add Model", in: modelsMenu)
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
      item.identifier = NSUserInterfaceItemIdentifier(HarnessKeymapMenu.actionPrefix + action)
      item.keyEquivalentModifierMask = [.command]
      historyMenu.addItem(item)
    }
    command("Back", "[", "historyBack")
    command("Forward", "]", "historyForward")
    let reopen = NSMenuItem(title: "Reopen Last Closed", action: #selector(menuAction(_:)), keyEquivalent: "t")
    reopen.target = self
    reopen.representedObject = "reopen"
    reopen.identifier = NSUserInterfaceItemIdentifier(HarnessKeymapMenu.actionPrefix + "reopen")
    reopen.keyEquivalentModifierMask = [.command, .shift]
    historyMenu.addItem(reopen)
    historyMenu.addItem(.separator())
    appendHistorySection("Recently Closed", entries: Array(closedHistory.prefix(10)), closed: true)
    historyMenu.addItem(.separator())
    appendHistorySection("Recently Visited", entries: Array(history.prefix(15)), closed: false)
    historyMenu.addItem(.separator())
    command("Show Full History", "y", "showHistory")
    if let keymap { keymap.applyMenuKeys(to: historyMenu, context: flutterKeyContext) }
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
      item.attributedTitle = entry.menuTitle
      item.target = self
      item.representedObject = entry.id
      item.toolTip = [entry.title, entry.machineName, entry.detail].filter { !$0.isEmpty }.joined(separator: "\n")
      item.state = entry.current ? .on : .off
      item.image = entry.swarm
        ? SwarmIdentity.menuIcon
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
      item.identifier = NSUserInterfaceItemIdentifier(HarnessKeymapMenu.actionPrefix + action)
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
      (!["findTerminal", "findNext", "findPrevious", "splitRight", "splitDown", "zoomPane", "pinPane"].contains(action) || canFind)
  }

  @objc private func menuAction(_ sender: NSMenuItem) {
    guard validateMenuItem(sender), let action = sender.representedObject as? String else { return }
    sendTabAction(action, arguments: nil)
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

private enum SwarmIdentity {
  // Same four-pane symbol as widgets/swarm_icon.dart.
  static let menuIcon = NSImage(systemSymbolName: "square.split.2x2", accessibilityDescription: nil)
}

private struct SwarmSubscriptionEntry: Equatable {
  let title: String
  let account: String
  let status: String
  let details: [String]
  let engine: String?
  let iconAsset: String?

  init?(_ row: [String: Any]) {
    guard let title = row["title"] as? String, !title.isEmpty,
          let status = row["status"] as? String else { return nil }
    self.title = title
    account = row["account"] as? String ?? ""
    self.status = status
    details = Array((row["details"] as? [String] ?? [status]).prefix(16))
    engine = row["engine"] as? String
    iconAsset = row["iconAsset"] as? String
  }

  var accessibilityLabel: String {
    [title, account, status].filter { !$0.isEmpty }.joined(separator: ", ")
  }
}

/// Read-only account information, with aligned trailing balances. There is no
/// action or submenu to suggest another step just to read the remaining usage.
private final class SwarmSubscriptionView: NSView {
  private static let rowFont = NSFont.menuFont(ofSize: 0)
  let identity = NSTextField(labelWithString: "")
  let balance = NSTextField(labelWithString: "")
  private let icon = NSImageView()

  private static func textWidth(_ text: String) -> CGFloat {
    // Include the native text cell's horizontal drawing insets. Measuring only
    // glyphs or a label already constrained by its frame can clip the status.
    ceil((text as NSString).size(withAttributes: [.font: rowFont]).width) + 8
  }

  static func preferredWidth(_ entry: SwarmSubscriptionEntry) -> CGFloat {
    let identityWidth = textWidth(entry.title + "  " + entry.account)
    let balanceWidth = textWidth(entry.status)
    return min(720, max(440, identityWidth + balanceWidth + 88))
  }

  init(entry: SwarmSubscriptionEntry, icon: NSImage, width: CGFloat) {
    super.init(frame: NSRect(x: 0, y: 0, width: width, height: 26))
    autoresizingMask = [.width]
    self.icon.image = icon
    self.icon.imageScaling = .scaleProportionallyDown
    let title = NSMutableAttributedString(string: entry.title,
      attributes: [.font: Self.rowFont, .foregroundColor: NSColor.labelColor])
    if !entry.account.isEmpty {
      title.append(NSAttributedString(string: "  " + entry.account,
        attributes: [.font: Self.rowFont, .foregroundColor: NSColor.secondaryLabelColor]))
    }
    identity.attributedStringValue = title
    identity.usesSingleLineMode = true
    identity.lineBreakMode = .byTruncatingMiddle
    balance.stringValue = entry.status
    balance.font = Self.rowFont
    balance.textColor = .secondaryLabelColor
    balance.alignment = .right
    balance.usesSingleLineMode = true
    balance.lineBreakMode = .byClipping
    for view in [self.icon, identity, balance] {
      addSubview(view)
      view.setAccessibilityElement(false)
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityLabel(entry.accessibilityLabel)
    toolTip = entry.details.joined(separator: "\n")
    layout()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layout() {
    super.layout()
    icon.frame = NSRect(x: 16, y: (bounds.height - 16) / 2, width: 16, height: 16)
    let height = ceil(Self.rowFont.ascender - Self.rowFont.descender + Self.rowFont.leading)
    let balanceWidth = Self.textWidth(balance.stringValue)
    balance.frame = NSRect(x: bounds.width - 18 - balanceWidth,
      y: (bounds.height - height) / 2, width: balanceWidth, height: height)
    identity.frame = NSRect(x: 40, y: balance.frame.minY,
      width: max(0, balance.frame.minX - 24 - 40), height: height)
  }
}

private struct SwarmHistoryEntry: Equatable {
  let id: String
  let title: String
  let detail: String
  let machineName: String
  let swarm: Bool
  let current: Bool
  let engine: String?
  let iconAsset: String?
  let canReopen: Bool
  var menuTitle: NSAttributedString {
    let font = NSFont.menuFont(ofSize: 0)
    func fitted(_ text: String, width: CGFloat) -> String {
      var value = text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
      if (value as NSString).size(withAttributes: [.font: font]).width <= width { return value }
      while !value.isEmpty && ((value + "…") as NSString).size(withAttributes: [.font: font]).width > width { value.removeLast() }
      return value + "…"
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 660)]
    let name = fitted(title, width: machineName.isEmpty ? 660 : 430)
    let machine = fitted(machineName, width: 206)
    return NSAttributedString(string: machine.isEmpty ? name : name + "\t" + machine,
      attributes: [.font: font, .paragraphStyle: paragraph])
  }

  init?(_ row: [String: Any]) {
    guard let id = row["id"] as? String, let title = row["title"] as? String else { return nil }
    self.id = id
    self.title = title
    detail = row["detail"] as? String ?? ""
    machineName = row["machineName"] as? String ?? ""
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
    // Flutter ships desktop assets inside App.framework, not the runner bundle.
    let framework = Bundle.main.privateFrameworksURL?.appendingPathComponent("App.framework")
    let bundle = framework.flatMap { Bundle(url: $0) }
      ?? Bundle(identifier: "io.flutter.flutter.app")
      ?? Bundle.main
    return bundle.resourceURL?.appendingPathComponent("flutter_assets").appendingPathComponent(asset)
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
/// Dart's palette is authoritative. These defaults match Graphite before its
/// first snapshot arrives; every window retains its own resolved colors.
private struct SwarmNativePalette: Equatable {
  let tabBar: NSColor
  let workspace: NSColor
  let search: NSColor
  let accent: NSColor

  init(_ values: [String: Any] = [:]) {
    func color(_ name: String, _ fallback: UInt32) -> NSColor {
      let supplied = values[name] as? Int64
      let valid = supplied.map { $0 >= 0 && $0 <= Int64(UInt32.max) && ($0 >> 24) == 255 } ?? false
      let argb = valid ? UInt32(supplied!) : fallback
      return NSColor(srgbRed: CGFloat((argb >> 16) & 255) / 255,
        green: CGFloat((argb >> 8) & 255) / 255, blue: CGFloat(argb & 255) / 255, alpha: 1)
    }
    tabBar = color("tabBar", 0xff1c1c1c)
    workspace = color("workspace", 0xff282828)
    search = color("search", 0xff2c2c2c)
    accent = color("accent", 0xffbdcbdc)
  }
}

private final class SwarmNotificationButton: NSButton {
  var hasAttention = false { didSet { needsDisplay = true } }
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if hasAttention {
      NSColor.systemOrange.setFill()
      NSBezierPath(ovalIn: NSRect(x: bounds.midX + 4, y: bounds.midY + 5, width: 5, height: 5)).fill()
    }
  }
}

private final class SwarmTabStrip: NSView {
  private(set) var palette = SwarmNativePalette()
  var emit: ((String, Any?) -> Void)?
  private let scroll = NSScrollView()
  private let document = NSView()
  private let newButton = NSButton()
  fileprivate let searchButton = NSButton()
  fileprivate let notificationButton = SwarmNotificationButton()
  fileprivate let settingsButton = NSButton()
  private var tabs: [SwarmTabButton] = []
  private var activeId = ""
  private var revealActiveAfterLayout = false
  private var tabOrderChanged = false
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
      button.title = ""
      button.imagePosition = .imageOnly
      button.contentTintColor = palette.accent
      button.target = self
      button.action = action
      button.toolTip = label
      button.setAccessibilityLabel(label)
      addSubview(button)
    }
    button(newButton, "plus", "New swarm (⌘T)", #selector(newSwarm))
    newButton.isEnabled = false
    button(searchButton, "safari", "Navigate (⌘P)", #selector(openSearch))
    searchButton.setAccessibilityLabel("Navigate")
    button(notificationButton, "bell", "Notifications", #selector(openNotifications))
    button(settingsButton, "gearshape", "Settings (⌘,)", #selector(openSettings))
    searchButton.isEnabled = false
    notificationButton.isEnabled = false
    settingsButton.isEnabled = false
    registerForDraggedTypes([swarmPasteboardType])
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func updatePalette(_ values: [String: Any]) {
    let nextPalette = SwarmNativePalette(values)
    guard nextPalette != palette else { return }
    palette = nextPalette
    searchButton.contentTintColor = palette.accent
    notificationButton.contentTintColor = palette.accent
    settingsButton.contentTintColor = palette.accent
    newButton.contentTintColor = palette.accent
    for tab in tabs { tab.palette = palette }
    needsDisplay = true
  }

  func update(_ state: [String: Any]) {
    // Workspace teardown clears its controls without changing appearance.
    if let palette = state["palette"] as? [String: Any] { updatePalette(palette) }
    actionsEnabled = state["enabled"] as? Bool == true
    let rows = state["tabs"] as? [[String: Any]] ?? []
    let nextActiveId = state["activeId"] as? String ?? ""
    revealActiveAfterLayout = revealActiveAfterLayout || nextActiveId != activeId
    activeId = nextActiveId
    let ids = rows.compactMap { $0["id"] as? String }
    let previousOrder = tabs.map(\.swarmId)
    tabOrderChanged = tabOrderChanged || ids != previousOrder
    for tab in tabs where !ids.contains(tab.swarmId) { tab.removeFromSuperview() }
    let previous = Dictionary(uniqueKeysWithValues: tabs.map { ($0.swarmId, $0) })
    tabs = rows.compactMap { row in
      guard let id = row["id"] as? String else { return nil }
      let tab = previous[id] ?? SwarmTabButton(id: id)
      tab.palette = palette
      tab.name = row["name"] as? String ?? "New swarm"
      tab.selected = id == activeId
      tab.actionsEnabled = actionsEnabled
      tab.attention = (row["attention"] as? Int ?? 0) > 0
      tab.emit = { [weak self, weak tab] method, args in
        guard let self, let tab, self.actionsEnabled,
              self.tabs.contains(where: { $0 === tab }) else { return }
        self.emit?(method, args)
      }
      tab.hoverChanged = { [weak self] in self?.updateDividers() }
      if tab.superview == nil { document.addSubview(tab) }
      tab.needsDisplay = true
      return tab
    }
    updateDividers()
    // Moving frames alone leaves AppKit's child traversal in insertion order.
    document.setAccessibilityChildren(tabs)
    newButton.isEnabled = actionsEnabled && tabs.count < 24
    searchButton.isEnabled = actionsEnabled
    notificationButton.isEnabled = actionsEnabled
    settingsButton.isEnabled = actionsEnabled
    let attention = state["attention"] as? Int ?? 0
    notificationButton.hasAttention = attention > 0
    notificationButton.toolTip = attention > 0 ? "\(attention) agents need input" : "Notifications"
    notificationButton.setAccessibilityLabel(notificationButton.toolTip)
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
    let active = tabs.first(where: { $0.swarmId == activeId })
    let activeWasVisible = active.map { scroll.documentVisibleRect.intersects($0.frame) } ?? false
    let previousScrollSize = scroll.frame.size
    let previousDocumentSize = document.frame.size
    // 164, not 124: the right-hand controls are three buttons on a 40pt pitch
    // now, and this is what keeps the tab scroller from sliding under them. A
    // button added below without widening this is a tab clipped by a gear.
    let available = max(132, bounds.width - 164)
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
    searchButton.frame = NSRect(x: bounds.width - 120, y: buttonY, width: 28, height: 28)
    notificationButton.frame = NSRect(x: bounds.width - 80, y: buttonY, width: 28, height: 28)
    settingsButton.frame = NSRect(x: bounds.width - 40, y: buttonY, width: 28, height: 28)
    let geometryChanged = scroll.frame.size != previousScrollSize || document.frame.size != previousDocumentSize
    if let active, revealActiveAfterLayout || (activeWasVisible && (geometryChanged || tabOrderChanged)) {
      document.scrollToVisible(active.frame)
    }
    revealActiveAfterLayout = false
    tabOrderChanged = false
  }
  override func draw(_ dirtyRect: NSRect) {
    // The selected tab meets this edge; its bottom corners are shoulders,
    // rather than the rounded bottom of a separate pill.
    palette.workspace.setFill()
    NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()

  }
  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 { window?.performZoom(nil) }
    else { window?.performDrag(with: event) }
  }
  @objc private func newSwarm() {
    if actionsEnabled && newButton.isEnabled { emit?("new", nil) }
  }
  @objc private func openSearch() {
    if actionsEnabled { emit?("jump", nil) }
  }
  @objc private func openNotifications() {
    if actionsEnabled { emit?("notifications", nil) }
  }

  // "settings" deliberately stays OUT of sendTabAction's focus-restore list,
  // unlike its neighbours here. Flutter's `case 'settings'` AWAITS the whole
  // Settings screen, so the acknowledgement this button waits on would not
  // arrive until Settings closed — and the responder it then grabbed would be
  // taken from whatever the user had moved on to. The app menu's ⌘, has always
  // used this same plain path.
  @objc private func openSettings() {
    if actionsEnabled { emit?("settings", nil) }
  }


  private func draggedTab(_ sender: NSDraggingInfo) -> SwarmTabButton? {
    guard actionsEnabled, sender.draggingSourceOperationMask.contains(.move),
          let source = sender.draggingSource as? SwarmTabButton,
          tabs.contains(where: { $0 === source }),
          sender.draggingPasteboard.string(forType: swarmPasteboardType) == source.swarmId,
          scroll.frame.contains(convert(sender.draggingLocation, from: nil)) else { return nil }
    return source
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggedTab(sender) == nil ? [] : .move }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggedTab(sender) == nil ? [] : .move }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let source = draggedTab(sender), let old = tabs.firstIndex(where: { $0 === source }) else { return false }
    let point = document.convert(sender.draggingLocation, from: nil)
    let index = tabs.firstIndex(where: { point.x < $0.frame.midX }) ?? tabs.count
    let destination = max(0, index > old ? index - 1 : index)
    if destination != old { emit?("reorder", ["id": source.swarmId, "index": destination]) }
    return true
  }
}

private final class SwarmTabButton: NSView, NSDraggingSource, NSMenuItemValidation {
  var palette = SwarmNativePalette() {
    didSet { if palette != oldValue { needsDisplay = true } }
  }
  let swarmId: String
  var name = "New swarm" { didSet { if name != oldValue { invalidateLabel(); updateAccessibility() } } }
  var selected = false { didSet { if selected != oldValue { invalidateLabel(); updateAccessibility() } } }
  var attention = false { didSet { if attention != oldValue { needsDisplay = true; updateAccessibility() } } }
  var showsDivider = false { didSet { if showsDivider != oldValue { needsDisplay = true } } }
  var contentCenterY: CGFloat = 20
  var emit: ((String, Any?) -> Void)?
  var hoverChanged: (() -> Void)?
  var isHovered: Bool { hovered && actionsEnabled }
  private let closeButton = SwarmTabActionButton()
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
    closeButton.owner = self
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
      palette.workspace.setFill()
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
    selectButton.setAccessibilityHelp(attention ? "Contains agents needing input" : nil)
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
private class SwarmTabActionButton: NSButton {
  weak var owner: SwarmTabButton?
  override func becomeFirstResponder() -> Bool {
    guard super.becomeFirstResponder() else { return false }
    if let owner { owner.scrollToVisible(owner.bounds) }
    return true
  }
}

private final class SwarmSelectButton: SwarmTabActionButton {
  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    owner?.mouseDown(with: event)
  }
  override func mouseDragged(with event: NSEvent) {
    guard isEnabled else { return }
    owner?.mouseDragged(with: event)
  }
}
