// Loads index.html in a real WebKit view and asks it whether it is alive: no errors
// thrown during start-up, every hook the app calls present, flakes created, frames
// drawn. A single exception while the script is initialising leaves the overlay
// completely blank, and parsing the file cannot see that coming.
import AppKit
import WebKit

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "index.html"
let page = URL(fileURLWithPath: path).absoluteURL

let probeJS = """
JSON.stringify({
  errors: window.__errors || [],
  missing: ['setIntensity','setPaused','setPowerSaver','applySettings','sendPlow',
            'setLedges','setInteractive','clearPile','setPile','getPile']
             .filter((name) => typeof window[name] !== 'function'),
  state: window.__snowState ? window.__snowState() : null
})
"""

final class Probe: NSObject, WKNavigationDelegate {
    let web: WKWebView
    var finished = false
    var failure: String?
    var summary = ""

    override init() {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(WKUserScript(
            source: """
            window.__errors = [];
            window.addEventListener('error', (e) => window.__errors.push(String(e.message)));
            window.addEventListener('unhandledrejection',
                                    (e) => window.__errors.push('promise: ' + e.reason));
            """,
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: config)
        super.init()
        web.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.inspect() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("the page failed to load: \(error.localizedDescription)")
    }

    private func inspect() {
        web.evaluateJavaScript(probeJS) { value, error in
            guard let json = (value as? String)?.data(using: .utf8),
                  let report = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
            else { return self.fail("could not read the page: \(error?.localizedDescription ?? "?")") }

            let errors = report["errors"] as? [String] ?? []
            let missing = report["missing"] as? [String] ?? []
            let state = report["state"] as? [String: Any]
            let flakes = state?["flakes"] as? Int ?? 0
            let frames = state?["frames"] as? Int ?? 0

            if !errors.isEmpty { return self.fail("the page threw: \(errors.joined(separator: "; "))") }
            if !missing.isEmpty { return self.fail("hooks missing: \(missing.joined(separator: ", "))") }
            if state == nil { return self.fail("the engine never finished starting up") }
            if flakes < 1 { return self.fail("no flakes were created") }
            if frames < 1 { return self.fail("no frame was ever drawn") }

            self.summary = "\(flakes) flakes, \(frames) frames"
            self.finished = true
        }
    }

    private func fail(_ message: String) {
        failure = message
        finished = true
    }
}

let probe = Probe()
probe.web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())

let deadline = Date().addingTimeInterval(25)
while !probe.finished && Date() < deadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
}

if let failure = probe.failure {
    FileHandle.standardError.write(Data("  \(failure)\n".utf8))
    exit(1)
}
guard probe.finished else {
    FileHandle.standardError.write(Data("  the page never reported back\n".utf8))
    exit(1)
}
print("  page alive: \(probe.summary)")
