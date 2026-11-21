// Snowfall.saver — the same snow as a macOS screen saver, which is how it reaches the
// lock screen. A normal application cannot draw over the lock screen: that surface
// belongs to loginwindow. A screen saver, however, is what macOS itself runs when the
// Mac is idle or locked, so the snow is implemented a second time here.
//
// Drawn natively with Core Graphics rather than in a WKWebView: the screen saver host
// process is sandboxed and short on privileges, and a web view is a poor bet there.
//
// Build and install:  ./install-saver.sh

import ScreenSaver
import AppKit

@objc(SnowfallView)
final class SnowfallView: ScreenSaverView {

    private struct Flake {
        var x: CGFloat, y: CGFloat, r: CGFloat
        var vy: CGFloat, sway: CGFloat, phase: CGFloat, spin: CGFloat
        var bucket: Int
    }

    private static let buckets = 5
    private var flakes: [Flake] = []
    private var wind: CGFloat = 0
    private var windGoal: CGFloat = 0
    private var windTimer: CGFloat = 0
    private var seededSize: NSSize = .zero

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0   // same 30 fps budget as the overlay
        wantsLayer = true
        seed()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: Model

    private func seed() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let count = max(40, Int(bounds.width * bounds.height / 9000))
        flakes = (0..<count).map { _ in makeFlake(seeded: true) }
        seededSize = bounds.size
    }

    private func makeFlake(seeded: Bool) -> Flake {
        // depth 0 = far away (small, slow, faint), 1 = close to the glass
        let depth = pow(CGFloat.random(in: 0...1), 1.6)
        return Flake(
            x: .random(in: -40...(bounds.width + 40)),
            y: seeded ? .random(in: 0...bounds.height)
                      : bounds.height + .random(in: 10...60),
            r: 0.7 + depth * 2.6,
            vy: 14 + depth * 46,
            sway: CGFloat.random(in: 10...34) * (0.4 + depth),
            phase: .random(in: 0...(2 * .pi)),
            spin: .random(in: 0.4...1.3),
            bucket: min(Self.buckets - 1, Int((0.28 + depth * 0.62) * CGFloat(Self.buckets)))
        )
    }

    override func layout() {
        super.layout()
        if flakes.isEmpty || seededSize != bounds.size { seed() }
    }

    // MARK: Animation

    override func animateOneFrame() {
        let dt = CGFloat(animationTimeInterval)

        windTimer -= dt
        if windTimer <= 0 {
            windGoal = .random(in: -34...34)
            windTimer = .random(in: 3...8)
        }
        wind += (windGoal - wind) * min(dt * 0.5, 1)

        for i in flakes.indices {
            flakes[i].phase += flakes[i].spin * dt
            flakes[i].y -= flakes[i].vy * dt          // AppKit is y-up, so down is minus
            flakes[i].x += (wind * 0.6 + sin(flakes[i].phase) * flakes[i].sway) * dt

            if flakes[i].y + flakes[i].r < 0 {
                flakes[i] = makeFlake(seeded: false)
            } else if flakes[i].x < -60 {
                flakes[i].x = bounds.width + 50
            } else if flakes[i].x > bounds.width + 60 {
                flakes[i].x = -50
            }
        }

        needsDisplay = true
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // One path and one fill per opacity bucket, as in the web engine.
        for bucket in 0..<Self.buckets {
            ctx.setFillColor(gray: 1, alpha: (CGFloat(bucket) + 0.5) / CGFloat(Self.buckets))
            ctx.beginPath()
            for f in flakes where f.bucket == bucket {
                ctx.addEllipse(in: CGRect(x: f.x - f.r, y: f.y - f.r,
                                          width: f.r * 2, height: f.r * 2))
            }
            ctx.fillPath()
        }
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
