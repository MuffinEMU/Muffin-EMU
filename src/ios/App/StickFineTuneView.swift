// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import TouchLabCore

/// "Stick fine-tuning": each stick's deadzones, curve, sensitivity and inversion, with a test
/// circle that shows what the game would be sent. One page for Settings and for the sheet that
/// opens over the game from the move-controls panels. The numbers are stored per stick under the
/// shared stick keys (`SharedStick.key`), so MuffinEMU's pad, the new pad and every TouchLab style
/// read the same ones.
struct StickFineTuneView: View {
    /// True in the sheet over the game, which needs its own way out.
    var showsDone = false

    @Environment(\.presentationMode) private var presentation
    @State private var left = true

    var body: some View {
        Form {
            Section {
                Picker("Stick", selection: $left) {
                    Text("Left stick").tag(true)
                    Text("Right stick").tag(false)
                }
                .pickerStyle(.segmented)
            }
            // Rebuilt per stick: its settings are @AppStorage on that stick's keys.
            ForEach([left], id: \.self) { StickFineTuneEditor(left: $0) }
        }
        .navigationTitle("Stick fine-tuning")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if showsDone {
                    Button("Done") { presentation.wrappedValue.dismiss() }
                }
            }
        }
    }
}

private struct StickFineTuneEditor: View {
    let left: Bool

    @AppStorage(ControllerLayoutSettings.stickGateKey)
    private var gateRaw = ControllerLayoutSettings.defaultStickGateRaw
    @AppStorage(ControllerLayoutSettings.deadzoneKey) private var sharedDeadzone = SharedStick.unset
    @AppStorage(ControllerLayoutSettings.stickCurveKey) private var sharedCurve = SharedStick.unset
    @AppStorage private var deadzoneOwn: Double
    @AppStorage private var curveOwn: Double
    @AppStorage private var outer: Double
    @AppStorage private var anti: Double
    @AppStorage private var sensX: Double
    @AppStorage private var sensY: Double
    @AppStorage private var invertX: Bool
    @AppStorage private var invertY: Bool
    @AppStorage private var calibrationRaw: String

    init(left: Bool) {
        self.left = left
        _deadzoneOwn = AppStorage(wrappedValue: SharedStick.unset, SharedStick.key(.innerDeadzone, left: left))
        _curveOwn = AppStorage(wrappedValue: SharedStick.unset, SharedStick.key(.curve, left: left))
        _outer = AppStorage(wrappedValue: 0, SharedStick.key(.outerDeadzone, left: left))
        _anti = AppStorage(wrappedValue: 0, SharedStick.key(.antiDeadzone, left: left))
        _sensX = AppStorage(wrappedValue: 1, SharedStick.key(.sensitivityX, left: left))
        _sensY = AppStorage(wrappedValue: 1, SharedStick.key(.sensitivityY, left: left))
        _invertX = AppStorage(wrappedValue: false, SharedStick.key(.invertX, left: left))
        _invertY = AppStorage(wrappedValue: false, SharedStick.key(.invertY, left: left))
        _calibrationRaw = AppStorage(wrappedValue: "", SharedStick.calibrationKey(left: left))
    }

    /// A stick with no value of its own shows the shared one, which is what it is using.
    private var deadzone: Binding<Double> {
        Binding(get: { deadzoneOwn >= 0 ? deadzoneOwn : (sharedDeadzone >= 0 ? sharedDeadzone : ControllerLayoutSettings.defaultDeadzone) },
                set: { deadzoneOwn = $0 })
    }

    private var curve: Binding<Double> {
        Binding(get: { curveOwn >= 0 ? curveOwn : (sharedCurve >= 0 ? sharedCurve : ControllerLayoutSettings.defaultStickCurve) },
                set: { curveOwn = $0 })
    }

    private var feel: StickFeel {
        StickFeel(innerDeadzone: deadzone.wrappedValue, curve: curve.wrappedValue, outerDeadzone: outer,
                  antiDeadzone: anti, sensitivityX: sensX, sensitivityY: sensY,
                  invertX: invertX, invertY: invertY)
    }

    var body: some View {
        Section {
            StickTestPad(feel: feel, gateRaw: gateRaw, calibrationRaw: calibrationRaw)
                .frame(maxWidth: .infinity)
        } header: {
            Text("Test")
        } footer: {
            Text("Drag the circle. The grey dot is where your thumb is; the blue dot is what the game is sent, after everything below and your calibration. Nothing here reaches the game.")
        }

        Section {
            percentRow("Inner deadzone", value: deadzone, range: StickTuning.deadzoneRange,
                       caption: "How far you can move before the game notices. Turn it up if a resting thumb makes the game drift.")
            percentRow("Outer deadzone", value: $outer, range: StickFeel.outerRange,
                       caption: "How far short of the edge the stick already counts as fully pushed. Turn it up if you can't quite reach full speed.")
            percentRow("Anti-deadzone", value: $anti, range: StickFeel.antiRange,
                       caption: "The least the game is sent once you are past the inner deadzone. For games that have a deadzone of their own and ignore small pushes.")
            valueRow("Fine control", readout: curve.wrappedValue <= StickTuning.curveRange.lowerBound + 0.005
                        ? "linear" : String(format: "%.1fx", curve.wrappedValue),
                     value: curve, range: StickTuning.curveRange,
                     caption: "Makes small movements gentler. At linear, halfway is half speed; higher values make halfway slower.")
        } header: {
            Text("Response")
        } footer: {
            Text("Deadzone and fine control here are for this stick only. The sliders in the stick settings set both sticks.")
        }

        Section {
            percentRow("Horizontal sensitivity", value: $sensX, range: StickFeel.sensitivityRange,
                       caption: nil)
            percentRow("Vertical sensitivity", value: $sensY, range: StickFeel.sensitivityRange,
                       caption: "Below 100% limits how far the stick can turn the game on that axis. Above 100% reaches full sooner.")
            Toggle("Invert horizontal", isOn: $invertX)
                .tint(MuffinTheme.pixelBlue)
            Toggle("Invert vertical", isOn: $invertY)
                .tint(MuffinTheme.pixelBlue)
        } header: {
            Text("Axes")
        }

        Section {
            NavigationLink {
                StickCalibrationView()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Calibrate sticks", systemImage: "scope")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(calibrationRaw.isEmpty ? "Not calibrated." : "Calibrated.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            Button(role: .destructive) {
                SharedStick.reset(left: left)
            } label: {
                DestructiveSettingsLabel(title: left ? "Reset left stick" : "Reset right stick",
                                         systemImage: "arrow.uturn.backward")
            }
        } footer: {
            Text("Resetting puts this stick's fine-tuning back to the shared deadzone and curve, with no other changes. Calibration is kept.")
        }
    }

    private func percentRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                            caption: String?) -> some View {
        let v = value.wrappedValue
        return valueRow(title, readout: v <= 0.0005 && range.lowerBound == 0 ? "off" : "\(Int((v * 100).rounded()))%",
                        value: value, range: range, caption: caption)
    }

    private func valueRow(_ title: String, readout: String, value: Binding<Double>, range: ClosedRange<Double>,
                          caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(readout)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(readout)
            if let caption {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A circle to drag a thumb in, with the stick value the game would be sent. It calls
/// `SharedStick.output`, the function MuffinEMU's pad and the new pad use at every touch, with the
/// same gate, calibration and travel maths.
private struct StickTestPad: View {
    let feel: StickFeel
    let gateRaw: String
    let calibrationRaw: String

    private static let diameter: CGFloat = 170

    /// The thumb, in points from the centre (+y down), as the pads see a finger.
    @State private var thumb: CGPoint = .zero
    @State private var touching = false

    private var gate: ControllerGeometry.StickGate {
        ControllerGeometry.StickGate(rawValue: gateRaw) ?? ControllerLayoutSettings.defaultStickGate
    }

    private var travel: CGFloat { ControllerGeometry.stickTravel(ringDiameter: Self.diameter) }

    private var output: CGPoint {
        SharedStick.output(dx: thumb.x, dy: thumb.y, travel: travel, feel: feel,
                           gateRaw: gateRaw, calibrationRaw: calibrationRaw)
    }

    var body: some View {
        let f = feel.clamped
        let out = output
        VStack(spacing: 10) {
            ZStack {
                StickGateShape(gate: gate)
                    .fill(Color(white: 0.5).opacity(0.18))
                    .overlay(StickGateShape(gate: gate).strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5))
                // Where the output starts and where it reaches full.
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: travel * 2 * CGFloat(f.innerDeadzone), height: travel * 2 * CGFloat(f.innerDeadzone))
                if f.outerDeadzone > 0 {
                    Circle()
                        .strokeBorder(MuffinTheme.pixelBlue.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: travel * 2 * CGFloat(1 - f.outerDeadzone), height: travel * 2 * CGFloat(1 - f.outerDeadzone))
                }
                // What the game is sent, at the same scale as the thumb: full output sits on the rim.
                Circle()
                    .fill(MuffinTheme.pixelBlue)
                    .frame(width: 14, height: 14)
                    .offset(x: CGFloat(out.x) * travel, y: -CGFloat(out.y) * travel)
                Circle()
                    .fill(Color.gray.opacity(touching ? 0.9 : 0.5))
                    .frame(width: 26, height: 26)
                    .offset(x: thumb.x, y: thumb.y)
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .padding(14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        touching = true
                        let c = CGPoint(x: value.location.x - (Self.diameter / 2 + 14),
                                        y: value.location.y - (Self.diameter / 2 + 14))
                        // Drawn no farther than the gate plus the little overtravel the pads allow.
                        let len = (c.x * c.x + c.y * c.y).squareRoot()
                        let reach = StickMath.overtravel(travel) + travel * gate.radiusFraction(atAngle: atan2(c.y, c.x))
                        thumb = len > reach && len > 0 ? CGPoint(x: c.x * reach / len, y: c.y * reach / len) : c
                    }
                    .onEnded { _ in
                        touching = false
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) { thumb = .zero }
                    }
            )
            .accessibilityLabel("Stick test area")

            VStack(spacing: 2) {
                Text("Thumb  x \(Self.format(thumb.x / travel))  y \(Self.format(-thumb.y / travel))")
                Text("Game   x \(Self.format(CGFloat(out.x)))  y \(Self.format(CGFloat(out.y)))")
            }
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(.secondary)
        }
    }

    private static func format(_ v: CGFloat) -> String {
        String(format: "%+.2f", Double(v))
    }
}

/// How the move-controls panels open the page over the game. The card holds the sheet (outside its
/// always-dark rows, so the page uses the normal colours) and the row asks it to open.
struct OpenStickFineTune {
    var action: () -> Void = {}
}

private struct OpenStickFineTuneKey: EnvironmentKey {
    static let defaultValue = OpenStickFineTune()
}

extension EnvironmentValues {
    var openStickFineTune: OpenStickFineTune {
        get { self[OpenStickFineTuneKey.self] }
        set { self[OpenStickFineTuneKey.self] = newValue }
    }
}

/// "Fine-tune sticks", for a move-controls panel with sticks on it.
struct FineTuneSticksRow: View {
    @Environment(\.openStickFineTune) private var open

    var body: some View {
        Button(action: open.action) {
            Label("Fine-tune sticks", systemImage: "dial.medium")
        }
        .buttonStyle(MuffinSecondaryButtonStyle())
    }
}
