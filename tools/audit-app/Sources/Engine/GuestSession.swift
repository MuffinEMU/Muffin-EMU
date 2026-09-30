//
//  GuestSession.swift
//  Booting and stopping the guest, and waiting for it to announce its mailbox.
//
import Foundation

extension AuditRunner {
    /// Makes sure audit.rpx is running with its mailbox attached, booting it if it is not. Throws with a
    /// description (including the last lines of the core's log) when it cannot.
    func ensureGuest() async throws {
        if guestUp && core.titleRunning && link.isAttached && link.isValid() { return }
        await stopGuest()
        guard let host = host, let surfaces = await host.surfaces() else { throw CoreError.message("the app has no render surface to give the core") }

        logs.reset()
        link.detach()
        helloAddress = nil
        probeEvents.removeAll()
        let bootStart = core.nowNs

        surfaceInfo = surfaces
        let attached = await host.attach(surfaces, pad: request.padSurface, to: core)
        guard attached else { throw CoreError.message("the render surface could not be registered with the core") }

        let settings = CoreDriver.BootSettings(renderer: request.renderer, recompiler: wantRecompiler(), vsync: true)
        let path = rpxPath
        let core = self.core
        bootCount += 1
        logs.hostLine("BOOT #\(bootCount) renderer=\(settings.renderer) recompiler=\(settings.recompiler)")
        let failure: String? = await Task.detached(priority: .userInitiated) { core.boot(rpxPath: path, settings: settings) }.value
        if let failure = failure { throw CoreError.message(failure) }

        // Wait for the guest's HELLO line, then for the magic word in its mailbox.
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
            logs.drain()
            if host.isCancelled { throw CoreError.message("cancelled") }
            for (event, _) in probeEvents {
                if case .hello(let proto, let build, let addr, _) = event {
                    guard proto == Int(Mailbox.protocolVersion) else {
                        throw CoreError.message("the guest speaks probe protocol \(proto) but this app speaks \(Mailbox.protocolVersion)")
                    }
                    helloAddress = addr
                    helloBuild = build
                }
            }
            if let addr = helloAddress {
                link.attach(address: addr)
                if link.isValid() { break }
            }
            if !core.titleRunning && Date().timeIntervalSince(deadline.addingTimeInterval(-45)) > 5 {
                throw CoreError.message("the title stopped before the guest announced itself.\n" + tail())
            }
        }
        guard link.isAttached, link.isValid() else {
            throw CoreError.message("the guest did not announce a valid mailbox within 45 s.\n" + tail())
        }
        if let s = link.readState(), s.state == Mailbox.stateFatal {
            throw CoreError.message("the guest could not start: \(s.message)")
        }
        link.setHostFlags(captureWorking: captureAvailable, padSurface: request.padSurface)
        guestUp = true
        let ms = Double(core.nowNs &- bootStart) / 1_000_000.0
        logs.hostLine("GUEST UP in \(Int(ms)) ms build=\(helloBuild)")
    }

    func wantRecompiler() -> Bool {
        switch request.cpu {
        case "interpreter": return false
        case "recompiler": return core.jitPermitted
        default: return core.jitPermitted
        }
    }

    func stopGuest() async {
        guard core.initialized else { return }
        if link.isAttached && core.titleRunning { link.send(command: Mailbox.cmdExit) }
        if core.titleRunning {
            let core = self.core
            await Task.detached(priority: .userInitiated) { core.stopTitle() }.value
        }
        link.detach()
        guestUp = false
    }

    func tail(_ n: Int = 12) -> String {
        "Last core log lines:\n" + logs.lines.suffix(n).map { $0.text }.joined(separator: "\n")
    }
}
