import SwiftUI

/// Which graphics API the engine draws through. Metal is this port's own native
/// backend and the one every device here has been tested against; Vulkan runs
/// through MoltenVK's translation layer instead, which exists for the compatibility
/// cases Metal doesn't cover rather than as an equal alternative.
///
/// Declared metal-then-vulkan (not in rawValue order) so `.allCases` puts the native
/// default first in the segmented control - CaseIterable follows declaration order,
/// not rawValue order.
enum RendererAPI: Int, CaseIterable, Identifiable {
    case metal = 2
    case vulkan = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .metal:  return "Metal"
        case .vulkan: return "Vulkan (MoltenVK)"
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
        case .nearestNeighbor: return "Nearest Neighbor"
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

/// Backs cemu_bridge_set_display_gamma(). The bridge itself also accepts exactly 0 to
/// mean sRGB (see CemuBridge.h), but this settings page only ever offers a real gamma
/// value in the 1.0-3.0 range the bridge clamps to - there is no on-screen way to send
/// 0 from here, so this app's own effective floor is 1.0, not sRGB. minValue/maxValue
/// mirror the bridge's own clamp so the slider can never show a position the push would
/// silently correct out from under it.
enum DisplayGammaSetting {
    static let storageKey = "muffin.render.displayGamma"
    // Double, not Float: @AppStorage has no Float overload (Bool/Int/Double/String/URL/
    // Data and RawRepresentable-over-those only) - Float compiles as a plain property
    // with no error until Xcode's real type-checker sees it, which nothing in this
    // environment runs. cemu_bridge_set_display_gamma still takes the C `float` the
    // engine expects; the one call site converts explicitly.
    static let defaultValue: Double = 2.2
    static let minValue: Double = 1.0
    static let maxValue: Double = 3.0
}

/// Backs cemu_bridge_set_override_gamma_value() - a separate gamma stage from Display
/// Gamma above, not a second control for the same value. See that function's doc comment
/// in CemuBridge.h for what actually differs: this one replaces or adds to a game's own
/// gamma request, Display Gamma is applied on top of the result. Same Double-not-Float and
/// 1.0-3.0 reasoning as DisplayGammaSetting.
enum OverrideGammaSetting {
    static let storageKey = "muffin.render.overrideGammaValue"
    static let defaultValue: Double = 2.2 // matches CemuConfig's overrideGammaValue default
    static let minValue: Double = 1.0
    static let maxValue: Double = 3.0
}

/// Which MoltenVK build the Vulkan renderer loads: 1.4.3 by default, or 1.2.8,
/// the build 64Touch uses. The bridge reads the key once when the engine starts, because a
/// loaded MoltenVK cannot be swapped inside a running process.
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

/// Renderer, filters, resolution, stretching and VSync - everything that decides
/// how the finished picture is drawn and presented, in one section. The bridge
/// reads muffin.render.graphicsAPI/upscaleFilter/downscaleFilter itself before
/// every launch, the same way GameManager already pushes recompiler/favourAccuracy/
/// vsync/stretch - so this view only owns the @AppStorage and the picker, with no
/// bridge call of its own for those three keys.
struct GraphicsSettingsSection: View {
    @AppStorage(RendererAPI.storageKey) private var rendererRaw = RendererAPI.defaultValue.rawValue
    @AppStorage(UpscaleFilterSetting.storageKey) private var upscaleRaw = UpscaleFilterSetting.defaultValue.rawValue
    @AppStorage(DownscaleFilterSetting.storageKey) private var downscaleRaw = DownscaleFilterSetting.defaultValue.rawValue
    @AppStorage(RenderScale.storageKey) private var renderScaleRaw = RenderScale.balanced.rawValue
    @AppStorage("muffin.render.vsync") private var vsyncEnabled = true
    @AppStorage(FrameStretch.storageKey) private var frameStretchEnabled = FrameStretch.defaultValue
    @AppStorage(MoltenVKBuild.storageKey) private var moltenVKRaw = MoltenVKBuild.defaultValue.rawValue
    @AppStorage("muffin.render.upsideDown") private var upsideDownEnabled = false
    @AppStorage(DisplayGammaSetting.storageKey) private var displayGamma = DisplayGammaSetting.defaultValue
    // Default true: matches CemuConfig's framebuffer_fetch{true} compiled-in default, same
    // "don't show a switch in a position the engine isn't actually in" reasoning as every
    // other @AppStorage default on this page.
    @AppStorage("muffin.render.framebufferFetch") private var framebufferFetchEnabled = true
    @AppStorage("muffin.render.overrideAppGamma") private var overrideAppGammaEnabled = false
    @AppStorage(OverrideGammaSetting.storageKey) private var overrideGammaValue = OverrideGammaSetting.defaultValue

    private var renderScale: RenderScale {
        RenderScale(rawValue: renderScaleRaw) ?? .balanced
    }

    var body: some View {
        Section {
            rendererPicker
            moltenVKPicker
            upscalePicker
            downscalePicker
            resolutionPicker
            stretchToggle
            vsyncToggle
            upsideDownToggle
            if rendererRaw == RendererAPI.metal.rawValue {
                framebufferFetchToggle
            }
            gammaSlider
            overrideGammaToggle
            if overrideAppGammaEnabled {
                overrideGammaSlider
            }
            meshShaderNote
        } header: {
            SettingsSectionHeader("Graphics", icon: "cube.transparent", accent: .core)
        } footer: {
            InfoButton.footer(
                "Metal is the native, default renderer; Vulkan (MoltenVK) can be more compatible for some titles at some cost to speed, and takes effect on the next launch. Resolution, stretching, VSync, screen flip and gamma change how the picture is presented, not how the game is emulated.",
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
                .foregroundColor(.secondary)
        }
    }

    // Says what is running now as well as what is picked, because the two differ until the
    // next launch and a switch that looks like it did nothing is worse than no switch.
    private var moltenVKCaption: String {
        let active = String(cString: cemu_bridge_active_moltenvk())
        if !active.isEmpty && active != moltenVKRaw {
            return "Running \(active) now. \(moltenVKRaw) is used from the next launch of MuffinEMU."
        }
        return "Used by the Vulkan renderer only. A change applies the next time MuffinEMU launches."
    }

    private var upscalePicker: some View {
        Picker("Upscale filter", selection: $upscaleRaw) {
            ForEach(ScaleFilter.allCases) { filter in
                Text(filter.title).tag(filter.rawValue)
            }
        }
        .pickerStyle(.menu)
        .tint(MuffinTheme.pixelBlue)
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var downscalePicker: some View {
        Picker("Downscale filter", selection: $downscaleRaw) {
            ForEach(ScaleFilter.allCases) { filter in
                Text(filter.title).tag(filter.rawValue)
            }
        }
        .pickerStyle(.menu)
        .tint(MuffinTheme.pixelBlue)
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var resolutionPicker: some View {
        Picker("Resolution", selection: $renderScaleRaw) {
            ForEach(RenderScale.allCases) { scale in
                Text(scale.title).tag(scale.rawValue)
            }
        }
        .pickerStyle(.menu)
        .tint(MuffinTheme.pixelBlue)
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var stretchToggle: some View {
        Toggle(isOn: $frameStretchEnabled) {
            Text("Enable Frame Stretching")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.pixelBlue)
        .onChange(of: frameStretchEnabled) { newValue in
            cemu_bridge_set_stretch_to_fill(newValue)
        }
    }

    private var vsyncToggle: some View {
        Toggle(isOn: $vsyncEnabled) {
            Text("VSync")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.pixelBlue)
        .onChange(of: vsyncEnabled) { newValue in
            cemu_bridge_set_vsync_enabled(newValue)
        }
    }

    private var upsideDownToggle: some View {
        Toggle(isOn: $upsideDownEnabled) {
            Text("Flip Screen Upside Down")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.pixelBlue)
        .onChange(of: upsideDownEnabled) { newValue in
            cemu_bridge_set_render_upside_down(newValue)
        }
    }

    private var gammaSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Display Gamma")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(String(format: "%.1f", displayGamma))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Slider(
                value: $displayGamma,
                in: DisplayGammaSetting.minValue...DisplayGammaSetting.maxValue
            )
            .onChange(of: displayGamma) { newValue in
                cemu_bridge_set_display_gamma(Float(newValue))
            }
        }
    }

    // Metal only: MetalRenderer.cpp is the only backend that reads framebuffer_fetch, so a
    // toggle shown under Vulkan would be a switch that moves and changes nothing - the same
    // reason precompiled_shaders (a real CemuConfig field, but inert on this core's Metal/
    // Vulkan backends) is not exposed anywhere on this page either.
    private var framebufferFetchToggle: some View {
        Toggle(isOn: $framebufferFetchEnabled) {
            Text("Framebuffer Fetch")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.pixelBlue)
        .onChange(of: framebufferFetchEnabled) { newValue in
            cemu_bridge_set_framebuffer_fetch(newValue)
        }
    }

    private var overrideGammaToggle: some View {
        Toggle(isOn: $overrideAppGammaEnabled) {
            Text("Override App Gamma")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.pixelBlue)
        .onChange(of: overrideAppGammaEnabled) { newValue in
            cemu_bridge_set_override_app_gamma(newValue)
        }
    }

    private var overrideGammaSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Override Gamma")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(String(format: "%.1f", overrideGammaValue))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Slider(
                value: $overrideGammaValue,
                in: OverrideGammaSetting.minValue...OverrideGammaSetting.maxValue
            )
            .onChange(of: overrideGammaValue) { newValue in
                cemu_bridge_set_override_gamma_value(Float(newValue))
            }
        }
    }

    // A real, current hardware limitation, not a hedge - see MetalRenderer.cpp's
    // mesh-shader gate. GraphicPacksView carries the full version of this note
    // where it actually matters (right next to the packs it affects); this is the
    // same fact surfaced here too, because "three screens deep" is too deep for the
    // first place someone would look for why a pack isn't rendering.
    private var meshShaderNote: some View {
        Text("This device has no mesh shader support yet, so some graphic packs won't render fully correctly - see Graphic Packs under Library.")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
    }

    private var fullText: String {
        """
        Metal is the native rendering path this port is built on and the default. Vulkan (MoltenVK) runs through a translation layer instead and can be more compatible for some titles, at some cost to speed. Takes effect the next time you launch a game.

        MoltenVK is the layer that turns Vulkan into Metal, so it only matters with the Vulkan renderer. 1.4.3 is the default; 1.2.8 is the build 64Touch uses. Only one can be loaded per launch, so a change applies the next time MuffinEMU starts.

        Upscale filter is used when MuffinEMU draws the game's picture larger than the game rendered it; downscale filter is used when drawing it smaller. Bicubic (the upscale default) is smoother than linear; Bicubic Hermite sharpens that further; Nearest Neighbor keeps hard pixel edges with no blending at all. Linear is the downscale default.

        \(renderScale.summary)

        Resolution changes the size of the picture MuffinEMU draws, not the resolution the game runs at - nothing about the emulation changes with it. Takes effect the next time you launch a game.

        Frame stretching fills the screen's own shape instead of keeping the Wii U's 1280x720 proportions, which otherwise letterboxes with bars on two sides. Off keeps the picture undistorted; on trades that for using every pixel. Takes effect on the very next frame.

        VSync paces new frames to the screen's own refresh instead of showing them the instant they're ready, which avoids tearing at the cost of capping how fast the picture can update. On by default. Turn it off only if a game feels laggy behind your input and you'd rather see torn frames sooner than smooth ones later - most titles under this port's current performance won't notice a difference either way. Takes effect on the next launch of a game.

        Flip screen upside down inverts both Wii U outputs vertically before they reach the screen. Off for everyone except a panel or capture rig that presents the image inverted. Takes effect on the next frame.

        Framebuffer fetch lets eligible Metal shaders read a pixel already sitting in the framebuffer instead of a separate blend pass - on by default, Metal only, and takes effect the next time you launch a game.

        Display gamma adjusts how bright midtones look without changing pure black or pure white. 2.2 is the conventional display gamma and this port's default; lower looks flatter and brighter in the mids, higher looks more contrasty and darker in the mids. Takes effect on the next frame.

        Override App Gamma and Override Gamma are a separate stage from Display Gamma above, not a second copy of it: some games ask for their own gamma value, and this either adds Override Gamma on top of that request (off) or replaces the game's request with Override Gamma entirely (on) - before Display Gamma is applied to the result. Off by default; most games never ask for a specific gamma at all, so this has nothing to override until one does.

        This device has no mesh shader support, so packs that rely on geometry shaders or post-processing (RECTS) draws won't render correctly yet. Everything else works normally.
        """
    }
}
