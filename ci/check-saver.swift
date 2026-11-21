// Loads Snowfall.saver the way macOS does — bundle, principal class, real frames — and
// asserts that it actually puts white pixels on screen. Catches the failures that are
// otherwise invisible until you lock the Mac: a principal class macOS cannot find, a
// bundle that will not load, an animation that draws nothing.
import AppKit
import ScreenSaver

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/Snowfall.saver"

guard let bundle = Bundle(path: path) else { fatalError("no bundle at \(path)") }
guard bundle.load() else { fatalError("bundle refused to load: \(path)") }
guard let type = bundle.principalClass as? ScreenSaverView.Type else {
    fatalError("principal class is not a ScreenSaverView: \(String(describing: bundle.principalClass))")
}

let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
guard let view = type.init(frame: frame, isPreview: false) else {
    fatalError("the saver's init(frame:isPreview:) returned nil")
}

for _ in 0..<20 { view.animateOneFrame() }

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: Int(frame.width), pixelsHigh: Int(frame.height),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else {
    fatalError("could not make a bitmap to draw into")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
view.draw(frame)
NSGraphicsContext.restoreGraphicsState()

var lit = 0
if let data = rep.bitmapData {
    var i = 0
    let bytes = rep.bytesPerRow * rep.pixelsHigh
    while i < bytes {
        if data[i] > 128 { lit += 1 }
        i += 4
    }
}

print("  \(type) drew \(lit) lit pixels after 20 frames")
guard lit > 50 else { fatalError("the saver drew nothing") }
