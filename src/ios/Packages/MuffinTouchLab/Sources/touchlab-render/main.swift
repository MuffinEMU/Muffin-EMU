import CoreGraphics
import Foundation
import TouchLabCore

// Writes <dir>/<scheme>-<device>-<display>.svg for every combination, plus an index.html.

final class NullOutput: PadOutput {
    func setButton(_ button: PadButton, pressed: Bool) {}
    func setStick(_ stick: PadStick, _ value: StickValue) {}
    func setTouchscreen(_ point: CGPoint?) {}
    func releaseAll() {}
}

let dir = CommandLine.arguments.dropFirst().first ?? "docs/previews"
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
var index = "<!doctype html><meta charset=utf-8><title>TouchLab previews</title><body style='background:#000;color:#ccc;font-family:sans-serif'>"

for info in SchemeCatalog.all where info.id != ShowcasePad.schemeInfo.id {
    index += "<h2>\(info.name)</h2><p>\(info.summary)</p>"
    for device in TargetDevice.all + (info.id == ArcPad.schemeInfo.id ? TargetDevice.portraitVariants : []) {
        for display in TargetDevice.Display.allCases {
            let ctx = device.context(display)
            let engine = PadEngine(scheme: SchemeCatalog.make(info.id), output: NullOutput(), context: ctx)
            var title = "\(info.name) - \(device.name) - \(display.rawValue)"
            if let frame = engine.scheme as? FramePad { title += " (\(frame.mode))" }
            let svg: String
            if PadStyle.appliesTo(info.id) {
                let scene = PadStyle.scene(elements: engine.render(), size: ctx.size)
                svg = ShowcaseSVG.svg(scene: scene, videoRects: ctx.videoRects, safe: ctx.safeBounds, title: title)
            } else {
                svg = SVGRenderer.svg(size: ctx.size, videoRects: ctx.videoRects, safe: ctx.safeBounds,
                                      title: title, elements: engine.render())
            }
            let slug = device.name.lowercased().replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            let file = "\(info.id)-\(slug)-\(display.rawValue).svg"
            try svg.write(toFile: "\(dir)/\(file)", atomically: true, encoding: .utf8)
            index += "<img src='\(file)' width='480' style='margin:4px'>"
        }
    }
}
// Showcase: its own previews, on the five review devices in both orientations. Native lays out
// its own picture, so it is drawn once; Fit is drawn around each host layout.
do {
    func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }
    func draw(_ device: TargetDevice, display: TargetDevice.Display, mode: ShowcaseLayout.DisplayMode,
              colour: ShowcaseColourPreset = .wiiUWhite, backdrop: ShowcaseSVG.Backdrop = .dark, demo: Bool = false,
              glass: Bool = false, opacity: CGFloat = PadSettings.defaultOpacity, name: String) throws {
        let ctx = device.context(display)
        let pad = ShowcasePad()
        pad.pointsPerInch = device.showcasePointsPerInch
        pad.displayMode = mode
        pad.colourPreset = colour
        pad.glass = glass
        let engine = PadEngine(scheme: pad, output: NullOutput(), context: ctx)
        if demo { ShowcaseDemo.press(engine, pad) }
        let scene = pad.scene(pressed: engine.mixer.pressed, sticks: engine.mixer.sticks, opacity: opacity)
        let rects = pad.pictureRect.map { [$0] } ?? ctx.videoRects
        let size = String(format: "%.0f%% of life size", Double(pad.lifeSizeFraction) * 100)
        let title = "Showcase - \(device.name) - \(mode == .native ? "native" : "fit \(display.rawValue) (\(pad.arrangement))") - \(size)"
        let svg = ShowcaseSVG.svg(scene: scene, videoRects: rects, safe: ctx.safeBounds, title: title, backdrop: backdrop)
        try svg.write(toFile: "\(dir)/showcase/\(name).svg", atomically: true, encoding: .utf8)
        index += "<img src='showcase/\(name).svg' width='480' style='margin:4px'>"
    }
    try FileManager.default.createDirectory(atPath: "\(dir)/showcase", withIntermediateDirectories: true)
    index += "<h2>Showcase</h2><p>\(ShowcasePad.schemeInfo.summary)</p>"
    for device in TargetDevice.showcaseReview {
        let s = slug(device.name)
        try draw(device, display: .stacked, mode: .native, name: "\(s)-native")
        try draw(device, display: .stacked, mode: .fit, name: "\(s)-fit-stacked")
        try draw(device, display: .single, mode: .fit, name: "\(s)-fit-single")
    }
    // Colours, a held state, and a light picture behind it, on the iPad Pro 11 and an iPhone.
    let pro = TargetDevice.showcaseReview.first { $0.name == "iPad Pro 11 (A12Z)" }!
    let phone = TargetDevice.showcaseReview.first { $0.name == "iPhone 16 Pro Max" }!
    for colour in ShowcaseColourPreset.allCases {
        try draw(pro, display: .stacked, mode: .fit, colour: colour, name: "colour-\(colour.rawValue)-ipad-pro-11-fit")
        try draw(phone, display: .stacked, mode: .native, colour: colour, name: "colour-\(colour.rawValue)-iphone-16-pro-max-native")
    }
    try draw(pro, display: .stacked, mode: .fit, demo: true, name: "held-ipad-pro-11-fit")
    try draw(pro, display: .stacked, mode: .fit, backdrop: .light, demo: true, name: "light-held-ipad-pro-11-fit")
    try draw(phone, display: .stacked, mode: .native, backdrop: .light, demo: true, name: "light-held-iphone-16-pro-max-native")
    try draw(pro, display: .stacked, mode: .fit, colour: .wiiUBlack, backdrop: .light, demo: true, name: "light-held-black-ipad-pro-11-fit")
    // The glass look, and a faint pad (opacity 0.35) on dark and light pictures.
    try draw(pro, display: .stacked, mode: .fit, demo: true, glass: true, name: "glass-held-ipad-pro-11-fit")
    try draw(pro, display: .stacked, mode: .fit, colour: .midnight, backdrop: .light, demo: true, glass: true, name: "light-glass-midnight-ipad-pro-11-fit")
    try draw(pro, display: .stacked, mode: .fit, demo: true, opacity: 0.35, name: "low-opacity-ipad-pro-11-fit")
    try draw(pro, display: .stacked, mode: .fit, backdrop: .light, demo: true, opacity: 0.35, name: "light-low-opacity-ipad-pro-11-fit")
    // Fit's packing where the old fitter floated over the picture.
    let se = TargetDevice.showcaseReview.first { $0.name == "iPhone SE" }!
    try draw(se, display: .stacked, mode: .fit, demo: true, name: "packed-iphone-se-fit-stacked")
}
// Arc in its other states: the calibration (animated guide, live fit, a retry note, the review),
// locked, fine-tuning with a snap guide, swapped hands, and quiet mode with a thumb on it.
do {
    func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }
    func points(_ pivot: CGPoint, _ side: ArcSide, _ radius: CGFloat, from: CGFloat, to: CGFloat, steps: Int) -> [CGPoint] {
        (0...steps).map { i in
            let phi = from + (to - from) * CGFloat(i) / CGFloat(steps)
            let wobble = CGFloat((i * 7919) % 5) - 2
            return CGPoint(x: pivot.x + side.inboardSign * radius * sin(phi) + wobble, y: pivot.y - radius * cos(phi) + wobble)
        }
    }
    func sweep(_ e: PadEngine, id: Int, _ pts: [CGPoint], t0: Double, lift: Bool = true) {
        e.began(id, at: pts[0], time: t0)
        for (i, p) in pts.enumerated().dropFirst() { e.moved(id, to: p, time: t0 + Double(i) * 0.02) }
        if lift { e.ended(id, at: pts.last!, time: t0 + Double(pts.count) * 0.02) }
    }
    func write(_ engine: PadEngine, _ ctx: LayoutContext, _ device: TargetDevice, state: String, title: String) throws {
        let svg = SVGRenderer.svg(size: ctx.size, videoRects: ctx.videoRects, safe: ctx.safeBounds,
                                  title: "Arc - \(device.name) - \(title)", elements: engine.render())
        let file = "arc-state-\(state)-\(slug(device.name)).svg"
        try svg.write(toFile: "\(dir)/\(file)", atomically: true, encoding: .utf8)
        index += "<img src='\(file)' width='480' style='margin:4px'>"
    }
    index += "<h2>Arc states</h2><p>Calibration, locked, fine-tune, swapped hands and quiet mode.</p>"
    let wanted: [(String, TargetDevice.Display)] = [("iPad mini", .stacked), ("iPhone SE", .single),
                                                    ("iPhone SE portrait", .stacked), ("iPhone 16 Pro Max portrait", .stacked)]
    for (name, display) in wanted {
        guard let device = (TargetDevice.all + TargetDevice.portraitVariants).first(where: { $0.name == name }) else { continue }
        let ctx = device.context(display)
        let u = ctx.unit, w = ctx.size.width, h = ctx.size.height
        let rp = CGPoint(x: w - 10, y: h + 40), lp = CGPoint(x: 10, y: h + 40)
        let rad = 6.2 * u
        func fresh() -> (ArcPad, PadEngine) {
            let arc = ArcPad()
            arc.animationTime = 1.1
            return (arc, PadEngine(scheme: arc, output: NullOutput(), context: ctx))
        }
        // 1. The guide, waiting for the left thumb.
        do { let (arc, e) = fresh(); arc.startCalibration(); try write(e, ctx, device, state: "calibration-guide", title: "calibration: animated guide") }
        // 2. A sweep in progress, fitted arc drawn live.
        do {
            let (arc, e) = fresh(); arc.startCalibration()
            sweep(e, id: 1, points(lp, .left, rad, from: 0.3, to: 0.95, steps: 60), t0: 1, lift: false)
            _ = arc
            try write(e, ctx, device, state: "calibration-live", title: "calibration: live fit under the thumb")
        }
        // 3. A sweep that was too short: friendly retry.
        do {
            let (arc, e) = fresh(); arc.startCalibration()
            sweep(e, id: 1, points(lp, .left, rad, from: 0.5, to: 0.62, steps: 20), t0: 1)
            _ = arc
            try write(e, ctx, device, state: "calibration-retry", title: "calibration: try a longer sweep")
        }
        // 4. Review: the finished layout before Done.
        do {
            let (arc, e) = fresh(); arc.startCalibration()
            sweep(e, id: 1, points(lp, .left, rad, from: 0.3, to: 1.25, steps: 90), t0: 1)
            sweep(e, id: 2, points(rp, .right, rad, from: 0.3, to: 1.25, steps: 90), t0: 5)
            _ = arc
            try write(e, ctx, device, state: "calibration-review", title: "calibration: review before Done")
            // 5. Done: locked, with the badge.
            arc.acceptCalibration()
            arc.animationTime = nil
            arc.clock = { 0 }
            try write(e, ctx, device, state: "locked", title: "locked")
        }
        // 6. Fine-tune with a drag settling on a snap guide.
        do {
            let (arc, e) = fresh()
            arc.setFineTuning(true)
            if let s = arc.controls.first(where: { $0.button == .zr })?.shape.center {
                e.began(1, at: s, time: 1)
                e.moved(1, to: CGPoint(x: s.x - 0.1 * u, y: s.y + 0.05 * u), time: 1.1)
            }
            try write(e, ctx, device, state: "fine-tune", title: "fine-tune: handles and snap guides")
        }
        // 7. Hands swapped (left-handed).
        do {
            let (arc, e) = fresh()
            arc.options.swapHands = true
            try write(e, ctx, device, state: "swapped", title: "swapped hands")
        }
        // 8. Quiet mode with a thumb on the right arc (single screen only).
        if display == .single {
            let (arc, e) = fresh()
            if let a = arc.controls.first(where: { $0.button == .b })?.shape.center {
                e.began(1, at: a, time: 1)
                for i in 1...40 { _ = arc.tick(time: 1 + Double(i) / 30) }
            }
            try write(e, ctx, device, state: "quiet-thumb", title: "quiet over the video, brightening under the thumb")
        }
    }
}
// Options worth seeing next to the defaults.
index += "<h2>Zone, large A</h2>"
for device in TargetDevice.all {
    let ctx = device.context(.stacked)
    let engine = PadEngine(scheme: ZonePad(aScale: 1.4), output: NullOutput(), context: ctx)
    let svg = SVGRenderer.svg(size: ctx.size, videoRects: ctx.videoRects, safe: ctx.safeBounds,
                              title: "Zone, large A - \(device.name) - stacked", elements: engine.render())
    let slug = device.name.lowercased().replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
    let file = "zone-large-a-\(slug)-stacked.svg"
    try svg.write(toFile: "\(dir)/\(file)", atomically: true, encoding: .utf8)
    index += "<img src='\(file)' width='480' style='margin:4px'>"
}
try index.write(toFile: "\(dir)/index.html", atomically: true, encoding: .utf8)
print("wrote previews to \(dir)")
