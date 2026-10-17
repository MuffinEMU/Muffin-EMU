// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI
import Metal

/// Which graphics API the engine draws through. Metal is the native backend; Vulkan runs
/// through MoltenVK's translation layer, for compatibility cases Metal doesn't cover.
///
/// Declared metal-then-vulkan so `.allCases` puts the default first in the segmented control.
enum RendererAPI: Int, CaseIterable, Identifiable {
    case metal = 2
    case vulkan = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .metal:  return "Metal"
        case .vulkan: return "Vulkan (experimental)"
        }
    }

    static let storageKey = "muffin.render.graphicsAPI"
    static let defaultValue: RendererAPI = .metal
}

/// One filter enum shared by both the upscale and downscale pickers below - the
/// four choices are the same set either way, only the default and which direction
/// it applies to differ.
enum ScaleFilter: Int, CaseIterable, Identifiable {
    case linear = 0
    case bicubic = 1
    case bicubicHermite = 2
    case nearestNeighbor = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .linear:         return "Linear"
        case .bicubic:        return "Bicubic"
        case .bicubicHermite: return "Bicubic Hermite"
        case .nearestNeighbor: return "Nearest neighbour"
        }
    }
}

enum UpscaleFilterSetting {
    static let storageKey = "muffin.render.upscaleFilter"
    static let defaultValue = ScaleFilter.bicubic
}

enum DownscaleFilterSetting {
    static let storageKey = "muffin.render.downscaleFilter"
    static let defaultValue = ScaleFilter.linear
}

/// Settings > Graphics > Texture filtering, backing cemu_bridge_set_anisotropic_filtering(): the anisotropic
/// ratio applied to every texture a game filters, or the game's own. The raw value is the log2 of the ratio
/// the bridge takes (-1 for the game's own), so the stored value is what the engine reads.
enum TextureFiltering: Int, CaseIterable, Identifiable {
    case gameDefault = -1
    case x2 = 1
    case x4 = 2
    case x8 = 3
    case x16 = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .gameDefault: return "Game default"
        case .x2: return "2x anisotropic"
        case .x4: return "4x anisotropic"
        case .x8: return "8x anisotropic"
        case .x16: return "16x anisotropic"
        }
    }

    static let storageKey = "muffin.render.textureFiltering"
    static let defaultValue: TextureFiltering = .gameDefault

    static var stored: TextureFiltering {
        TextureFiltering(rawValue: UserDefaults.standard.object(forKey: storageKey) as? Int ?? defaultValue.rawValue) ?? defaultValue
    }

    static func applyToBridge() {
        cemu_bridge_set_anisotropic_filtering(Int32(stored.rawValue))
    }
}

/// Backs cemu_bridge_set_display_gamma(). minValue/maxValue mirror the bridge's clamp so the
/// slider can't show a position the push would silently correct.
enum DisplayGammaSetting {
    static let storageKey = "muffin.render.displayGamma"
    // Double, not Float: @AppStorage has no Float overload; converted at the call site.
    static let defaultValue: Double = 2.2
    static let minValue: Double = 1.0
    static let maxValue: Double = 3.0
}

/// Backs cemu_bridge_set_override_gamma_value(): a separate gamma stage from Display Gamma
/// (see that function's doc in CemuBridge.h). Same Double storage and 1.0-3.0 range.
enum OverrideGammaSetting {
    static let storageKey = "muffin.render.overrideGammaValue"
    static let defaultValue: Double = 2.2 // matches CemuConfig's overrideGammaValue default
    static let minValue: Double = 1.0
    static let maxValue: Double = 3.0
}

/// Which MoltenVK build the Vulkan renderer loads: 1.4.3 by default, or the older 1.2.8. The
/// bridge reads the key once at engine start; a loaded MoltenVK can't be swapped in a
/// running process.
enum MoltenVKBuild: String, CaseIterable, Identifiable {
    case v143 = "1.4.3"
    case v128 = "1.2.8"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .v143: return "1.4.3 (default)"
        case .v128: return "1.2.8"
        }
    }

    static let storageKey = "muffin.render.moltenVK"
    static let defaultValue: MoltenVKBuild = .v143
}

/// Renderer, filters, resolution, stretching and gamma. The bridge reads the
/// renderer and filter keys itself before every launch, so those three have no bridge call here.
struct GraphicsSettingsSection: View {
    @AppStorage(RendererAPI.storageKey) private var rendererRaw = RendererAPI.defaultValue.rawValue
    @AppStorage(UpscaleFilterSetting.storageKey) private var upscaleRaw = UpscaleFilterSetting.defaultValue.rawValue
    @AppStorage(DownscaleFilterSetting.storageKey) private var downscaleRaw = DownscaleFilterSetting.defaultValue.rawValue
    @AppStorage(RenderScale.storageKey) private var renderScaleRaw = RenderScale.deviceDefault.rawValue
    @AppStorage(FavourPerformance.storageKey) private var favourPerformance = FavourPerformance.defaultValue
    @AppStorage(FullSpeedRenders.storageKey) private var fullSpeedRenders = FullSpeedRenders.defaultValue
    @AppStorage(FullSpeedRenders.shaderModeKey) private var fullSpeedShaderMode = FullSpeedRenders.defaultShaderMode.rawValue
    @AppStorage(FrameStretch.storageKey) private var frameStretchEnabled = FrameStretch.defaultValue
    @AppStorage(TextureFiltering.storageKey) private var textureFilteringRaw = TextureFiltering.defaultValue.rawValue
    @AppStorage(MoltenVKBuild.storageKey) private var moltenVKRaw = MoltenVKBuild.defaultValue.rawValue
    @AppStorage("muffin.render.upsideDown") private var upsideDownEnabled = false
    @AppStorage(DisplayGammaSetting.storageKey) private var displayGamma = DisplayGammaSetting.defaultValue
    // Default true: matches CemuConfig's framebuffer_fetch default.
    @AppStorage("muffin.render.framebufferFetch") private var framebufferFetchEnabled = true
    // Default false: matches CemuConfig's emulate_missing_effects default.
    @AppStorage("muffin.render.emulateMissingEffects") private var emulateMissingEffects = false
    @AppStorage("muffin.render.overrideAppGamma") private var overrideAppGammaEnabled = false
    @AppStorage(OverrideGammaSetting.storageKey) private var overrideGammaValue = OverrideGammaSetting.defaultValue
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue

    private var advanced: Bool { SettingsMode.isAdvanced(raw: settingsModeRaw) }

    private var renderScale: RenderScale {
        RenderScale(rawValue: renderScaleRaw) ?? RenderScale.deviceDefault
    }

    var body: some View {
        Section {
            // The renderer, filters, Steady frame rate and the picture tweaks are Advanced mode only:
            // Basic keeps them at their defaults (see AdvancedSettings).
            if advanced {
                fullSpeedRendersToggle
                if fullSpeedRenders {
                    fullSpeedShaderPicker
                }
                rendererPicker
                // Only the Vulkan renderer loads MoltenVK, so Metal users have nothing to pick here.
                if rendererRaw == RendererAPI.vulkan.rawValue {
                    moltenVKPicker
                }
                upscalePicker
                downscalePicker
            }
            resolutionPicker
            textureFilteringPicker
            if favourPerformance {
                Text("Favour performance is on (see CPU), so the picture is limited to Balanced resolution with linear scaling.")
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
            stretchToggle
            if advanced {
                upsideDownToggle
                if rendererRaw == RendererAPI.metal.rawValue {
                    framebufferFetchToggle
                    // Devices with mesh shaders draw these effects natively, so there is nothing to switch
                    if meshShadersUnsupported {
                        emulateMissingEffectsToggle
                    }
                }
                gammaSlider
                overrideGammaToggle
                if overrideAppGammaEnabled {
                    overrideGammaSlider
                }
            }
            meshShaderNote
        } header: {
            SettingsSectionHeader("Graphics", icon: "cube.transparent", accent: .core)
        } footer: {
            InfoButton.footer(
                // The renderer picker is Advanced mode only, so Basic doesn't describe it.
                advanced
                    ? "Leave the renderer on Metal unless a game draws wrongly. Changes apply the next time you start a game."
                    : "A lower resolution uses less memory.",
                title: "Graphics",
                text: fullText)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var rendererPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Renderer")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Picker("Renderer", selection: $rendererRaw) {
                ForEach(RendererAPI.allCases) { api in
                    Text(api.title).tag(api.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: rendererRaw) { newValue in
                // Picking Vulkan again is a retry: forget that it failed to start before
                if newValue == RendererAPI.vulkan.rawValue {
                    UserDefaults.standard.removeObject(forKey: "muffin.render.vulkanFailedBuild")
                    UserDefaults.standard.removeObject(forKey: "muffin.render.vulkanFailureReason")
                }
            }
            Text("Metal is the standard. Vulkan is experimental: some games may draw wrongly or crash. If Vulkan fails to start, MuffinEMU goes back to Metal.")
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
            if let reason = UserDefaults.standard.string(forKey: "muffin.render.vulkanFailureReason"), !reason.isEmpty {
                Text("Last Vulkan failure: \(reason)")
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
            if let failedBuild = UserDefaults.standard.string(forKey: "muffin.render.vulkanFailedBuild"),
               rendererRaw == RendererAPI.metal.rawValue {
                Text("Vulkan didn't start with MoltenVK \(failedBuild), so Metal is being used. Choose Vulkan again to retry.")
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
        }
    }

    private var moltenVKPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MoltenVK")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Picker("MoltenVK", selection: $moltenVKRaw) {
                ForEach(MoltenVKBuild.allCases) { build in
                    Text(build.title).tag(build.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text(moltenVKCaption)
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
        }
    }

    // Shows what is running now as well as what is picked; the two differ until the next launch.
    private var moltenVKCaption: String {
        let active = String(cString: cemu_bridge_active_moltenvk())
        if !active.isEmpty && active != moltenVKRaw {
            return "Running \(active) now. \(moltenVKRaw) starts the next time you open MuffinEMU."
        }
        return "Only used with Vulkan. A change applies the next time you open MuffinEMU."
    }

    private var upscalePicker: some View {
        Picker("Filter when enlarging", selection: $upscaleRaw) {
            ForEach(ScaleFilter.allCases) { filter in
                Text(filter.title).tag(filter.rawValue)
            }
        }
        .pickerStyle(.menu)
        .tint(MuffinTheme.accentText)
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var downscalePicker: some View {
        Picker("Filter when shrinking", selection: $downscaleRaw) {
            ForEach(ScaleFilter.allCases) { filter in
                Text(filter.title).tag(filter.rawValue)
            }
        }
        .pickerStyle(.menu)
        .tint(MuffinTheme.accentText)
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var fullSpeedRendersToggle: some View {
        Toggle(isOn: $fullSpeedRenders) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Steady frame rate")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(fullSpeedRenders
                     ? "Shows frames at the game's own speed so motion looks even. Turn on if a game stutters."
                     : "Frames are shown the moment they're ready.")
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
        }
        .tint(MuffinTheme.accentText)
        .onChange(of: fullSpeedRenders) { _ in FullSpeedRenders.applyToBridge() }
    }

    private var fullSpeedShaderPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("First time a new effect appears", selection: $fullSpeedShaderMode) {
                ForEach(FullSpeedRenders.ShaderMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)
            .tint(MuffinTheme.accentText)
            .foregroundColor(MuffinTheme.brownDarkest)
            .onChange(of: fullSpeedShaderMode) { _ in FullSpeedRenders.applyToBridge() }
            Text((FullSpeedRenders.ShaderMode(rawValue: fullSpeedShaderMode) ?? FullSpeedRenders.defaultShaderMode).summary)
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resolutionPicker: some View {
        Picker("Resolution", selection: $renderScaleRaw) {
            ForEach(RenderScale.allCases) { scale in
                Text(scale.title).tag(scale.rawValue)
            }
        }
        .pickerStyle(.menu)
        .tint(MuffinTheme.accentText)
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var textureFilteringPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Texture filtering", selection: $textureFilteringRaw) {
                ForEach(TextureFiltering.allCases) { level in
                    Text(level.title).tag(level.rawValue)
                }
            }
            .pickerStyle(.menu)
            .tint(MuffinTheme.accentText)
            .foregroundColor(MuffinTheme.brownDarkest)
            .onChange(of: textureFilteringRaw) { _ in TextureFiltering.applyToBridge() }
            Text(textureFilteringRaw == TextureFiltering.gameDefault.rawValue
                 ? "Textures are filtered the way each game asks for."
                 : "Textures seen at an angle, like floors and roads, stay sharper further away. Applies to the next frame.")
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
        }
    }

    private var stretchToggle: some View {
        Toggle(isOn: $frameStretchEnabled) {
            Text("Stretch picture to fill the screen")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.accentText)
        .onChange(of: frameStretchEnabled) { newValue in
            cemu_bridge_set_stretch_to_fill(newValue)
        }
    }

    private var upsideDownToggle: some View {
        Toggle(isOn: $upsideDownEnabled) {
            Text("Flip screen upside down")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.accentText)
        .onChange(of: upsideDownEnabled) { newValue in
            cemu_bridge_set_render_upside_down(newValue)
        }
    }

    private var gammaSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Display gamma")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(String(format: "%.1f", displayGamma))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
            Slider(
                value: $displayGamma,
                in: DisplayGammaSetting.minValue...DisplayGammaSetting.maxValue
            )
            .accessibilityLabel("Display gamma")
            .onChange(of: displayGamma) { newValue in
                cemu_bridge_set_display_gamma(Float(newValue))
            }
        }
    }

    // Metal only: MetalRenderer.cpp is the only backend that reads framebuffer_fetch.
    private var framebufferFetchToggle: some View {
        Toggle(isOn: $framebufferFetchEnabled) {
            Text("Fast blending")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.accentText)
        .onChange(of: framebufferFetchEnabled) { newValue in
            cemu_bridge_set_framebuffer_fetch(newValue)
        }
    }

    private var emulateMissingEffectsToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $emulateMissingEffects) {
                Text("Emulate missing effects")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.accentText)
            .onChange(of: emulateMissingEffects) { newValue in
                cemu_bridge_set_emulate_missing_effects(newValue)
            }
            Text("Draws effects your device's graphics chip can't do itself. Experimental. Turn on if a game is missing effects. Applies the next time you start a game.")
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
        }
    }

    private var overrideGammaToggle: some View {
        Toggle(isOn: $overrideAppGammaEnabled) {
            Text("Override the game's gamma")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.accentText)
        .onChange(of: overrideAppGammaEnabled) { newValue in
            cemu_bridge_set_override_app_gamma(newValue)
        }
    }

    private var overrideGammaSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Override gamma value")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(String(format: "%.1f", overrideGammaValue))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
            Slider(
                value: $overrideGammaValue,
                in: OverrideGammaSetting.minValue...OverrideGammaSetting.maxValue
            )
            .accessibilityLabel("Override gamma value")
            .onChange(of: overrideGammaValue) { newValue in
                cemu_bridge_set_override_gamma_value(Float(newValue))
            }
        }
    }

    // Shown only on GPUs without mesh shader support (see MetalRenderer.cpp's mesh-shader gate).
    // GraphicPacksView carries the full note next to the packs it affects.
    private var meshShadersUnsupported: Bool {
        !DeviceCapabilities.current.meshShaders
    }

    @ViewBuilder private var meshShaderNote: some View {
        if meshShadersUnsupported {
            Text("This device can't draw some graphic pack effects correctly. See Graphic packs under Library layout.")
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
        }
    }

    private var fullText: String {
        """
        Steady frame rate shows frames at the game's own speed so motion looks even. Turn it on if a game stutters. The first time a new effect appears, MuffinEMU has to prepare it. Wait for it pauses briefly. Keep going skips the effect once so there is no pause. Either way it is remembered, so this happens only once.

        Renderer: Metal is the standard. Vulkan (through MoltenVK) can work better for some games but may be slower. Changes apply the next time you start a game.

        MoltenVK only matters with Vulkan. 1.4.3 is the default; 1.2.8 is an older version that some games run better on.

        Filters smooth the picture when it is drawn bigger or smaller than the game made it. Bicubic is smooth, Bicubic Hermite is sharper, and Nearest neighbour keeps hard pixel edges.

        Resolution sets how sharp the picture is. Higher looks sharper but needs more power and memory. It applies the next time you start a game.

        \(renderScale.summary)

        Stretch picture to fill the screen removes the black bars by stretching the picture, which distorts it a little. Leave it off to keep the Wii U's 16:9 shape.

        Texture filtering keeps surfaces seen at an angle, like a road ahead or a floor, sharp further into the distance. Game default uses what each game asks for; 2x to 16x raise it. Textures a game draws without smoothing are left alone. It costs little and applies to the next frame.

        There is no VSync switch because iOS already syncs frames to the screen. For even pacing, use Steady frame rate.

        Flip screen upside down is for screens or capture setups that show the picture inverted. Leave it off otherwise.

        Fast blending makes some effects quicker on Metal. It is on by default. Turn it off only if a game looks wrong.

        Display gamma changes how bright the mid-tones look. 2.2 is standard. Lower looks brighter and flatter, higher looks darker with more contrast.

        Override the game's gamma replaces the gamma a game asks for with Override gamma value. Most games don't ask for one, so leave it off unless you know a game needs it.
        """
        + (meshShadersUnsupported ? "\n\nThis device can't draw graphic pack effects that use geometry shaders or post-processing. Everything else works normally." : "")
    }
}
