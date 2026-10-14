// MuffinEMU TouchLab — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: GPL-3.0-only
// This notice must be kept in any copy or modified version (GPL-3.0 §4 and §5).

import CoreGraphics
import Foundation
import TouchLabCore

// Showcase Fit: a pad packed into a thin margin must still read as the GamePad, and no control
// is ever outside the safe area, whatever the device, mode, preset, scale or picture.

func runShowcaseFitChecks() {
    var cases: [(String, TargetDevice, LayoutContext)] = []
    for d in TargetDevice.showcaseReview + TargetDevice.showcaseExtras {
        for display in TargetDevice.Display.allCases { cases.append((d.name + " " + display.rawValue, d, d.context(display))) }
        if d.size.width > d.size.height, d.size.height >= 700 { cases.append((d.name + " 4:3", d, d.letterboxed43)) }
    }
    var n = 0
    for (label, d, base) in cases {
        for preset in ShowcaseLayoutPreset.allCases {
            for scale in [CGFloat(0.8), 1, 1.2] {
                for mode in ShowcaseLayout.DisplayMode.allCases {
                    var ctx = base; ctx.scale = scale
                    let pad = ShowcasePad(); pad.pointsPerInch = d.showcasePointsPerInch
                    pad.layoutPreset = preset; pad.displayMode = mode
                    pad.layout(ctx)
                    n += 1
                    let where_ = "Showcase \(label) \(mode.rawValue) \(preset.rawValue) x\(scale)"
                    let screen = CGRect(origin: .zero, size: ctx.size)
                    for c in pad.controls where !c.isZone {
                        let b = c.shape.boundingBox
                        check(ctx.safeBounds.insetBy(dx: -0.5, dy: -0.5).contains(b) && screen.insetBy(dx: -0.5, dy: -0.5).contains(b),
                              "\(where_): \(c.label) \(b) is outside the safe area \(ctx.safeBounds)")
                    }
                }
            }
        }
    }
    print("showcase: \(n) safe-area cases")

    // 12.9-inch iPad, one 16:9 picture or a 4:3 picture under a top bar: GamePad arrangement kept.
    let d = TargetDevice.showcaseExtras[0]
    for (label, ctx) in [("single", d.context(.single)), ("4:3", d.letterboxed43)] {
        let pad = ShowcasePad(); pad.pointsPerInch = d.showcasePointsPerInch
        pad.layout(ctx)
        func c(_ b: PadButton) -> CGPoint { pad.controls.first { $0.button == b }!.shape.center }
        func stick(_ s: PadStick) -> CGPoint {
            pad.controls.first { if case .stick(let k, _, _) = $0.kind { return k == s }; return false }!.shape.center
        }
        let dpad = pad.controls.first { if case .dpad = $0.kind { return true }; return false }!.shape.center
        let u = pad.unitPoints
        let w = "12.9-inch showcase \(label)"
        check(pad.lifeSizeFraction >= 0.7, "\(w): buttons at \(pad.lifeSizeFraction) of life size")
        check(dpad.y - stick(.left).y >= 1.6 * u && c(.a).y - stick(.right).y >= 1.6 * u, "\(w): each stick sits above its cluster")
        check(stick(.left).y - c(.l).y >= 0.8 * u && stick(.left).y - c(.zl).y >= 0.8 * u
              && stick(.right).y - c(.r).y >= 0.8 * u && stick(.right).y - c(.zr).y >= 0.8 * u,
              "\(w): shoulders sit above their sticks")
        check(c(.b).y - c(.x).y >= 1.5 * u, "\(w): the face diamond keeps its shape")
        check(c(.zl).x < ctx.size.width / 2 && c(.zr).x > ctx.size.width / 2, "\(w): left controls left, right controls right")
        check(c(.plus).x < c(.minus).x && abs(c(.plus).y - c(.minus).y) < 1, "\(w): + left of -")
    }
}
