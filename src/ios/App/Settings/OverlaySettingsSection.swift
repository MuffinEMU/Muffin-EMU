import SwiftUI

/// Where the performance overlay is drawn, mirroring CemuConfig.h's own ScreenPosition
/// enum value-for-value (kDisabled = 0 through kBottomRight = 6) so the raw int this
/// picker stores can be pushed straight into cemu_bridge_set_overlay_position() with no
/// remapping step to get wrong. Declared disabled-first, matching the core's own default
/// and putting "off" at the top of the picker rather than buried among six placements.
enum OverlayPosition: Int, CaseIterable, Identifiable {
    case disabled = 0
    case topLeft = 1
    case topCenter = 2
    case topRight = 3
    case bottomLeft = 4
    case bottomCenter = 5
    case bottomRight = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .disabled:     return "Off"
        case .topLeft:      return "Top Left"
        case .topCenter:    return "Top Center"
        case .topRight:     return "Top Right"
        case .bottomLeft:   return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight:  return "Bottom Right"
        }
    }
}

/// Settings keys for the three overlay rows this app exposes. CemuConfig's `overlay`
/// struct has other real fields (text_color, text_scale, cpu_mode, drawcalls,
/// cpu_per_core_usage, vram_usage, debug) - deliberately out of scope for this pass,
/// not forgotten; adding UI for them later just means adding more keys here.
enum OverlaySettings {
    static let positionKey = "muffin.overlay.position"
    static let defaultPosition = OverlayPosition.disabled

    static let fpsKey = "muffin.overlay.fps"
    static let defaultFps = true // matches CemuConfig's overlay.fps default

    static let cpuUsageKey = "muffin.overlay.cpuUsage"
    static let defaultCpuUsage = false // matches CemuConfig's overlay.cpu_usage default

    static let ramUsageKey = "muffin.overlay.ramUsage"
    static let defaultRamUsage = true // matches CemuConfig's overlay.ram_usage default
}

/// The on-screen FPS/CPU/RAM readout the core already knows how to draw - this section
/// only ever decides where it goes and which of the three rows are on, the same "app
/// owns the @AppStorage, GameManager pushes it before boot" split every other graphics
/// setting on this screen uses (see GraphicsSettingsSection.swift's header comment).
///
/// The three toggles are visually disabled rather than hidden when position is Off: the
/// overlay only reads them when it draws, so choosing which rows you want *before*
/// turning it on somewhere is a normal way to use this, and disabling communicates
/// "this has no effect right now" without discarding the choice the way hiding would.
struct OverlaySettingsSection: View {
    @AppStorage(OverlaySettings.positionKey) private var positionRaw = OverlaySettings.defaultPosition.rawValue
    @AppStorage(OverlaySettings.fpsKey) private var fpsEnabled = OverlaySettings.defaultFps
    @AppStorage(OverlaySettings.cpuUsageKey) private var cpuUsageEnabled = OverlaySettings.defaultCpuUsage
    @AppStorage(OverlaySettings.ramUsageKey) private var ramUsageEnabled = OverlaySettings.defaultRamUsage

    private var position: OverlayPosition {
        OverlayPosition(rawValue: positionRaw) ?? .disabled
    }

    private var isOff: Bool { position == .disabled }

    var body: some View {
        Section {
            positionPicker
            fpsToggle
            cpuUsageToggle
            ramUsageToggle
        } header: {
            Text("Performance Overlay")
        } footer: {
            InfoButton.footer(
                "A small on-screen readout of FPS, CPU and RAM use. Off by default; the three rows below only draw once a corner is picked.",
                title: "Performance Overlay",
                text: fullText)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var positionPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Position")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Picker("Position", selection: $positionRaw) {
                ForEach(OverlayPosition.allCases) { position in
                    Text(position.title).tag(position.rawValue)
                }
            }
        }
        .onChange(of: positionRaw) { newValue in
            cemu_bridge_set_overlay_position(Int32(newValue))
        }
    }

    private var fpsToggle: some View {
        Toggle(isOn: $fpsEnabled) {
            Text("Show FPS")
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: fpsEnabled) { newValue in
            cemu_bridge_set_overlay_fps(newValue)
        }
    }

    private var cpuUsageToggle: some View {
        Toggle(isOn: $cpuUsageEnabled) {
            Text("Show CPU Usage")
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: cpuUsageEnabled) { newValue in
            cemu_bridge_set_overlay_cpu_usage(newValue)
        }
    }

    private var ramUsageToggle: some View {
        Toggle(isOn: $ramUsageEnabled) {
            Text("Show RAM Usage")
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: ramUsageEnabled) { newValue in
            cemu_bridge_set_overlay_ram_usage(newValue)
        }
    }

    private var fullText: String {
        """
        The performance overlay is the engine's own on-screen readout, the same one desktop Cemu draws in a corner of the window. Position picks which corner (or top/bottom center) it appears in on the TV screen; Off leaves it out of the picture entirely, and the three rows below have no effect until a position is chosen.

        FPS is the frame rate the engine is actually producing, the same number cemu_bridge_get_fps() reports elsewhere in this app. CPU usage and RAM usage are the engine's own measurements of its own process, not the device's - they say what MuffinEMU itself is using, not what iOS is using overall.

        A few other overlay rows exist in the underlying engine (draw calls, per-core CPU breakdown, VRAM use, a text color/scale override, a debug row) but aren't exposed on this screen yet.
        """
    }
}
