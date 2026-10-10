import SwiftUI

/// Size and place of the left and right halves of MuffinEMU's pad. Kept apart per
/// orientation: the phone held upright has its own values.
struct ClusterPlacementSettings: View {
    @AppStorage private var leftScale: Double
    @AppStorage private var rightScale: Double
    @AppStorage private var leftInward: Double
    @AppStorage private var rightInward: Double
    @AppStorage private var leftUp: Double
    @AppStorage private var rightUp: Double

    init(upright: Bool) {
        func key(_ k: String) -> String { upright ? ControllerLayoutSettings.portraitKey(k) : k }
        _leftScale = AppStorage(wrappedValue: 1.0, key(ControllerLayoutSettings.leftScaleKey))
        _rightScale = AppStorage(wrappedValue: 1.0, key(ControllerLayoutSettings.rightScaleKey))
        _leftInward = AppStorage(wrappedValue: 0.0, key(ControllerLayoutSettings.leftInwardKey))
        _rightInward = AppStorage(wrappedValue: 0.0, key(ControllerLayoutSettings.rightInwardKey))
        _leftUp = AppStorage(wrappedValue: 0.0, key(ControllerLayoutSettings.leftUpKey))
        _rightUp = AppStorage(wrappedValue: 0.0, key(ControllerLayoutSettings.rightUpKey))
    }

    var body: some View {
        Form {
            half("Left buttons", scale: $leftScale, inward: $leftInward, up: $leftUp)
            half("Right buttons", scale: $rightScale, inward: $rightInward, up: $rightUp)
            Section {
                Text("Applies to MuffinEMU's own pad, and is saved separately for each way you hold the device. Drag buttons in the layout editor for finer changes.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Left and right buttons")
    }

    private func half(_ title: String, scale: Binding<Double>, inward: Binding<Double>, up: Binding<Double>) -> some View {
        Section(header: Text(title)) {
            row("Size", scale, ControllerLayoutSettings.minClusterScale...ControllerLayoutSettings.maxClusterScale, 0.05)
            row("Toward the middle", inward, ControllerLayoutSettings.minClusterInward...ControllerLayoutSettings.maxClusterInward, 0.1)
            row("Up", up, ControllerLayoutSettings.minClusterUp...ControllerLayoutSettings.maxClusterUp, 0.1)
        }
    }

    private func row(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }
}
