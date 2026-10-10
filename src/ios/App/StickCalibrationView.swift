// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import TouchLabCore

/// "Calibrate sticks": for each stick, rest the thumb in the middle for a moment, push to
/// every edge, then let go. That records where the thumb rests, how much it wobbles there and
/// how far it comfortably goes. The result is saved under the shared stick keys, so it applies
/// to MuffinEMU's pad, the new pad (preview) and every TouchLab style.
struct StickCalibrationView: View {
    @Environment(\.presentationMode) private var presentation

    @AppStorage(ControllerLayoutSettings.stickGateKey)
    private var gateRaw = ControllerLayoutSettings.defaultStickGateRaw
    @AppStorage(ControllerLayoutSettings.scaleKey)
    private var padScale = ControllerLayoutSettings.defaultScale

    private enum Step: Equatable { case left, right, done }
    @State private var step: Step = .left
    @State private var session = StickCalibrationSession(travel: 60)
    @State private var offset: CGPoint = .zero
    @State private var touching = false
    @State private var notice: String?
    @State private var saved: [Bool: StickCalibration] = [:]
    private let ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var gate: StickTuning.Gate { StickTuning.Gate(rawValue: gateRaw) ?? .octagon }
    private var isLeft: Bool { step == .left }

    var body: some View {
        GeometryReader { proxy in
            let unit = ControllerGeometry.automaticDiameter(in: proxy.size) * CGFloat(padScale)
            let base = ControllerGeometry.stickBaseDiameter * unit
            let travel = ControllerGeometry.stickTravel(ringDiameter: base)
            VStack(spacing: 18) {
                Text(step == .done ? "Sticks calibrated" : (isLeft ? "Left stick" : "Right stick"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(prompt)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(minHeight: 44)
                if step != .done {
                    ring(base: base, travel: travel)
                } else {
                    summary
                }
                if let notice {
                    Text(notice).font(.system(size: 13)).foregroundColor(.secondary)
                }
                HStack(spacing: 16) {
                    if step == .left {
                        Button("Skip left") { advance() }
                    } else if step == .right {
                        Button("Skip right") { advance() }
                    }
                    Button(step == .done ? "Done" : "Cancel") { presentation.wrappedValue.dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { restart() }
        .onReceive(ticker) { _ in
            // A thumb that is held still sends no events; time still has to pass for the rest.
            if touching { session.move(to: offset, time: ProcessInfo.processInfo.systemUptime) }
        }
    }

    private var prompt: String {
        if step == .done { return "Every control style now uses your calibration. Run it again any time, or reset it from the stick settings." }
        switch session.phase {
        case .waiting: return "Put your thumb on the stick and hold it still for a moment."
        case .rest: return "Hold still..."
        case .sweep: return "Now push to every edge, all the way around. Let go when the ring is lit."
        case .finished: return ""
        }
    }

    private func ring(base: CGFloat, travel: CGFloat) -> some View {
        let knob = ControllerGeometry.stickKnobDiameter * base / ControllerGeometry.stickBaseDiameter
        return ZStack {
            Circle().fill(Color(white: 0.85).opacity(0.55))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 2))
            // The eight directions, lit as they are reached.
            ForEach(0..<StickCalibrationSession.sectorCount, id: \.self) { i in
                let lit = session.coveredSectors.contains(i)
                Circle()
                    .trim(from: 0, to: 0.11)
                    .stroke(lit ? MuffinTheme.pixelBlue : Color.black.opacity(0.18), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-Double(i) * 45 - 0.11 * 180))
                    .padding(3)
            }
            Circle().fill(MuffinTheme.pixelBlue.opacity(touching ? 1 : 0.7))
                .frame(width: knob, height: knob)
                .offset(x: offset.x, y: offset.y)
        }
        .frame(width: base, height: base)
        .padding(base * 0.35)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    let c = CGPoint(x: value.location.x - (base * 1.7) / 2, y: value.location.y - (base * 1.7) / 2)
                    let maxLen = travel * 1.15
                    let len = (c.x * c.x + c.y * c.y).squareRoot()
                    offset = len > maxLen ? CGPoint(x: c.x * maxLen / len, y: c.y * maxLen / len) : c
                    let now = ProcessInfo.processInfo.systemUptime
                    if !touching {
                        touching = true
                        session = StickCalibrationSession(travel: travel, gate: gate)
                        session.begin(at: offset, time: now)
                    } else {
                        session.move(to: offset, time: now)
                    }
                }
                .onEnded { _ in
                    touching = false
                    offset = .zero
                    if let result = session.lift() {
                        SharedStick.save(result, left: isLeft)
                        saved[isLeft] = result
                        notice = nil
                        advance()
                    } else {
                        notice = "That one didn't cover enough of the ring. Try again."
                        session = StickCalibrationSession(travel: travel, gate: gate)
                    }
                }
        )
        .accessibilityLabel(isLeft ? "Left stick calibration area" : "Right stick calibration area")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([true, false], id: \.self) { left in
                let cal = saved[left] ?? SharedStick.calibration(left: left)
                Text("\(left ? "Left" : "Right"): " + (cal.isIdentity
                     ? "not calibrated"
                     : "full output at \(Int((cal.fullThrow * 100).rounded()))% of the ring"))
                    .font(.system(size: 15, design: .rounded))
            }
        }
    }

    private func advance() {
        switch step {
        case .left: step = .right
        case .right: step = .done
        case .done: break
        }
        session = StickCalibrationSession(travel: session.travel, gate: gate)
        offset = .zero
    }

    private func restart() {
        step = .left
        notice = nil
        offset = .zero
        touching = false
    }
}
