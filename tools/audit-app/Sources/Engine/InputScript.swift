//
//  InputScript.swift
//  Drives the emulated GamePad (buttons, sticks, touch) through the bridge while the guest's
//  input_echo test reads it, and checks what the guest says it saw. A step that cannot be checked
//  (touch coordinates, whose mapping is the most platform-dependent part) defaults to "warn", so a
//  difference is reported without failing the test.
//
import Foundation

extension AuditRunner {
    func runScript(_ steps: [ScriptStep], m: inout Measurements) async {
        let vpad: [String: UInt32] = [
            "A": 0x8000, "B": 0x4000, "X": 0x2000, "Y": 0x1000, "LEFT": 0x0800, "RIGHT": 0x0400, "UP": 0x0200, "DOWN": 0x0100,
            "ZL": 0x0080, "ZR": 0x0040, "L": 0x0020, "R": 0x0010, "PLUS": 0x0008, "MINUS": 0x0004,
            "STICK_L": 0x0004_0000, "STICK_R": 0x0002_0000,
        ]
        func state() -> GuestState { link.readState() ?? GuestState() }
        func record(_ label: String, _ action: String, _ pass: Bool, _ severity: String, expected: String, measured: String) {
            m.scriptResults.append(ScriptResult(label: label, action: action, pass: pass, severity: severity, expected: expected, measured: measured, tNs: core.nowNs))
        }
        func wait(_ ms: Int) async {
            var left = ms
            while left > 0 {
                let slice = min(left, 40)
                try? await Task.sleep(nanoseconds: UInt64(slice) * 1_000_000)
                logs.drain()
                left -= slice
            }
        }

        core.releaseAllInput()
        await wait(300)

        for step in steps {
            if host?.isCancelled == true { break }
            let severity = step.severity ?? "fail"
            switch step.action {
            case "press":
                let name = (step.button ?? "A").uppercased()
                let label = step.label ?? "press \(name)"
                let mask = UInt32(step.expectHold ?? Int(vpad[name] ?? 0))
                let holdMs = step.holdMs ?? 400
                core.button(name, pressed: true)
                var seen = false
                var lastHold: UInt32 = 0
                var waited = 0
                // Hold for at least holdMs, and keep looking (up to 400 ms more) until the guest has reported the button.
                while waited < holdMs + 400 && !(seen && waited >= holdMs) {
                    await wait(40)
                    waited += 40
                    lastHold = state().inputHold
                    if mask != 0 && lastHold & mask == mask { seen = true }
                }
                core.button(name, pressed: false)
                await wait(250)
                let released = state().inputHold & mask == 0
                record(label, "press", seen && released, severity, expected: String(format: "hold bit 0x%X set while held, clear after", mask),
                       measured: "\(seen ? "set" : "never set (hold was \(String(format: "0x%X", lastHold)))"), \(released ? "cleared" : "still set after release")")

            case "stick":
                let left = (step.stick ?? "left") == "left"
                let x = step.x ?? 0, y = step.y ?? 0
                let tol = step.tolerance ?? 0.12
                let label = step.label ?? "\(left ? "left" : "right") stick (\(x), \(y))"
                core.stick(left: left, x: Float(x), y: Float(y))
                await wait(step.settleMs ?? 500)
                let s = state()
                let gx = Double(left ? s.leftX : s.rightX) / 1000.0, gy = Double(left ? s.leftY : s.rightY) / 1000.0
                // The hardware clamps to the unit circle, so ask for what a clamped request would give.
                let mag = (x * x + y * y).squareRoot()
                let ex = mag > 1 ? x / mag : x, ey = mag > 1 ? y / mag : y
                let ok = abs(gx - ex) <= tol && abs(gy - ey) <= tol
                record(label, "stick", ok, severity, expected: String(format: "(%.2f, %.2f) within %.2f", ex, ey, tol), measured: String(format: "(%.2f, %.2f)", gx, gy))
                core.stick(left: left, x: 0, y: 0)
                await wait(200)

            case "touch":
                let x = step.x ?? 0.5, y = step.y ?? 0.5
                let label = step.label ?? String(format: "touch (%.2f, %.2f)", x, y)
                let w = Double(request.padSurface ? (surfaceInfo?.padWidth ?? 854) : (surfaceInfo?.tvWidth ?? 1280)) * (surfaceInfo?.scale ?? 1)
                let h = Double(request.padSurface ? (surfaceInfo?.padHeight ?? 480) : (surfaceInfo?.tvHeight ?? 720)) * (surfaceInfo?.scale ?? 1)
                core.padTouch(x: x * w, y: y * h, down: true)
                await wait(step.settleMs ?? 600)
                let s = state()
                let touched = s.touchState & 1 != 0
                record(label + ": registered", "touch", touched, severity, expected: "guest sees the screen touched", measured: touched ? "touched" : "not touched (touch state \(s.touchState))")
                let gx = Double(s.touchX) / 1280.0, gy = Double(s.touchY) / 720.0
                let tol = step.tolerance ?? 0.12
                record(label + ": position", "touch", touched && abs(gx - x) <= tol && abs(gy - y) <= tol, "warn",
                       expected: String(format: "about (%.2f, %.2f) of 1280x720", x, y), measured: String(format: "(%.2f, %.2f), raw (%d, %d)", gx, gy, Int(s.touchX), Int(s.touchY)))
                core.padTouch(x: x * w, y: y * h, down: false)
                await wait(250)
                let after = state().touchState & 1 == 0
                record(label + ": released", "touch", after, severity, expected: "guest sees the touch end", measured: after ? "ended" : "still touched")

            case "release":
                core.releaseAllInput()
                await wait(step.settleMs ?? 400)
                let s = state()
                let clear = s.inputHold == 0 && abs(s.leftX) < 150 && abs(s.leftY) < 150 && abs(s.rightX) < 150 && abs(s.rightY) < 150
                record(step.label ?? "release everything", "release", clear, severity, expected: "no buttons held, sticks centred", measured: String(format: "hold 0x%X, left (%d, %d), right (%d, %d)", s.inputHold, Int(s.leftX), Int(s.leftY), Int(s.rightX), Int(s.rightY)))

            case "await_physical":
                // Informational: did anyone press a real button or touch the screen while this waited?
                let baseline = state().inputChanges
                let deadline = Date().addingTimeInterval(Double(step.holdMs ?? 6000) / 1000.0)
                var saw = false
                while Date() < deadline && !saw {
                    await wait(100)
                    saw = state().inputChanges != baseline
                }
                record(step.label ?? "physical input", "await_physical", saw, "info", expected: "a real button press or touch reaches the guest (optional)",
                       measured: saw ? "input seen" : "none seen")

            case "wait":
                await wait(step.holdMs ?? 500)

            default:
                record(step.label ?? step.action, step.action, false, "warn", expected: "a known script action", measured: "unknown action \(step.action)")
            }
        }
        core.releaseAllInput()
    }
}
