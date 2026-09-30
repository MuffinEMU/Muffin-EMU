#if canImport(UIKit)
import SwiftUI
import TouchLabCore

/// Which Wii U screen a view is showing.
public enum TouchLabScreen: Hashable, Sendable {
    case tv, gamepad
}

/// Collects the on-screen frames (window coordinates) of the views showing the TV and
/// GamePad images, wherever they are in the host's hierarchy. Tag each screen view with
/// `.touchLabScreenFrame(_:)`, read the result with `.onPreferenceChange`, and hand it to
/// `TouchPad(..., rectSpace: .window)`.
public struct TouchLabScreenFramesKey: PreferenceKey {
    public static var defaultValue: [TouchLabScreen: CGRect] = [:]
    public static func reduce(value: inout [TouchLabScreen: CGRect], nextValue: () -> [TouchLabScreen: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

public extension View {
    /// Reports this view's frame as the given Wii U screen's frame.
    func touchLabScreenFrame(_ screen: TouchLabScreen) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: TouchLabScreenFramesKey.self, value: [screen: proxy.frame(in: .global)])
            }
        )
    }
}

/// Turns reported screen frames into what `TouchPad` wants.
public struct TouchLabScreens: Equatable {
    public var frames: [TouchLabScreen: CGRect]
    /// True when the renderer letterboxes the 16:9 image inside its view; false when the
    /// image fills the view. Only affects `videoRects` (what Frame avoids covering).
    public var imageIsAspectFit: Bool

    public init(frames: [TouchLabScreen: CGRect], imageIsAspectFit: Bool = true) {
        self.frames = frames
        self.imageIsAspectFit = imageIsAspectFit
    }

    /// The picture areas, for Frame's "never cover the game".
    public var videoRects: [CGRect] {
        [frames[.tv], frames[.gamepad]].compactMap { $0 }.filter { $0.width > 1 && $0.height > 1 }.map {
            imageIsAspectFit ? PadScreenGeometry.aspectFit(16.0 / 9.0, in: $0) : $0
        }
    }

    /// The GamePad VIEW's full frame (not the fitted image): MuffinEMU's own touch path
    /// maps a touch as a position inside that view's size, so this keeps both identical.
    public var touchscreenRect: CGRect? {
        frames[.gamepad].flatMap { $0.width > 1 && $0.height > 1 ? $0 : nil }
    }
}
#endif
