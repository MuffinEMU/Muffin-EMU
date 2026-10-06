import SwiftUI
import UIKit

/// The core's performance readout and notifications, drawn natively at full screen
/// resolution.
///
/// The core's own ImGui overlay is drawn into the game's render surface, which on iOS has a
/// reduced backing scale (RenderScale.swift), so the compositor stretches its text and it
/// looks soft. While this view is active it asks the core to stop drawing that overlay
/// (cemu_bridge_set_native_overlay) and draws the same lines itself. Inactive means the old
/// ImGui overlay, unchanged. Position, colour and scale are read from the core each poll, so
/// changing them in Settings during a game still takes effect.

// MARK: - Model

/// One text block (the stats readout or a single notification) and how to draw it.
private struct NativeOverlayCard {
    let lines: [String]
    let color: Int
    let scale: Int
}

/// What the core said to draw, plus how: a snapshot of cemu_bridge_native_overlay_text() and
/// the position/colour/scale settings it was built under.
private struct NativeOverlaySnapshot: Equatable {
    var statsPosition: ScreenPosition = .disabled
    var statsColor: Int = OverlaySettings.defaultTextColor
    var statsScale: Int = OverlaySettings.defaultTextScale
    var notificationPosition: ScreenPosition = .disabled
    var notificationColor: Int = OverlaySettings.defaultTextColor
    var notificationScale: Int = OverlaySettings.defaultTextScale
    var stats: [String] = []
    var notifications: [[String]] = []

    /// Asks the core for the current text. Polling consumes the core's one-shot shader and
    /// pipeline counters, so this is only called from the one polling view.
    static func read() -> NativeOverlaySnapshot {
        var snapshot = NativeOverlaySnapshot()
        snapshot.statsPosition = ScreenPosition(rawValue: Int(cemu_bridge_overlay_position())) ?? .disabled
        snapshot.statsColor = Int(cemu_bridge_overlay_text_color())
        snapshot.statsScale = Int(cemu_bridge_overlay_text_scale())
        snapshot.notificationPosition = ScreenPosition(rawValue: Int(cemu_bridge_notification_position())) ?? .disabled
        snapshot.notificationColor = Int(cemu_bridge_notification_text_color())
        snapshot.notificationScale = Int(cemu_bridge_notification_text_scale())
        guard snapshot.statsPosition != .disabled || snapshot.notificationPosition != .disabled else {
            return snapshot
        }
        snapshot.parse(String(cString: cemu_bridge_native_overlay_text()))
        return snapshot
    }

    /// The text is the stats lines (separated by newlines), then each notification after a
    /// 0x1E separator; a notification's own lines are separated by newlines.
    private mutating func parse(_ raw: String) {
        let parts = raw.split(separator: "\u{1E}", omittingEmptySubsequences: false)
        guard let first = parts.first else { return }
        stats = Self.lines(of: first)
        notifications = parts.dropFirst().map { Self.lines(of: $0) }.filter { !$0.isEmpty }
    }

    private static func lines(of block: Substring) -> [String] {
        block.split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }
    }
}

// MARK: - Placement

private extension ScreenPosition {
    var alignment: Alignment {
        switch self {
        case .disabled, .topLeft: return .topLeading
        case .topCenter: return .top
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomCenter: return .bottom
        case .bottomRight: return .bottomTrailing
        }
    }

    /// Bottom positions stack upward: the first block sits at the edge, later ones above it.
    var stacksUpward: Bool {
        switch self {
        case .bottomLeft, .bottomCenter, .bottomRight: return true
        default: return false
        }
    }
}

private extension Color {
    /// A packed 0xAARRGGBB value, the format the Text Color setting edits.
    init(packedARGB packed: Int) {
        let value = UInt32(truncatingIfNeeded: packed)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: Double((value >> 24) & 0xFF) / 255)
    }
}

// MARK: - Views

/// One translucent card of text. Matches the core's own look: 14pt base size times the text
/// scale, black at 65% opacity behind it.
private struct NativeOverlayCardView: View {
    let lines: [String]
    let color: Int
    let scale: Int

    private var font: Font {
        .system(size: 14 * CGFloat(scale) / 100).monospacedDigit()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines.indices, id: \.self) { index in
                Text(lines[index])
                    .font(font)
                    .foregroundColor(Color(packedARGB: color))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.65))
        .cornerRadius(6)
    }
}

/// A stack of cards pinned to one corner or edge, 10pt in from it, and never closer than the
/// screen's own safe area (the notch side and rounded corners of an iPhone) or the top bar.
private struct NativeOverlayStackView: View {
    let position: ScreenPosition
    let cards: [NativeOverlayCard]
    let safeArea: UIEdgeInsets
    /// Bottom edge of the in-game top bar. The overlay sits beneath the bar, so a top
    /// position would otherwise be drawn behind Back and the button row.
    let topInset: CGFloat

    private static let margin: CGFloat = 10

    private var edgeInsets: EdgeInsets {
        let margin = Self.margin
        return EdgeInsets(
            top: max(margin, topInset > 0 ? topInset + 6 : safeArea.top + margin),
            leading: max(margin, safeArea.left),
            bottom: max(margin, safeArea.bottom),
            trailing: max(margin, safeArea.right))
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch position {
        case .topCenter, .bottomCenter: return .center
        case .topRight, .bottomRight: return .trailing
        default: return .leading
        }
    }

    private var ordered: [NativeOverlayCard] {
        position.stacksUpward ? Array(cards.reversed()) : cards
    }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 10) {
            ForEach(ordered.indices, id: \.self) { index in
                NativeOverlayCardView(lines: ordered[index].lines, color: ordered[index].color, scale: ordered[index].scale)
            }
        }
        .padding(edgeInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
    }
}

/// Polls the core at about 4 Hz and draws what it returns. Only in the view tree while the
/// native overlay is active, so nothing polls otherwise.
private struct NativeCoreOverlayLayer: View {
    let topInset: CGFloat

    // Not .read(): a @State default is evaluated on every init of this struct, and reading
    // consumes the core's one-shot counters. The first real read is the first timer tick.
    @State private var snapshot = NativeOverlaySnapshot()

    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var statsCards: [NativeOverlayCard] {
        guard snapshot.statsPosition != .disabled, !snapshot.stats.isEmpty else { return [] }
        return [NativeOverlayCard(lines: snapshot.stats, color: snapshot.statsColor, scale: snapshot.statsScale)]
    }

    private var notificationCards: [NativeOverlayCard] {
        guard snapshot.notificationPosition != .disabled else { return [] }
        return snapshot.notifications.map {
            NativeOverlayCard(lines: $0, color: snapshot.notificationColor, scale: snapshot.notificationScale)
        }
    }

    @ViewBuilder
    private func stacks(safeArea: UIEdgeInsets) -> some View {
        ZStack {
            if snapshot.statsPosition == snapshot.notificationPosition {
                // Same corner: one stack, stats first, like the core.
                NativeOverlayStackView(position: snapshot.statsPosition, cards: statsCards + notificationCards,
                                       safeArea: safeArea, topInset: topInset)
            } else {
                NativeOverlayStackView(position: snapshot.statsPosition, cards: statsCards,
                                       safeArea: safeArea, topInset: topInset)
                NativeOverlayStackView(position: snapshot.notificationPosition, cards: notificationCards,
                                       safeArea: safeArea, topInset: topInset)
            }
        }
    }

    var body: some View {
        // The GeometryReader is only here so the safe area is read again whenever the
        // window changes size (rotation, Split View, Stage Manager). The game's view tree
        // ignores the safe area, so SwiftUI cannot supply it here.
        GeometryReader { _ in
            stacks(safeArea: WindowSafeArea.insets())
        }
        .accessibilityHidden(true)
        .onReceive(timer) { _ in
            let latest = NativeOverlaySnapshot.read()
            if latest != snapshot { snapshot = latest }
        }
    }
}

/// Drop-in layer for the emulator screen. Does not affect layout and never takes touches.
/// `active` false hands the overlay back to the core's ImGui drawing. `topInset` is the bottom
/// edge of the in-game top bar, so top positions sit below it.
struct NativeCoreOverlayView: View {
    let active: Bool
    var topInset: CGFloat = 0

    var body: some View {
        // A ZStack, so onAppear/onDisappear belong to this view and not to whichever branch
        // of `content` is showing: switching branches must not briefly hand the overlay back
        // to the core's own drawing and then take it again.
        ZStack { content }
            .allowsHitTesting(false)
            .onAppear { cemu_bridge_set_native_overlay(active) }
            .onChange(of: active) { newValue in
                cemu_bridge_set_native_overlay(newValue)
            }
            .onDisappear { cemu_bridge_set_native_overlay(false) }
    }

    @ViewBuilder
    private var content: some View {
        if active {
            NativeCoreOverlayLayer(topInset: topInset)
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

/// The window's real safe-area insets. The in-game view tree ignores the safe area (the game
/// fills the whole screen), so SwiftUI reports none inside it; the window still knows where
/// an iPhone's notch side and rounded corners are. Zero on an iPad filling the screen.
enum WindowSafeArea {
    static func insets() -> UIEdgeInsets {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return (windows.first(where: { $0.isKeyWindow }) ?? windows.first)?.safeAreaInsets ?? .zero
    }

    /// Padding for something pinned near an edge: `minimum` everywhere, more where the window
    /// has a safe area. Vertical edges keep `minimum` (the status bar is hidden in game).
    static func padding(minimum: CGFloat) -> EdgeInsets {
        let safe = insets()
        return EdgeInsets(top: minimum, leading: max(minimum, safe.left),
                          bottom: minimum, trailing: max(minimum, safe.right))
    }
}
