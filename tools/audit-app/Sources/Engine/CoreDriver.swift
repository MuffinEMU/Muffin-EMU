//
//  CoreDriver.swift
//  The app's one door into the MuffinEMU core: the regular bridge (CemuBridge.h) for boot, settings and
//  input, and the audit hooks (IOSAuditHooks.h) for snapshots, frame readback and the probe mailbox.
//  The sequence mirrors what the Bench app does per engine (initialize, attach the surface on the main
//  thread, boot, poll, stop), which is known to work on device.
//
import Foundation

struct CoreCapabilities {
    var line: String
    var machine: String
    var chip: String
    var tier: Int
    var appleGpuFamily: Int
    var bcTextures: Bool
    var metal3: Bool
    var physicalMemoryMB: Int
    var logicalCores: Int
}

enum CoreError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let m): return m }
    }
}

final class CoreDriver {
    static let shared = CoreDriver()

    private(set) var initialized = false
    private(set) var dataDir = ""

    // MARK: Hooks

    var hooksVersion: Int { Int(cemu_audit_api_version()) }
    var hooksCompatible: Bool { hooksVersion == Int(CEMU_AUDIT_API_VERSION) }
    var hooksBuildInfo: String { String(cString: cemu_audit_build_info()) }
    var nowNs: UInt64 { cemu_audit_now_ns() }

    // MARK: Start-up

    /// The device capability snapshot. Safe to call repeatedly; the first call takes it.
    func captureCapabilities() -> CoreCapabilities {
        let s = Platform.screen
        cemu_device_caps_set_screen(s.shortPoints, s.longPoints, s.scale, s.isPad)
        cemu_device_caps_initialize()
        var caps = CemuDeviceCaps()
        cemu_device_caps_get(&caps)
        return CoreCapabilities(line: String(cString: cemu_device_caps_line()),
                                machine: String(cString: cemu_device_caps_machine()),
                                chip: String(cString: cemu_device_caps_chip()),
                                tier: Int(caps.tier), appleGpuFamily: Int(caps.appleGpuFamily),
                                bcTextures: caps.bcTextures, metal3: caps.metal3,
                                physicalMemoryMB: Int(caps.physicalMemory / (1024 * 1024)),
                                logicalCores: Int(caps.logicalCores))
    }

    var deviceReport: String { String(cString: cemu_bridge_device_report()) }
    var crashLogPath: String { String(cString: cemu_bridge_crash_log_path()) }

    /// One-time engine set-up under Application Support (the app's Documents folder is for reports only).
    func initializeCore(logProfile: Int) throws {
        if initialized { cemu_audit_set_log_profile(Int32(logProfile)); return }
        guard cemu_bridge_core_available() else { throw CoreError.message("this build has no core linked in") }
        guard hooksCompatible else {
            throw CoreError.message("the core's audit hooks are version \(hooksVersion) but this app was built for \(CEMU_AUDIT_API_VERSION)")
        }
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("AuditCore", isDirectory: true)
        try? FileManager.default.removeItem(at: base)
        let mlc = base.appendingPathComponent("mlc", isDirectory: true)
        try FileManager.default.createDirectory(at: mlc, withIntermediateDirectories: true)
        dataDir = base.path

        // The same settings every audit run gets, whatever the device: no clock ladder, no accuracy mode,
        // one emulated CPU core, real-time clock.
        cemu_bridge_set_timebase_auto_enabled(false)
        cemu_bridge_set_favour_accuracy(false)
        cemu_bridge_set_favour_performance(false)
        cemu_bridge_initialize(mlc.path)
        // -1 means the engine never initialized (the bridge answers "cannot answer" then).
        guard cemu_bridge_reload_and_count_keys() >= 0 else { throw CoreError.message("the core did not initialize") }
        cemu_bridge_set_timebase_shift(3)
        cemu_bridge_set_cpu_core_mode(1)
        // After initialize, which installs its own mix of log categories.
        cemu_audit_set_log_profile(Int32(logProfile))
        ios_live_log_set_enabled(true)
        // A 10 Hz memory sampler and the memory-warning hook, written to the crash log with synchronous writes: the
        // termination they explain (jetsam) leaves no other trace.
        cemu_bridge_start_memory_watchdog()
        initialized = true
    }

    // MARK: Surfaces (main thread)

    func attachTV(view: UnsafeMutableRawPointer, widthPoints: Int, heightPoints: Int, scale: Double) {
        cemu_bridge_register_render_surface(view, Int32(widthPoints), Int32(heightPoints), scale)
    }

    func attachPad(view: UnsafeMutableRawPointer, widthPoints: Int, heightPoints: Int, scale: Double) {
        cemu_bridge_register_pad_render_surface(view, Int32(widthPoints), Int32(heightPoints), scale)
    }

    func releasePad() { cemu_bridge_release_pad_render_surface() }
    var padRegistered: Bool { cemu_bridge_has_pad_render_surface() }

    // MARK: Boot and stop

    struct BootSettings {
        var renderer: String   // "metal" or "vulkan"
        var recompiler: Bool
        var vsync: Bool
    }

    /// Blocking: call from a background task. Returns nil on success or a description of what the core said.
    func boot(rpxPath: String, settings: BootSettings) -> String? {
        cemu_bridge_set_graphics_api(settings.renderer == "vulkan" ? 1 : 2)
        cemu_bridge_set_recompiler_enabled(settings.recompiler)
        cemu_bridge_set_vsync_enabled(settings.vsync)
        cemu_bridge_set_timebase_shift(3)
        let status = cemu_bridge_boot_title(rpxPath)
        if status.rawValue == 0 { return nil }
        let text = String(cString: cemu_bridge_status_text())
        return "boot failed with status \(status.rawValue): \(text)"
    }

    var titleRunning: Bool { cemu_bridge_is_title_running() }

    func stopTitle() { cemu_bridge_shutdown_title() }

    var launchNotice: String { String(cString: cemu_bridge_take_launch_notice()) }

    // MARK: Read-outs

    func snapshot() -> JSONValue? {
        guard let p = cemu_audit_snapshot_json() else { return nil }
        return JSONValue.parse(String(cString: p))
    }

    var fps: Double { cemu_bridge_get_fps() }
    var videoStallKind: Int { Int(cemu_bridge_video_stall_kind()) }
    var perfLine: String { String(cString: cemu_bridge_perf_line()) }
    var cpuModeName: String {
        switch cemu_bridge_cpu_mode() { case 1: return "interpreter"; case 2: return "recompiler"; default: return "undecided" }
    }
    var coresRunning: Int { Int(cemu_bridge_cpu_cores_running()) }
    var graphicsApiName: String { cemu_bridge_graphics_api() == 1 ? "vulkan" : "metal" }

    /// Whether this process may run generated code (CS_DEBUGGED), the same test the Bench app uses.
    var jitPermitted: Bool {
        var flags: UInt32 = 0
        return csops(getpid(), 0, &flags, MemoryLayout<UInt32>.size) == 0 && (flags & 0x1000_0000) != 0
    }

    // MARK: Frame readback

    func armCapture(tv: Bool, pad: Bool, count: Int, thumbWidth: Int = 128, thumbHeight: Int = 72) {
        var mask: UInt32 = 0
        if tv { mask |= CEMU_AUDIT_VIEW_TV }
        if pad { mask |= CEMU_AUDIT_VIEW_PAD }
        cemu_audit_capture_arm(mask, UInt32(count), UInt32(thumbWidth), UInt32(thumbHeight))
    }

    func cancelCapture() { cemu_audit_capture_cancel() }
    var capturePending: Int { Int(cemu_audit_capture_pending()) }

    func popFrame() -> CapturedFrame? {
        var h = CemuAuditFrame()
        // The thumbnail is thumbWidth*thumbHeight*3 bytes; 512x288 is the largest the hook allows.
        var buf = [UInt8](repeating: 0, count: 512 * 288 * 3)
        let got = buf.withUnsafeMutableBufferPointer { cemu_audit_capture_pop(&h, $0.baseAddress, UInt32($0.count)) }
        guard got else { return nil }
        var f = CapturedFrame()
        f.seq = h.seq; f.view = Int(h.view); f.status = h.status; f.latteFrame = h.latteFrame; f.tNs = h.timestampNs
        f.srcWidth = Int(h.srcWidth); f.srcHeight = Int(h.srcHeight); f.pixelFormat = Int(h.pixelFormat)
        f.thumbWidth = Int(h.thumbWidth); f.thumbHeight = Int(h.thumbHeight)
        f.meanR = Double(h.meanR); f.meanG = Double(h.meanG); f.meanB = Double(h.meanB)
        f.blackFraction = Double(h.blackFraction); f.whiteFraction = Double(h.whiteFraction)
        f.minLuma = Int(h.minLuma); f.maxLuma = Int(h.maxLuma); f.hash = h.hash
        if h.status == 0 { f.thumb = Array(buf.prefix(Int(h.thumbWidth) * Int(h.thumbHeight) * 3)) }
        return f
    }

    // MARK: Frame pacing and audio

    func setFrameTiming(_ enabled: Bool) { cemu_audit_frame_timing_enable(enabled) }

    /// Present timestamps recorded on the GPU thread since the last call, and how many the ring lost.
    func drainFrameTimes() -> (times: [UInt64], dropped: Int) {
        var out = [UInt64](repeating: 0, count: 4096)
        var dropped: UInt32 = 0
        let n = out.withUnsafeMutableBufferPointer { cemu_audit_frame_timing_drain($0.baseAddress, UInt32($0.count), &dropped) }
        return (Array(out.prefix(Int(n))), Int(dropped))
    }

    func resetAudioStats() { cemu_audit_audio_reset() }

    // MARK: Input injection

    func button(_ name: String, pressed: Bool) {
        let map: [String: CemuBridgeButton] = [
            "A": CEMU_BRIDGE_BUTTON_A, "B": CEMU_BRIDGE_BUTTON_B, "X": CEMU_BRIDGE_BUTTON_X, "Y": CEMU_BRIDGE_BUTTON_Y,
            "L": CEMU_BRIDGE_BUTTON_L, "R": CEMU_BRIDGE_BUTTON_R, "ZL": CEMU_BRIDGE_BUTTON_ZL, "ZR": CEMU_BRIDGE_BUTTON_ZR,
            "PLUS": CEMU_BRIDGE_BUTTON_PLUS, "MINUS": CEMU_BRIDGE_BUTTON_MINUS,
            "UP": CEMU_BRIDGE_BUTTON_UP, "DOWN": CEMU_BRIDGE_BUTTON_DOWN, "LEFT": CEMU_BRIDGE_BUTTON_LEFT, "RIGHT": CEMU_BRIDGE_BUTTON_RIGHT,
            "STICK_L": CEMU_BRIDGE_BUTTON_STICK_L, "STICK_R": CEMU_BRIDGE_BUTTON_STICK_R,
        ]
        if let b = map[name.uppercased()] { cemu_bridge_set_button_state(b, pressed) }
    }

    func stick(left: Bool, x: Float, y: Float) {
        cemu_bridge_set_stick_axis(left ? CEMU_BRIDGE_STICK_LEFT : CEMU_BRIDGE_STICK_RIGHT, x, y)
    }

    func releaseAllInput() { cemu_bridge_release_all_buttons() }

    func padTouch(x: Double, y: Double, down: Bool) { cemu_bridge_set_pad_touch(x, y, down) }

    // MARK: Memory

    func memoryStatus() -> (availableMB: Double, footprintMB: Double)? {
        var avail: UInt64 = 0, foot: UInt64 = 0
        guard cemu_bridge_memory_status(&avail, &foot) else { return nil }
        return (Double(avail) / 1_048_576.0, Double(foot) / 1_048_576.0)
    }
}
