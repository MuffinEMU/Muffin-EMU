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
            let svg = SVGRenderer.svg(size: ctx.size, videoRects: ctx.videoRects, safe: ctx.safeBounds,
                                      title: title, elements: engine.render())
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
              name: String) throws {
        let ctx = device.context(display)
        let pad = ShowcasePad()
        pad.pointsPerInch = device.showcasePointsPerInch
        pad.displayMode = mode
        pad.colourPreset = colour
        let engine = PadEngine(scheme: pad, output: NullOutput(), context: ctx)
        if demo { ShowcaseDemo.press(engine, pad) }
        let scene = pad.scene(pressed: engine.mixer.pressed, sticks: engine.mixer.sticks)
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
