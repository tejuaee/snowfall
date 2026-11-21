// Snowfall — a transparent, click-through snow overlay for the macOS desktop.
//
// One borderless window per screen, each hosting the canvas page in index.html.
// The windows sit above ordinary windows, join every Space, and ignore the mouse,
// so the snow falls over whatever you are doing without ever getting in the way.
//
// Build & run:  ./snow.sh        (or: swiftc -O Snow.swift -o snowfall && ./snowfall)

import AppKit
import WebKit

// MARK: - One overlay window per screen

final class SnowOverlay {
    let window: NSWindow
    let web: WKWebView

    init(screen: NSScreen, pageURL: URL, intensity: Int) {
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
        apply(intensity: intensity, afterLoad: true)
        window.orderFrontRegardless()
    }

    func apply(intensity: Int, afterLoad: Bool = false) {
        let js = "window.setIntensity && window.setIntensity(\(intensity));"
        // Right after loadFileURL the page may not be parsed yet, so give it a beat.
        let delay = afterLoad ? 0.35 : 0.0
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // Snow on every attached display; rebuilt when displays are added or resized.
    private func startSnowing() {
        tearDownWindows()
        for screen in NSScreen.screens {
            overlays.append(SnowOverlay(screen: screen, pageURL: pageURL, intensity: intensity))
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
        overlays.forEach { $0.apply(intensity: intensity) }
        refreshMenu()
    }

    @objc private func quit() {
        tearDownWindows()
        NSApp.terminate(nil)
    }
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
