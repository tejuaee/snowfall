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

final class SnowOverlay {
    let window: NSWindow
    let web: WKWebView

    init(screen: NSScreen, pageURL: URL, intensity: Int, powerSaver: Bool) {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        web = WKWebView(frame: .zero, configuration: config)

        window = NSWindow(contentRect: screen.frame,
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

// MARK: - App

final class SnowController: NSObject, NSApplicationDelegate {
    private var overlays: [SnowOverlay] = []
    private var status: NSStatusItem?
    private var intensity = 2          // 1 light · 2 medium · 3 blizzard
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // Snow on every attached display; rebuilt when displays are added or resized.
    private func startSnowing() {
        tearDownWindows()
        for screen in NSScreen.screens {
            overlays.append(SnowOverlay(screen: screen, pageURL: pageURL,
                                        intensity: intensity, powerSaver: powerSaving))
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

    private(set) var easeOffOnBattery = true
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

    private func runningOnBattery() -> Bool {
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

    /// A window behind a full-screen app, or on a Space you are not looking at, loses
    /// `.visible`. Its snow stops entirely instead of spending GPU time on frames that
    /// are never composited.
    private func updatePause() {
        let allHidden = displayAsleep || screenLocked
        for overlay in overlays {
            let hidden = allHidden || !overlay.window.occlusionState.contains(.visible)
            overlay.setPaused(hidden)
        }
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

    @objc private func setIntensity(_ sender: NSMenuItem) {
        intensity = sender.tag
        overlays.forEach { $0.push(intensity: intensity, powerSaver: powerSaving) }
        refreshMenu()
    }

    @objc private func quit() {
        tearDownWindows()
        NSApp.terminate(nil)
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
