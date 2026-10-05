import SwiftUI

/// Back, while a game is still starting.
///
/// The "Starting..." cover and the launch intro are drawn over the top bar, so while a game
/// boots there was no way out of a launch that never finishes. This sits above both. It does
/// the same thing the bar's Back button does during a boot: stops the launch without asking,
/// since nothing is running yet that could be lost.
struct BootBackButton: View {
    let action: () -> Void

    var body: some View {
        VStack {
            HStack {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                }
                .buttonStyle(MuffinSecondaryButtonStyle())
                .accessibilityHint("Stops starting the game and returns to your games.")
                Spacer()
            }
            Spacer()
        }
        .padding(WindowSafeArea.padding(minimum: 12))
    }
}

/// Says so when the device gets hot during a game.
///
/// iOS slows the game down when the device overheats, and MuffinEMU's own cool-down (Settings,
/// CPU) lowers the picture quality at the same time. Both happen without a word, which looks
/// like the game or the app has broken. This puts one line on screen (the same banner a
/// launch notice uses) when the device gets hot, and another when it has cooled down.
struct HeatNoticeModifier: ViewModifier {
    let show: (String) -> Void
    @State private var wasHot = false

    private static var isHot: Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }

    func body(content: Content) -> some View {
        content
            .onAppear { wasHot = Self.isHot }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                let hot = Self.isHot
                defer { wasHot = hot }
                if hot && !wasHot {
                    show(Self.hotMessage)
                } else if !hot && wasHot {
                    show("The device has cooled down. The game should run at full speed again.")
                }
            }
    }

    // ThermalMonitor is main-actor isolated; the closure above runs inside body, which is too.
    @MainActor private static var hotMessage: String {
        let auto = UserDefaults.standard.object(forKey: ThermalMonitor.autoThrottleKey) as? Bool
            ?? ThermalMonitor.autoThrottleDefault
        let start = "The device is hot, so iOS is slowing the game down."
        return auto
            ? "\(start) MuffinEMU is easing the load until it cools down."
            : "\(start) Turn on Cool down automatically in Settings, CPU, or lower Resolution in Settings, Graphics."
    }
}
