import SwiftUI

/// MuffinEMU's own pad, held upright on an iPhone: the picture runs along the top at full
/// width and the pad gets the space under it (`EmulatorViewOptimized.belowPicture`).
///
/// The landscape layout cannot be squeezed into that space. It is about 17 buttons wide and
/// the container is about 8.5, so the two halves would sit on top of each other. Portrait
/// keeps each half as it is (d-pad with L / ZL, face buttons with R / ZR) and changes only
/// where things sit around it:
///
///   - each half is pinned to its own bottom corner, which is where a thumb rests,
///   - + and - move from beside the d-pad / face buttons to under them, which is what takes
///     the halves from 4.5 buttons wide to 3.5 and lets both fit at a thumb-sized button,
///   - an analog stick, if joystick mode is on, goes above its half instead of inboard of it,
///   - comfort controls, the stick-spacing slider and per-button moves do not apply (they
///     are measured in the landscape layout), and moving a half is saved under its own keys,
///     so a layout dragged around in landscape is not disturbed by one made here.
extension ControllerGeometry {
    enum Portrait {
        /// Half the d-pad cross plus its measured gap, in button widths: the widest the
        /// d-pad half is once + and - have moved out from beside it.
        private static let halfWidth: CGFloat = 3.48
        private static let edgeMargin: CGFloat = 0.35
        /// Clear space between the two halves, in button widths.
        private static let gap: CGFloat = 0.9

        /// + and - sit this far below their half's centre dot (its bottom button's edge is at
        /// 1.655), so they clear it by about half a button.
        static let systemY: CGFloat = 2.6
        /// Where a half's centre dot sits, in button widths: from the near edge, and up from the
        /// bottom of the pad's area. The bottom is + / - 's lower edge plus a small margin; the
        /// area is already inside the home indicator's safe area.
        static let centreFromNearEdge: CGFloat = halfWidth / 2 + edgeMargin
        static let centreFromBottom: CGFloat = systemY + 0.387 + 0.3
        /// A stick above its half: clears the shoulder row (top edge at -3.26) by a quarter
        /// button, centred on the half.
        static let stickAnchorOffset = CGPoint(x: 0, y: -(3.261 + 0.25 + stickBaseDiameter / 2))

        /// Height, in button widths, from the top of the tallest control to the bottom margin.
        private static func heightUnits(joystick: Bool) -> CGFloat {
            let above = joystick ? -stickAnchorOffset.y + stickBaseDiameter / 2 : 3.261
            return above + centreFromBottom + 0.2
        }

        /// The face-button diameter, in points, at which both halves fit across `size`, and
        /// the stack fits down it. The size slider can only make this smaller: there is no
        /// room to grow into.
        static func diameter(in size: CGSize, joystick: Bool) -> CGFloat {
            let widthUnits = 2 * halfWidth + 2 * edgeMargin + gap
            return min(size.width / widthUnits, size.height / heightUnits(joystick: joystick), 72)
        }

        /// How tall an area the pad needs for buttons of at least 36 points, so that a
        /// second screen stacked above it cannot squeeze the controls to nothing.
        static func minimumHeight(joystick: Bool) -> CGFloat {
            heightUnits(joystick: joystick) * 36
        }

        /// The same half with + and - moved under it.
        static func cluster(_ controls: [Control]) -> [Control] {
            controls.map { control in
                guard control.id == "minus" || control.id == "plus" else { return control }
                return Control(id: control.id, glyph: control.glyph, offset: CGPoint(x: 0, y: systemY),
                               shape: control.shape, style: control.style)
            }
        }
    }
}
