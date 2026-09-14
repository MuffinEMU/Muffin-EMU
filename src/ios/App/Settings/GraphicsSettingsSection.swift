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

    private var renderScale: RenderScale {
        RenderScale(rawValue: renderScaleRaw) ?? .balanced
    }

    var body: some View {
        Section {
            rendererPicker
            upscalePicker
            downscalePicker
            resolutionPicker
            stretchToggle
            vsyncToggle
            meshShaderNote
        } header: {
            Text("Graphics")
        } footer: {
            InfoButton.footer(
                "Metal is the native, default renderer; Vulkan (MoltenVK) can be more compatible for some titles at some cost to speed, and takes effect on the next launch. Resolution, stretching and VSync change how the picture is presented, not how the game is emulated.",
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

    private var upscalePicker: some View {
        Picker("Upscale filter", selection: $upscaleRaw) {
            ForEach(ScaleFilter.allCases) { filter in
                Text(filter.title).tag(filter.rawValue)
            }
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var downscalePicker: some View {
        Picker("Downscale filter", selection: $downscaleRaw) {
            ForEach(ScaleFilter.allCases) { filter in
                Text(filter.title).tag(filter.rawValue)
            }
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var resolutionPicker: some View {
        Picker("Resolution", selection: $renderScaleRaw) {
            ForEach(RenderScale.allCases) { scale in
                Text(scale.title).tag(scale.rawValue)
            }
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    private var stretchToggle: some View {
        Toggle(isOn: $frameStretchEnabled) {
            Text("Enable Frame Stretching")
        }
        .tint(MuffinTheme.pixelBlue)
        .onChange(of: frameStretchEnabled) { newValue in
            cemu_bridge_set_stretch_to_fill(newValue)
        }
    }

    private var vsyncToggle: some View {
        Toggle(isOn: $vsyncEnabled) {
            Text("VSync")
        }
        .tint(MuffinTheme.pixelBlue)
        .onChange(of: vsyncEnabled) { newValue in
            cemu_bridge_set_vsync_enabled(newValue)
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

        Upscale filter is used when Muffin draws the game's picture larger than the game rendered it; downscale filter is used when drawing it smaller. Bicubic (the upscale default) is smoother than linear; Bicubic Hermite sharpens that further; Nearest Neighbor keeps hard pixel edges with no blending at all. Linear is the downscale default.

        \(renderScale.summary)

        Resolution changes the size of the picture Muffin draws, not the resolution the game runs at - nothing about the emulation changes with it. Takes effect the next time you launch a game.

        Frame stretching fills the screen's own shape instead of keeping the Wii U's 1280x720 proportions, which otherwise letterboxes with bars on two sides. Off keeps the picture undistorted; on trades that for using every pixel. Takes effect on the very next frame.

        VSync paces new frames to the screen's own refresh instead of showing them the instant they're ready, which avoids tearing at the cost of capping how fast the picture can update. On by default. Turn it off only if a game feels laggy behind your input and you'd rather see torn frames sooner than smooth ones later - most titles under this port's current performance won't notice a difference either way. Takes effect on the next launch of a game.

        This device has no mesh shader support, so packs that rely on geometry shaders or post-processing (RECTS) draws won't render correctly yet. Everything else works normally.
        """
    }
}
