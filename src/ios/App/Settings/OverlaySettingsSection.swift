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

/// Text binding for a packed 0xAARRGGBB colour. Accepts a 6-digit RGB hex (treated as
/// fully opaque) or an 8-digit ARGB one; anything else is left uncommitted.
func hexColourBinding(_ value: Binding<Int>) -> Binding<String> {
    Binding {
        String(format: "#%08X", UInt32(truncatingIfNeeded: value.wrappedValue))
    } set: { newValue in
        let cleaned = newValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard let parsed = UInt32(cleaned, radix: 16) else { return }
        switch cleaned.count {
        case 6: value.wrappedValue = Int(0xFF000000 | parsed)
        case 8: value.wrappedValue = Int(parsed)
        default: return
        }
    }
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
            drawcallsToggle
            cpuUsageToggle
            cpuPerCoreUsageToggle
            ramUsageToggle
            vramUsageToggle
            debugToggle
        } header: {
            SettingsSectionHeader("Performance Overlay", icon: "speedometer", accent: .io)
        } footer: {
            InfoButton.footer(
                "Shows FPS, CPU and RAM use on screen. Pick a corner to turn it on.",
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
            .pickerStyle(.menu)
            .tint(MuffinTheme.pixelBlue)
        }
        .onChange(of: positionRaw) { newValue in
            cemu_bridge_set_overlay_position(Int32(newValue))
        }
    }

    private var textColorHex: Binding<String> { hexColourBinding($textColor) }

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
            cemu_bridge_set_overlay_text_color(UInt32(truncatingIfNeeded: newValue))
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
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: fpsEnabled) { newValue in
            cemu_bridge_set_overlay_fps(newValue)
        }
    }

    private var drawcallsToggle: some View {
        Toggle(isOn: $drawcallsEnabled) {
            Text("Draw Calls")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.pixelBlue)
        .disabled(isOff)
        .onChange(of: debugEnabled) { newValue in
            cemu_bridge_set_overlay_debug(newValue)
        }
    }

    private var fullText: String {
        """
        The overlay is the engine's own readout, like desktop Cemu's. Position picks a corner of the TV screen; Off hides it.

        FPS is the frame rate the game is producing. CPU, per-core CPU, RAM and VRAM usage measure MuffinEMU itself, not the whole device. Draw Calls counts draw commands in the current frame. Debug adds a few lines of renderer state.
        """
    }
}
