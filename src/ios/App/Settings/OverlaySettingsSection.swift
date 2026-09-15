import SwiftUI

/// Settings keys for every row this section exposes - the full set of fields on
/// CemuConfig's `overlay` struct, one @AppStorage key each. See CemuBridge.h's comment
/// on the overlay bridge functions for which rows the renderer actually acts on
/// (cpu_mode round-trips but isn't currently read by LatteOverlay_renderOverlay()).
enum OverlaySettings {
    static let positionKey = "muffin.overlay.position"
    static let defaultPosition = ScreenPosition.disabled

    static let textColorKey = "muffin.overlay.textColor"
    // Int, not UInt32: @AppStorage has no UInt32 overload (Bool/Int/Double/String/URL/Data
    // and RawRepresentable-over-those only - see GraphicsSettingsSection.swift's identical
    // note on DisplayGammaSetting/Float). The packed 0xAARRGGBB value fits Int on every
    // platform this app runs on; cemu_bridge_set_overlay_text_color still takes the C
    // `uint32_t` the engine expects, converted at the one call site.
    static let defaultTextColor: Int = 0xFFFFFFFF // opaque white, matches CemuConfig's default

    static let textScaleKey = "muffin.overlay.textScale"
    static let defaultTextScale = 100 // percent, matches CemuConfig's overlay.text_scale default

    static let fpsKey = "muffin.overlay.fps"
    static let defaultFps = true // matches CemuConfig's overlay.fps default

    static let cpuModeKey = "muffin.overlay.cpuMode"
    static let defaultCpuMode = true // matches CemuConfig's overlay.cpu_mode default

    static let drawcallsKey = "muffin.overlay.drawcalls"
    static let defaultDrawcalls = false // matches CemuConfig's overlay.drawcalls default

    static let cpuUsageKey = "muffin.overlay.cpuUsage"
    static let defaultCpuUsage = false // matches CemuConfig's overlay.cpu_usage default

    static let cpuPerCoreUsageKey = "muffin.overlay.cpuPerCoreUsage"
    static let defaultCpuPerCoreUsage = false // matches CemuConfig's overlay.cpu_per_core_usage default

    static let ramUsageKey = "muffin.overlay.ramUsage"
    static let defaultRamUsage = true // matches CemuConfig's overlay.ram_usage default

    static let vramUsageKey = "muffin.overlay.vramUsage"
    static let defaultVramUsage = false // matches CemuConfig's overlay.vram_usage default

    static let debugKey = "muffin.overlay.debug"
    static let defaultDebug = true // matches CemuConfig's overlay.debug default
}

/// The on-screen FPS/CPU/RAM readout the core already knows how to draw - this section
/// only ever decides where it goes, how it looks, and which rows are on, the same "app
/// owns the @AppStorage, GameManager pushes it before boot" split every other graphics
/// setting on this screen uses (see GraphicsSettingsSection.swift's header comment).
///
/// The rows below are visually disabled rather than hidden when position is Off: the
/// overlay only reads them when it draws, so choosing what you want *before* turning it
/// on somewhere is a normal way to use this, and disabling communicates "this has no
/// effect right now" without discarding the choice the way hiding would.
struct OverlaySettingsSection: View {
    @AppStorage(OverlaySettings.positionKey) private var positionRaw = OverlaySettings.defaultPosition.rawValue
    @AppStorage(OverlaySettings.textColorKey) private var textColor = OverlaySettings.defaultTextColor
    @AppStorage(OverlaySettings.textScaleKey) private var textScale = OverlaySettings.defaultTextScale
    @AppStorage(OverlaySettings.fpsKey) private var fpsEnabled = OverlaySettings.defaultFps
    @AppStorage(OverlaySettings.cpuModeKey) private var cpuModeEnabled = OverlaySettings.defaultCpuMode
    @AppStorage(OverlaySettings.drawcallsKey) private var drawcallsEnabled = OverlaySettings.defaultDrawcalls
    @AppStorage(OverlaySettings.cpuUsageKey) private var cpuUsageEnabled = OverlaySettings.defaultCpuUsage
    @AppStorage(OverlaySettings.cpuPerCoreUsageKey) private var cpuPerCoreUsageEnabled = OverlaySettings.defaultCpuPerCoreUsage
    @AppStorage(OverlaySettings.ramUsageKey) private var ramUsageEnabled = OverlaySettings.defaultRamUsage
    @AppStorage(OverlaySettings.vramUsageKey) private var vramUsageEnabled = OverlaySettings.defaultVramUsage
    @AppStorage(OverlaySettings.debugKey) private var debugEnabled = OverlaySettings.defaultDebug

    private var position: ScreenPosition {
        ScreenPosition(rawValue: positionRaw) ?? .disabled
    }

    private var isOff: Bool { position == .disabled }

    var body: some View {
        Section {
            positionPicker
            textColorField
            textScaleSlider
            fpsToggle
            cpuModeToggle
            drawcallsToggle
            cpuUsageToggle
            cpuPerCoreUsageToggle
            ramUsageToggle
            vramUsageToggle
            debugToggle
        } header: {
            Text("Performance Overlay")
        } footer: {
            InfoButton.footer(
                "A small on-screen readout of FPS, CPU and RAM use. Off by default; the rows below only draw once a corner is picked.",
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
                ForEach(ScreenPosition.allCases) { position in
                    Text(position.title).tag(position.rawValue)
                }
            }
        }
        .onChange(of: positionRaw) { newValue in
            cemu_bridge_set_overlay_position(Int32(newValue))
        }
    }

    // 0xAARRGGBB packed the same way ImGui::ColorConvertU32ToFloat4 reads it - see
    // CemuBridge.h's doc comment on cemu_bridge_set_overlay_text_color(). Accepts either
    // a 6-digit RGB hex (treated as fully opaque) or an 8-digit ARGB one; anything else
    // is left uncommitted rather than guessed at.
    private var textColorHex: Binding<String> {
        Binding {
            String(format: "#%08X", UInt32(textColor))
        } set: { newValue in
            let cleaned = newValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "#", with: "")
            guard let parsed = UInt32(cleaned, radix: 16) else { return }
            switch cleaned.count {
            case 6: textColor = Int(0xFF000000 | parsed)
            case 8: textColor = Int(parsed)
            default: return
            }
        }
    }

    private var textColorField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Text Color")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            TextField("AARRGGBB", text: textColorHex)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
        .disabled(isOff)
        .onChange(of: textColor) { newValue in
            cemu_bridge_set_overlay_text_color(UInt32(newValue))
        }
    }

    private var textScaleSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Text Scale")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(textScale)%")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Slider(
                value: Binding(get: { Double(textScale) }, set: { textScale = Int($0) }),
                in: 50...200, step: 25)
        }
        .disabled(isOff)
        .onChange(of: textScale) { newValue in
            cemu_bridge_set_overlay_text_scale(Int32(newValue))
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

    private var cpuModeToggle: some View {
        Toggle(isOn: $cpuModeEnabled) {
            Text("CPU Mode")
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: cpuModeEnabled) { newValue in
            cemu_bridge_set_overlay_cpu_mode(newValue)
        }
    }

    private var drawcallsToggle: some View {
        Toggle(isOn: $drawcallsEnabled) {
            Text("Draw Calls")
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: drawcallsEnabled) { newValue in
            cemu_bridge_set_overlay_drawcalls(newValue)
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

    private var cpuPerCoreUsageToggle: some View {
        Toggle(isOn: $cpuPerCoreUsageEnabled) {
            Text("CPU Per Core Usage")
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: cpuPerCoreUsageEnabled) { newValue in
            cemu_bridge_set_overlay_cpu_per_core_usage(newValue)
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

    private var vramUsageToggle: some View {
        Toggle(isOn: $vramUsageEnabled) {
            Text("VRAM Usage")
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: vramUsageEnabled) { newValue in
            cemu_bridge_set_overlay_vram_usage(newValue)
        }
    }

    private var debugToggle: some View {
        Toggle(isOn: $debugEnabled) {
            Text("Debug")
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: debugEnabled) { newValue in
            cemu_bridge_set_overlay_debug(newValue)
        }
    }

    private var fullText: String {
        """
        The performance overlay is the engine's own on-screen readout, the same one desktop Cemu draws in a corner of the window. Position picks which corner (or top/bottom center) it appears in on the TV screen; Off leaves it out of the picture entirely, and the rows below have no effect until a position is chosen.

        Text Color and Text Scale style the readout itself. FPS is the frame rate the engine is actually producing, the same number cemu_bridge_get_fps() reports elsewhere in this app. CPU Usage, CPU Per Core Usage, RAM Usage and VRAM Usage are the engine's own measurements of its own process, not the device's - they say what MuffinEMU itself is using, not what iOS is using overall. Draw Calls shows how many draw commands the current frame issued. Debug adds a short block of internal renderer state. CPU Mode is a real, saved setting on this same overlay, but the current build's overlay draw pass doesn't act on it yet - toggling it has no visible effect.
        """
    }
}
