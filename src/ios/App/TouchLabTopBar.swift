import SwiftUI

/// Reports the bottom edge of the in-game top bar (Back, pause, the button row) in window
/// coordinates, so the TouchLab control styles can keep every control below it.
///
/// Measured rather than hard-coded: the bar's height changes with Dynamic Type, with the
/// skin-selector drop-down, and between iPhone and iPad. Written only when the layout
/// changes, never from the input path.
struct TopBarBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func reportTopBarBottom() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: TopBarBottomKey.self, value: proxy.frame(in: .global).maxY)
            }
        )
    }
}
