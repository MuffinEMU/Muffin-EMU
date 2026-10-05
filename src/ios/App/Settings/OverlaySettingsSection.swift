import SwiftUI
import UIKit

/// Settings keys for the overlay rows, one @AppStorage key each, matching CemuConfig's
/// `overlay` struct. `cpuMode` has a key and default (GameManager still pushes it) but no
/// row: the overlay's draw pass doesn't read it.
enum OverlaySettings {
    static let positionKey = "muffin.overlay.position"
    static let defaultPosition = ScreenPosition.disabled

    static let textColorKey = "muffin.overlay.textColor"
    // Int, not UInt32: @AppStorage has no UInt32 overload. Packed 0xAARRGGBB.
    static let defaultTextColor: Int = 0xFFFFFFFF // opaque white, matches CemuConfig's default

    static let textScaleKey = "muffin.overlay.textScale"
    static let defaultTextScale = 100 // percent, matches CemuConfig's overlay.text_scale default

    static let fpsKey = "muffin.overlay.fps"
    static let defaultFps = true // matches CemuConfig's overlay.fps default

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

/// Colour binding over a packed 0xAARRGGBB value, for a ColorPicker. Always fully opaque on the
/// way out: a see-through text colour only ever made the readout hard to find. (The old
/// hex text field rejected every keystroke until a whole 6 or 8 digit value was pasted.)
func packedColourBinding(_ value: Binding<Int>) -> Binding<Color> {
    Binding {
        let packed = UInt32(truncatingIfNeeded: value.wrappedValue)
        return Color(.sRGB,
                     red: Double((packed >> 16) & 0xFF) / 255,
                     green: Double((packed >> 8) & 0xFF) / 255,
                     blue: Double(packed & 0xFF) / 255,
                     opacity: 1)
    } set: { newValue in
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(newValue).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
        func byte(_ component: CGFloat) -> UInt32 { UInt32(max(0, min(1, component)) * 255 + 0.5) }
        value.wrappedValue = Int(0xFF000000 | (byte(red) << 16) | (byte(green) << 8) | byte(blue))
    }
}

/// The on-screen FPS/CPU/RAM readout the core draws. This section sets where it goes, how it
/// looks and which rows are on; GameManager pushes the stored values before boot. Rows are
/// disabled (not hidden) while Position is Off so choices can be made before turning it on.
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
            // The row's own Text is the label; a menu picker in a Form row prints its label as well.
            .labelsHidden()
            .tint(MuffinTheme.accentText)
        }
        .onChange(of: positionRaw) { newValue in
            cemu_bridge_set_overlay_position(Int32(newValue))
        }
    }

    private var textColorField: some View {
        ColorPicker("Text color", selection: packedColourBinding($textColor), supportsOpacity: false)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .disabled(isOff)
            .onChange(of: textColor) { newValue in
                cemu_bridge_set_overlay_text_color(UInt32(truncatingIfNeeded: newValue))
            }
    }

    private var textScaleSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Text size")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(textScale)%")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(MuffinTheme.secondaryText)
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
        .tint(MuffinTheme.accentText)
        .disabled(isOff)
        .onChange(of: fpsEnabled) { newValue in
            cemu_bridge_set_overlay_fps(newValue)
        }
    }

    private var drawcallsToggle: some View {
        Toggle(isOn: $drawcallsEnabled) {
            Text("Show draw calls")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.accentText)
        .disabled(isOff)
        .onChange(of: drawcallsEnabled) { newValue in
            cemu_bridge_set_overlay_drawcalls(newValue)
        }
    }

    private var cpuUsageToggle: some View {
        Toggle(isOn: $cpuUsageEnabled) {
            Text("Show CPU usage")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.accentText)
        .disabled(isOff)
        .onChange(of: cpuUsageEnabled) { newValue in
            cemu_bridge_set_overlay_cpu_usage(newValue)
        }
    }

    private var cpuPerCoreUsageToggle: some View {
        Toggle(isOn: $cpuPerCoreUsageEnabled) {
            Text("Show CPU usage per core")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.accentText)
        .disabled(isOff)
        .onChange(of: cpuPerCoreUsageEnabled) { newValue in
            cemu_bridge_set_overlay_cpu_per_core_usage(newValue)
        }
    }

    private var ramUsageToggle: some View {
        Toggle(isOn: $ramUsageEnabled) {
            Text("Show RAM usage")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.accentText)
        .disabled(isOff)
        .onChange(of: ramUsageEnabled) { newValue in
            cemu_bridge_set_overlay_ram_usage(newValue)
        }
    }

    private var vramUsageToggle: some View {
        Toggle(isOn: $vramUsageEnabled) {
            Text("Show VRAM usage")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.accentText)
        .disabled(isOff)
        .onChange(of: vramUsageEnabled) { newValue in
            cemu_bridge_set_overlay_vram_usage(newValue)
        }
    }

    private var debugToggle: some View {
        Toggle(isOn: $debugEnabled) {
            Text("Show debug info")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.accentText)
        .disabled(isOff)
        .onChange(of: debugEnabled) { newValue in
            cemu_bridge_set_overlay_debug(newValue)
        }
    }

    private var fullText: String {
        """
        The overlay is the engine's own readout, like desktop Cemu's. Position picks a corner of the TV screen; Off hides it, and the other rows stay dimmed until a corner is chosen.

        FPS is the frame rate the game is producing. CPU, per-core CPU, RAM and VRAM usage measure MuffinEMU itself, not the whole device. Draw calls counts draw commands in the current frame. Debug info adds a few lines of renderer state.

        The panel only appears while at least one of FPS, draw calls, CPU, per-core CPU or RAM is on. VRAM usage and debug info are extra lines inside it, so on their own they show nothing.

        Text size and color change the readout's look. Changes show up straight away.
        """
    }
}
