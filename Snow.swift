// Snowfall — a transparent, click-through snow overlay for the macOS desktop.
//
// One borderless window per screen, each hosting the canvas page in index.html.
// The windows sit above ordinary windows, join every Space, and ignore the mouse,
// so the snow falls over whatever you are doing without ever getting in the way.
//
// Build & run:  ./snow.sh        (or: swiftc -O Snow.swift -o snowfall && ./snowfall)

import AppKit
import WebKit
import IOKit.ps
import IOKit.pwr_mgt

// MARK: - One overlay window per screen

/// Borderless windows refuse key status by default, which would leave Snowball Mode
/// with no way to hear the Escape key. No initialisers of its own, so it inherits all
/// of NSWindow's.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class SnowOverlay {
    let window: NSWindow
    let web: WKWebView
    let screen: NSScreen

    init(screen: NSScreen, pageURL: URL, intensity: Int, powerSaver: Bool,
         handler: WKScriptMessageHandler?) {
        self.screen = screen
        let config = WKWebViewConfiguration()
        if let handler {
            let content = WKUserContentController()
            content.add(handler, name: "snowfall")
            config.userContentController = content
        }
        config.suppressesIncrementalRendering = false
        // An overlay that renders one local page needs none of the heavier WebKit
        // machinery: no cache or cookie writes to disk, no media, no fullscreen.
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = .all
        if #available(macOS 13.3, *) { config.preferences.isElementFullscreenEnabled = false }

        web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = false
        web.allowsMagnification = false
        web.allowsLinkPreview = false

        window = OverlayWindow(contentRect: screen.frame,
                               styleMask: [.borderless],
                               backing: .buffered,
                               defer: false,
                               screen: screen)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true      // clicks pass straight through to your apps
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.displaysWhenScreenProfileChanges = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                     .fullScreenAuxiliary, .ignoresCycle]

        // Keep the web view itself transparent: no white page behind the flakes.
        web.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) { web.underPageBackgroundColor = .clear }
        web.layer?.backgroundColor = .clear

        let host = NSView(frame: screen.frame)
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        web.frame = host.bounds
        web.autoresizingMask = [.width, .height]
        host.addSubview(web)
        window.contentView = host

        window.setFrame(screen.frame, display: true)
        web.loadFileURL(pageURL.appendingQueryItem("overlay", "1"),
                        allowingReadAccessTo: pageURL.deletingLastPathComponent())
        push(intensity: intensity, powerSaver: powerSaver, delay: 0.35)
        window.orderFrontRegardless()
    }

    private func run(_ js: String, delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.web.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func apply(_ settings: SnowSettings, delay: TimeInterval = 0) {
        run("window.applySettings && window.applySettings(\(settings.json));", delay: delay)
    }

    func sendPlow() { run("window.sendPlow && window.sendPlow();") }
    func setLedges(_ json: String) { run("window.setLedges && window.setLedges(\(json));") }

    /// Snowball Mode is the one time the overlay stops being click-through. While it is
    /// listening for the mouse it must also stop covering the menu bar, or the ❄ menu
    /// itself becomes unclickable.
    func setInteractive(_ on: Bool) {
        window.ignoresMouseEvents = !on

        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        window.setFrame(on ? NSRect(x: screen.frame.minX, y: screen.frame.minY,
                                    width: screen.frame.width,
                                    height: screen.frame.height - menuBar)
                           : screen.frame,
                        display: true)

        run("window.setInteractive && window.setInteractive(\(on));")
        if on { window.makeKeyAndOrderFront(nil) }
    }

    func readPile(_ done: @escaping (String?) -> Void) {
        web.evaluateJavaScript("JSON.stringify(window.getPile ? window.getPile() : [])") {
            value, _ in done(value as? String)
        }
    }

    func restorePile(_ json: String, delay: TimeInterval = 0.45) {
        run("window.setPile && window.setPile(\(json));", delay: delay)
    }
    func clearPile() { run("window.clearPile && window.clearPile();") }

    func setPaused(_ paused: Bool) {
        web.evaluateJavaScript("window.setPaused && window.setPaused(\(paused));",
                               completionHandler: nil)
    }

    /// Right after `loadFileURL` the page may not be parsed yet, hence the delay on
    /// the first push.
    func push(intensity: Int, powerSaver: Bool, delay: TimeInterval = 0) {
        let js = """
        window.setPowerSaver && window.setPowerSaver(\(powerSaver));
        window.setIntensity && window.setIntensity(\(intensity));
        """
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.web.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

private extension URL {
    func appendingQueryItem(_ name: String, _ value: String) -> URL {
        guard var c = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: name, value: value)]
        return c.url ?? self
    }
}

// MARK: - Settings

struct SnowSettings: Codable, Equatable {
    var settle: Bool = true             // whether snow lies at all
    var maxDepthPercent: Double = 100   // how much of the screen it may bury
    var autoPlowPercent: Double = 0     // plough itself at this depth; 0 = only on demand
    var plowCrossSeconds: Double = 7    // how long the truck takes to cross the screen
    var truckPercent: Double = 7        // truck height as a share of the screen
    var plowDirection: Int = 0          // 0 alternates, ±1 always from that side

    var json: String {
        guard let data = try? JSONEncoder().encode(self),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    static func load() -> SnowSettings {
        guard let data = UserDefaults.standard.data(forKey: "settings"),
              let stored = try? JSONDecoder().decode(SnowSettings.self, from: data)
        else { return SnowSettings() }
        return stored
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "settings")
        }
    }
}

/// The one window in this app you can actually click: sliders for the drift and the
/// plough, talking back over a WebKit message handler.
final class SettingsWindow: NSObject, WKScriptMessageHandler {
    let window: NSWindow
    private let web: WKWebView
    private let handle: ([String: Any]) -> Void

    init(pageURL: URL, settings: SnowSettings, handle: @escaping ([String: Any]) -> Void) {
        self.handle = handle

        let content = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = content
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 580), configuration: config)

        window = NSWindow(contentRect: web.frame,
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()

        content.add(self, name: "snowfall")
        window.title = "Snowfall"
        window.contentView = web
        window.isReleasedWhenClosed = false
        window.center()

        web.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.web.evaluateJavaScript(
                "window.loadSettings && window.loadSettings(\(settings.json));",
                completionHandler: nil)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        handle(body)
    }
}

// MARK: - Remembered settings

enum Defaults {
    private static let store = UserDefaults.standard

    static var intensity: Int {
        get { (1...3).contains(store.integer(forKey: "intensity")) ? store.integer(forKey: "intensity") : 2 }
        set { store.set(newValue, forKey: "intensity") }
    }

    static var easeOffOnBattery: Bool {
        get { store.object(forKey: "easeOffOnBattery") as? Bool ?? true }
        set { store.set(newValue, forKey: "easeOffOnBattery") }
    }
}

// MARK: - App

final class SnowController: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    private var overlays: [SnowOverlay] = []
    private var status: NSStatusItem?
    private var intensity = Defaults.intensity   // 1 light · 2 medium · 3 blizzard
    private var settings = SnowSettings.load()
    private var settingsWindow: SettingsWindow?
    private var snowballMode = false
    private var snowing = true
    private let pageURL: URL

    init(pageURL: URL) {
        self.pageURL = pageURL
        super.init()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenuBarItem()
        startSnowing()
        observeVisibility()
        observePower()

        // Keep the drift on disk so quitting, or a reboot, does not undo an evening of
        // snow. Every minute is often enough for something that accumulates this slowly.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.savePiles()
        }

        // Windows move; the snow on them should keep up without being expensive.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.publishLedges()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // Snow on every attached display; rebuilt when displays are added or resized.
    private func startSnowing() {
        tearDownWindows()
        for screen in NSScreen.screens {
            overlays.append(SnowOverlay(screen: screen, pageURL: pageURL,
                                        intensity: intensity, powerSaver: powerSaving,
                                        handler: self))
        }
        overlays.forEach { $0.apply(settings, delay: 0.4) }
        if snowballMode { overlays.forEach { $0.setInteractive(true) } }

        // A drift is hours of work. Put back whatever was on the ground last time.
        for (index, overlay) in overlays.enumerated() {
            if let stored = UserDefaults.standard.string(forKey: "pile.\(index)") {
                overlay.restorePile(stored)
            }
        }

        snowing = true
        refreshMenu()
    }

    private func tearDownWindows() {
        overlays.forEach { $0.window.orderOut(nil); $0.window.close() }
        overlays.removeAll()
    }

    @objc private func screensChanged() {
        guard snowing else { return }
        startSnowing()
    }

    // MARK: Battery awareness

    private(set) var easeOffOnBattery = Defaults.easeOffOnBattery
    private(set) var powerSaving = false

    private func observePower() {
        // Low Power Mode being switched on or off.
        NotificationCenter.default.addObserver(
            self, selector: #selector(powerStateChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil)

        // IOKit tells us when the Mac is plugged in or unplugged. The callback takes a
        // C function pointer, so it hands off through a notification.
        NotificationCenter.default.addObserver(
            self, selector: #selector(powerStateChanged), name: .snowPowerChanged, object: nil)
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .snowPowerChanged, object: nil)
            }
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        applyPowerState()
    }

    func runningOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return false }
        return (type as String) != kIOPMACPowerKey
    }

    @objc private func powerStateChanged() {
        applyPowerState()
        refreshMenu()
    }

    /// On battery or in Low Power Mode the snow runs at 20 fps, 1x pixels and a bit
    /// over half the flakes. It still snows; it just stops costing much.
    private func applyPowerState() {
        let saving = easeOffOnBattery
            && (runningOnBattery() || ProcessInfo.processInfo.isLowPowerModeEnabled)
        guard saving != powerSaving else { return }
        powerSaving = saving
        overlays.forEach { $0.push(intensity: intensity, powerSaver: powerSaving) }
    }

    func setEaseOffOnBattery(_ on: Bool) {
        easeOffOnBattery = on
        applyPowerState()
        refreshMenu()
    }

    // MARK: Never animate what nobody can see

    private var displayAsleep = false
    private var screenLocked = false

    private func observeVisibility() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(keepOnTop),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        ws.addObserver(self, selector: #selector(keepOnTop),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(displaysSlept),
                       name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(displaysWoke),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)

        // Screen lock is only published on the distributed centre.
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(sessionLocked),
                        name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(sessionUnlocked),
                        name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func occlusionChanged() { updatePause() }
    @objc private func displaysSlept() { displayAsleep = true; updatePause() }
    @objc private func displaysWoke() { displayAsleep = false; updatePause() }
    @objc private func sessionLocked() { screenLocked = true; updatePause() }
    @objc private func sessionUnlocked() { screenLocked = false; updatePause() }

    private var occlusionCheck: DispatchWorkItem?

    /// Occlusion flickers constantly in normal use: switching window, app, Space or tab
    /// makes macOS report the overlay covered for a moment and visible again right
    /// after. Pausing on that is what made the snow stutter and vanish for a split
    /// second. So going quiet is delayed by two seconds and re-checked, while coming
    /// back is immediate — being a frame late to stop costs nothing, being late to
    /// start is the bug you see.
    private func updatePause() {
        occlusionCheck?.cancel()

        if displayAsleep || screenLocked {
            overlays.forEach { $0.setPaused(true) }
            return
        }

        for overlay in overlays where overlay.window.occlusionState.contains(.visible) {
            overlay.setPaused(false)
        }

        guard overlays.contains(where: { !$0.window.occlusionState.contains(.visible) })
        else { return }

        let check = DispatchWorkItem { [weak self] in
            guard let self, !self.displayAsleep, !self.screenLocked else { return }
            for overlay in self.overlays {
                overlay.setPaused(!overlay.window.occlusionState.contains(.visible))
            }
        }
        occlusionCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: check)
    }

    /// Switching app or Space can leave the overlay ordered behind what you switched
    /// to, which looks like the snow disappearing. Re-assert the level and the order.
    @objc private func keepOnTop() {
        let top = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        for overlay in overlays {
            overlay.window.level = top
            overlay.window.orderFrontRegardless()
        }
        updatePause()
    }

    // MARK: Menu bar

    private func buildMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "❄"
        item.button?.toolTip = "Snowfall"
        item.menu = NSMenu()
        status = item
        refreshMenu()
    }

    private func refreshMenu() {
        guard let menu = status?.menu else { return }
        menu.removeAllItems()

        let description: String
        if powerSaving { description = "Easing off — saving power" }
        else if runningOnBattery() { description = "Full snow — on battery" }
        else { description = "Full snow — plugged in" }

        let state = NSMenuItem(title: description, action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: snowing ? "Stop Snow" : "Start Snow",
                                action: #selector(toggleSnow), keyEquivalent: "s")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        for (level, name) in [(1, "Light"), (2, "Medium"), (3, "Blizzard")] {
            let mi = NSMenuItem(title: name, action: #selector(setIntensity(_:)),
                                keyEquivalent: "\(level)")
            mi.target = self
            mi.tag = level
            mi.state = (level == intensity) ? .on : .off
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        let plow = NSMenuItem(title: "Send the Plough",
                              action: #selector(sendPlow), keyEquivalent: "p")
        plow.target = self
        menu.addItem(plow)

        let clear = NSMenuItem(title: "Clear the Snow",
                               action: #selector(clearSnow), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let snowballs = NSMenuItem(title: "Snowball Mode",
                                   action: #selector(toggleSnowballs), keyEquivalent: "n")
        snowballs.target = self
        snowballs.state = snowballMode ? .on : .off
        menu.addItem(snowballs)

        let prefs = NSMenuItem(title: "Snow Settings…",
                               action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())
        let ease = NSMenuItem(title: "Ease Off on Battery",
                              action: #selector(toggleEaseOff), keyEquivalent: "b")
        ease.target = self
        ease.state = easeOffOnBattery ? .on : .off
        menu.addItem(ease)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Snowfall", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleSnow() {
        if snowing {
            tearDownWindows()
            snowing = false
            refreshMenu()
        } else {
            startSnowing()
        }
    }

    // MARK: Snow on windows

    private struct Ledge { let id: Int; let rect: CGRect }

    /// Every window's top edge is somewhere snow can lie. Window geometry comes from
    /// CGWindowList, which needs no permission — only window *titles* are privileged,
    /// and those are of no interest here.
    private func publishLedges() {
        guard snowing, !overlays.isEmpty else { return }

        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        let mine = ProcessInfo.processInfo.processIdentifier

        // Front to back, which is the order CGWindowList returns.
        var windows: [Ledge] = []
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  (entry[kCGWindowOwnerPID as String] as? Int32) != mine,
                  let id = entry[kCGWindowNumber as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }

            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                              width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if rect.width < 90 || rect.height < 40 { continue }
            windows.append(Ledge(id: id, rect: rect))
        }

        guard let primary = NSScreen.screens.first else { return }

        for overlay in overlays {
            // Measured against the overlay window, not the screen: in Snowball Mode the
            // window sits below the menu bar, and page coordinates start at its top.
            let frame = overlay.window.frame
            let originX = frame.origin.x
            let originY = primary.frame.maxY - frame.maxY     // CoreGraphics counts down
            var payload: [[String: Any]] = []

            for (index, win) in windows.enumerated() {
                let top = win.rect.minY

                // What is left of this edge once the windows in front of it are removed.
                var spans = [(win.rect.minX, win.rect.maxX)]
                for other in windows[0..<index] where other.rect.minY <= top && other.rect.maxY > top {
                    spans = subtract(spans, other.rect.minX, other.rect.maxX)
                }
                spans = spans.filter { $0.1 - $0.0 > 40 }
                if spans.isEmpty { continue }

                let x = win.rect.minX - originX
                let y = top - originY

                // A full-screen window has no top edge you can see, so nothing should
                // appear to be lying on it. The same goes for anything reaching the
                // very top of the screen, where the menu bar is.
                let screenFrame = overlay.screen.frame
                let coversScreen = win.rect.width >= screenFrame.width - 2
                    && win.rect.height >= screenFrame.height - 2
                if coversScreen || y <= 2 { continue }

                if y < 0 || y > frame.height || x > frame.width || x + win.rect.width < 0 { continue }

                payload.append([
                    "id": "\(win.id)",
                    "x": Double(x),
                    "y": Double(y),
                    "w": Double(win.rect.width),
                    "spans": spans.map { [Double($0.0 - win.rect.minX), Double($0.1 - win.rect.minX)] }
                ])
            }

            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { continue }
            overlay.setLedges(json)
        }
    }

    private func subtract(_ spans: [(CGFloat, CGFloat)],
                          _ a: CGFloat, _ b: CGFloat) -> [(CGFloat, CGFloat)] {
        var out: [(CGFloat, CGFloat)] = []
        for span in spans {
            if b <= span.0 || a >= span.1 { out.append(span); continue }
            if a > span.0 { out.append((span.0, a)) }
            if b < span.1 { out.append((b, span.1)) }
        }
        return out
    }

    private func savePiles() {
        for (index, overlay) in overlays.enumerated() {
            overlay.readPile { json in
                guard let json, json.count > 2 else { return }
                UserDefaults.standard.set(json, forKey: "pile.\(index)")
            }
        }
    }

    /// While this is on the overlay swallows every click, which is the whole point and
    /// also the danger, so it is announced in the menu and Escape turns it off.
    @objc private func toggleSnowballs() {
        snowballMode.toggle()
        overlays.forEach { $0.setInteractive(snowballMode) }
        // Activating is what gets key presses — Escape — to the overlay. Deactivating
        // hands focus back; hiding would have taken the snow with it.
        if snowballMode { NSApp.activate(ignoringOtherApps: true) } else { NSApp.deactivate() }
        refreshMenu()
    }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if body["type"] as? String == "exitSnowball" {
            guard snowballMode else { return }
            snowballMode = false
            overlays.forEach { $0.setInteractive(false) }
            refreshMenu()
            return
        }
        received(body)
    }

    @objc private func sendPlow() { overlays.forEach { $0.sendPlow() } }
    @objc private func clearSnow() { overlays.forEach { $0.clearPile() } }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let page = pageURL.deletingLastPathComponent()
                .appendingPathComponent("settings.html")
            settingsWindow = SettingsWindow(pageURL: page, settings: settings) {
                [weak self] body in self?.received(body)
            }
        }
        settingsWindow?.show()
    }

    /// Messages from the settings page. Anything it sends is applied to every screen
    /// and written straight to disk, so the overlay and the window never disagree.
    private func received(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "settings":
            guard let raw = body["settings"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: raw),
                  let next = try? JSONDecoder().decode(SnowSettings.self, from: data)
            else { return }
            settings = next
            settings.save()
            overlays.forEach { $0.apply(settings) }
        case "plow": sendPlow()
        case "clear": clearSnow()
        default: break
        }
    }

    @objc private func toggleEaseOff() {
        setEaseOffOnBattery(!easeOffOnBattery)
        Defaults.easeOffOnBattery = easeOffOnBattery
    }

    @objc private func setIntensity(_ sender: NSMenuItem) {
        intensity = sender.tag
        Defaults.intensity = intensity
        overlays.forEach { $0.push(intensity: intensity, powerSaver: powerSaving) }
        refreshMenu()
    }

    @objc private func quit() {
        savePiles()
        // Reading the drift out of the page is asynchronous, so give it a moment to
        // land on disk before the process goes away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.tearDownWindows()
            NSApp.terminate(nil)
        }
    }
}

extension Notification.Name {
    static let snowPowerChanged = Notification.Name("snowfall.powerSourceChanged")
}

// MARK: - Entry point

let here = URL(fileURLWithPath: CommandLine.arguments.first ?? ".")
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()

let candidates = [here.appendingPathComponent("index.html"),
                  URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                      .appendingPathComponent("index.html")]

guard let page = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
    FileHandle.standardError.write(
        Data("snowfall: could not find index.html next to the binary\n".utf8))
    exit(1)
}

let app = NSApplication.shared
let controller = SnowController(pageURL: page)
app.delegate = controller
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon, never steals focus
app.run()
