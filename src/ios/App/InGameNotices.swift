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
