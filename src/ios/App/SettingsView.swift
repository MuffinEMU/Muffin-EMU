import SwiftUI
import UIKit
import UniformTypeIdentifiers

private extension Bundle {
    var appVersionString: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

struct SettingsView: View {
    @ObservedObject var gameManager: GameManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingIconPicker = false
    @State private var showingKeysImporter = false
    @State private var showingKeysRemovalConfirmation = false
    @State private var keyCount = WiiUKeys.installedKeyCount()
    @State private var keysErrorMessage: String?
    @State private var premiumUnlocked = PremiumUnlock.isUnlocked
    @State private var premiumCodeInput = ""
    @State private var premiumCodeError: String?
    /// Shared with EmulatorViewOptimized by key, not by binding - the emulator view is
    /// not in this sheet's hierarchy, and AppStorage is what makes the setting outlive
    /// the sheet anyway.
    @AppStorage(LaunchLogSettings.showKey) private var showLaunchLog = true
    @AppStorage("muffin.showLaunchIntro") private var launchIntroEnabled = true
    @State private var deviceReportCopied = false
    /// Computed on demand. The bridge owns the string and it is stable for the
    /// process's lifetime, so there is nothing to refresh and nothing to invalidate.
    private var deviceReport: String { String(cString: cemu_bridge_device_report()) }
    /// Read by DisplayRouter through `RenderScale.current` at surface-registration time,
    /// not observed by it - hence AppStorage here and a plain UserDefaults read there.
    @AppStorage(RenderScale.storageKey) private var renderScaleRaw = RenderScale.balanced.rawValue

    private var renderScale: RenderScale {
        RenderScale(rawValue: renderScaleRaw) ?? .balanced
    }

    /// Defaulted from `TimebaseScale.current` rather than from a fixed case, because the
    /// engine picks this one itself at launch from the CPU mode it actually got (real
    /// time under the recompiler, an eighth under the interpreter). A hardcoded default
    /// here would show a value that is not the one in effect, on the single screen whose
    /// job is to say what is in effect.
    @AppStorage(TimebaseScale.storageKey) private var timebaseRaw = TimebaseScale.current.rawValue
    // Must keep matching GameManager's defaults for the same keys: the engine reads them
    // at title start, and a disagreement here would show a switch in the wrong position.
    @AppStorage("muffin.cpu.recompiler") private var recompilerEnabled = false
    @AppStorage("muffin.cpu.legacyTimebase") private var legacyTimebase = false
    @AppStorage("muffin.shaders.asyncCompile") private var asyncShaderCompile = true
    @AppStorage("muffin.render.reduceEncoderSplitting") private var reduceEncoderSplitting = false
    @AppStorage("muffin.shaders.persistentCache") private var shaderCachePersistenceEnabled = true
    @AppStorage("muffin.render.vsync") private var vsyncEnabled = true
    @AppStorage(FrameStretch.storageKey) private var frameStretchEnabled = FrameStretch.defaultValue
    @State private var learnedCacheBytes: Int64 = 0
    @State private var compiledCacheBytes: Int64 = 0
    @State private var confirmClearLearned = false
    // A real ObservedObject on the shared store, not a second set of @AppStorage vars
    // pointed at the same keys - PreviewPadStore only reads UserDefaults once, at
    // launch, so a separate @AppStorage binding here would write the key correctly but
    // leave the store's own @Published value - the thing the live pad actually reads -
    // stale until relaunch. Binding straight to the store is what makes a change here
    // reach a game already running with the pad on screen.
    @AppStorage(PreviewPadStore.enabledKey) private var previewPadEnabled = false
    @ObservedObject private var previewPad = PreviewPadStore.shared
    @State private var showingLayoutExporter = false
    @State private var showingLayoutImporter = false
    @State private var showingColourExporter = false
    @State private var showingColourImporter = false
    @State private var previewFileErrorMessage: String?

    private var previewLayoutPresetBinding: Binding<String> {
        Binding(get: { previewPad.layoutPreset.rawValue },
               set: { previewPad.layoutPreset = PreviewLayoutPreset(rawValue: $0) ?? .iPadPro2020 })
    }
    private var previewColourPresetBinding: Binding<String> {
        Binding(get: { previewPad.colourPreset.rawValue },
               set: { previewPad.colourPreset = PreviewColourPreset(rawValue: $0) ?? .wiiUWhite })
    }
    private var previewDisplayModeBinding: Binding<String> {
        Binding(get: { previewPad.displayMode.rawValue },
               set: { previewPad.displayMode = PadLayout.DisplayMode(rawValue: $0) ?? .fit })
    }
    private var previewLayoutPreset: PreviewLayoutPreset { previewPad.layoutPreset }
    private var previewColourPreset: PreviewColourPreset { previewPad.colourPreset }

    /// A representative container/safe-area to export against when there is no live game
    /// view to measure - the exact reference profile PreviewLayoutPreset.iPadPro2020
    /// itself captures from, so an export made from Settings and one made mid-game agree.
    private func currentLayoutFile() -> MuffinLayoutFile {
        PreviewPadStore.shared.effectiveLayoutFile(
            container: CGSize(width: 1366, height: 1024),
            safeArea: CGRect(x: 0, y: 0, width: 1366, height: 1004),
            pointsPerInch: 132)
    }

    private func importLayout(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                previewFileErrorMessage = "Couldn't access that file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let file = try MuffinLayoutFile.decode(data)
            PreviewPadStore.shared.applyImportedLayout(file)
        } catch {
            previewFileErrorMessage = "Couldn't import that .muffinlyt file: \(error.localizedDescription)"
        }
    }

    private func importColour(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                previewFileErrorMessage = "Couldn't access that file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            _ = try MuffinColourFile.decode(data)
            // The three shipping presets in this preview are a fixed set (white/black/
            // Super Famicom); a genuinely custom imported palette is what
            // MuffinColourPresets.customStarter and PadColourPickerView exist for in the
            // full colour system - out of scope for this showcase build's 3-preset
            // picker, so this only validates the file rather than pretending to apply it.
            previewFileErrorMessage = "Imported and verified - custom colour slots aren't in this preview build's 3-preset picker yet."
        } catch {
            previewFileErrorMessage = "Couldn't import that .muffinclr file: \(error.localizedDescription)"
        }
    }
    @State private var cacheStatusMessage: String?

    /// Same keys the on-screen pad reads. Moving a cluster is a thing you can only
    /// sensibly do with a game under it, so that lives in the emulator view - but size
    /// and opacity are worth being able to set from here too, and "Reset layout" needs
    /// to be reachable from somewhere that is not itself on top of the pad.
    @AppStorage(ControllerLayoutSettings.scaleKey)
    private var controlScale = ControllerLayoutSettings.defaultScale
    @AppStorage(ControllerLayoutSettings.opacityKey)
    private var controlOpacity = ControllerLayoutSettings.defaultOpacity
    // Must keep matching the declaration in ControllerPad and ContentView: one key with
    // two disagreeing @AppStorage defaults means this toggle and the pad disagree about
    // which control scheme is on.
    @AppStorage(ControllerLayoutSettings.joystickKey)
    private var joystickMode = ControllerLayoutSettings.defaultJoystick
    @AppStorage(ControllerLayoutSettings.deadzoneKey)
    private var stickDeadzone = ControllerLayoutSettings.defaultDeadzone
    @AppStorage(ControllerLayoutSettings.stickCurveKey)
    private var stickCurve = ControllerLayoutSettings.defaultStickCurve
    @AppStorage(ControllerLayoutSettings.stickGateKey)
    private var stickGateRaw = ControllerLayoutSettings.defaultStickGateRaw

    private var stickGate: ControllerGeometry.StickGate {
        ControllerGeometry.StickGate(rawValue: stickGateRaw) ?? ControllerLayoutSettings.defaultStickGate
    }

    private var timebase: TimebaseScale {
        TimebaseScale(rawValue: timebaseRaw) ?? .realTime
    }

    var body: some View {
        // NavigationStack needs iOS 16+; this project's deployment target is 15.0.
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient
                    .ignoresSafeArea()

                Form {
                    Section("Appearance") {
                        Button(action: { showingIconPicker = true }) {
                            Label("App Icon", systemImage: "app.badge")
                        }
                        .foregroundColor(MuffinTheme.brownDarkest)
                    }

                    Section {
                        Toggle(isOn: $joystickMode) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add analog sticks")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Text(joystickMode
                                     ? "Both sticks shown alongside the d-pad and face buttons, not instead of them."
                                     : "Just the d-pad and face buttons, from the measured layout.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Only while the mode they belong to is on. A deadzone slider
                        // under a d-pad is a control with nothing behind it.
                        if joystickMode {
                            // Above the two sliders because it is a different kind of
                            // question: the gate is the shape of the stick, and the
                            // sliders are how that shape is read.
                            VStack(alignment: .leading, spacing: 4) {
                                Picker("Gate", selection: $stickGateRaw) {
                                    ForEach(ControllerGeometry.StickGate.allCases) { gate in
                                        Text(gate.title).tag(gate.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                                Text(stickGate.summary)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Stick deadzone")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    Spacer()
                                    // The number, not just the handle. This is the one
                                    // setting where "how much exactly" is the question
                                    // being asked, and a bare slider cannot answer it.
                                    Text(stickDeadzone <= 0.0005
                                         ? "off"
                                         : "\(Int((stickDeadzone * 100).rounded()))%")
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Slider(
                                    value: $stickDeadzone,
                                    in: ControllerLayoutSettings.minDeadzone...ControllerLayoutSettings.maxDeadzone
                                )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Fine control")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    Spacer()
                                    Text(stickCurve <= ControllerLayoutSettings.minStickCurve + 0.005
                                         ? "linear"
                                         : String(format: "%.1fx", stickCurve))
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Slider(
                                    value: $stickCurve,
                                    in: ControllerLayoutSettings.minStickCurve...ControllerLayoutSettings.maxStickCurve
                                )
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Button size")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            HStack(spacing: 10) {
                                Image(systemName: "minus.magnifyingglass")
                                Slider(
                                    value: $controlScale,
                                    in: ControllerLayoutSettings.minScale...ControllerLayoutSettings.maxScale
                                )
                                Image(systemName: "plus.magnifyingglass")
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Opacity")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            HStack(spacing: 10) {
                                Image(systemName: "circle.lefthalf.filled")
                                Slider(value: $controlOpacity, in: 0.2...1.0)
                                Image(systemName: "circle.fill")
                            }
                        }

                        Button(role: .destructive, action: { ControllerLayoutSettings.reset() }) {
                            Label("Reset layout", systemImage: "arrow.uturn.backward")
                        }
                    } header: {
                        Text("On-screen controls")
                    } footer: {
                        Text("The joystick is analog, like the sticks on the real GamePad: how far you push it is how fast you go, which a d-pad cannot express - it only ever says fully left or nothing. The position your thumb is at is the position the game receives, at full precision and with nothing smoothing it on the way. It takes the d-pad's own footprint, so nothing else on the pad moves, and turning it on also adds a camera stick on the right for the games that look around. Tap the left stick without pushing it to click it in (L3), which is where that button lives in this mode.\n\nThe gate is the shape the stick can reach. The real GamePad's is an octagon, and that is not decoration: only the four cardinals and the four diagonals reach full travel, and the flats between them stop about 8% short - which is the stick Mario Kart's drift and Zelda's walking were tuned against, and the flats are also the only thing telling your thumb where the diagonals are. Round gives the maximum in every direction instead.\n\nDeadzone is how much of the stick around the centre reads as untouched. Everything past it still reaches full speed, so turning it down buys precision near the middle and costs nothing at the top - turn it up only if a resting thumb makes the game drift. Fine control bends the first part of the travel: at linear, halfway is half speed; above it, halfway is slower than half, so small corrections get more of the stick to happen in. Nothing changes at the rim either way.\n\nMuffin picks a button size for the screen it is on and re-picks it whenever that changes, so the pad is already the right size on a phone and on an iPad without being set here. The size and opacity sliders adjust that choice rather than replacing it.\n\nTo move a cluster - either half, or the camera stick - start a game and tap the move button in the top bar; you need the game underneath to judge where the controls should go. The same joystick switch is in that panel.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    // The two things that decide how fast this runs, in the order they
                    // matter. CPU mode first because it is worth more than everything
                    // else combined and it is not a setting - it is decided by HOW the
                    // app was launched, which is exactly why it needs saying here.
                    // Three independent settings that each decide something different -
                    // whether the CPU is recompiled or interpreted, how fast the emulated
                    // clock runs, and when a shader gets built - split into their own
                    // sections rather than one shared block. They used to share a single
                    // "Performance" section, which read as one combined decision when
                    // they are not: Nano Assault Neo needs background shader compilation
                    // OFF while every other tested game wants it on, and that only makes
                    // sense as a real per-setting choice, not a facet of one bundled
                    // toggle. The per-game override for this one lives in the library's
                    // long-press menu, not here - this is the global default it falls
                    // back to.
                    Section {
                        CPUModeRow()

                        // Off by default because it is reported to crash. Two builds in a
                        // row were unusable and neither of us could tell which change did
                        // it without a rebuild per guess.
                        Toggle(isOn: $recompilerEnabled) {
                            Text("Use the recompiler (JIT)")
                        }
                        .tint(MuffinTheme.pixelBlue)
                        .onChange(of: recompilerEnabled) { newValue in
                            cemu_bridge_set_recompiler_enabled(newValue)
                        }
                    } header: {
                        Text("CPU")
                    } footer: {
                        Text("Faster when it works, but a crash in the emulated CPU makes every other problem impossible to judge. Start the game again after changing this.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    Section {
                        Toggle(isOn: $legacyTimebase) {
                            Text("Use the original emulated clock")
                        }
                        .tint(MuffinTheme.pixelBlue)
                        .onChange(of: legacyTimebase) { newValue in
                            cemu_bridge_set_legacy_timebase(newValue)
                        }
                    } header: {
                        Text("Emulated Clock")
                    } footer: {
                        Text("The rewritten clock had an overflow that ran the emulated console 65 times too slow, which made games mistime everything they animate. That is fixed, and the log now prints the clock rate so you can check it. This falls back to the old one anyway if anything still looks wrong.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    Section {
                        Toggle(isOn: $asyncShaderCompile) {
                            Text("Compile shaders in the background")
                        }
                        .tint(MuffinTheme.pixelBlue)
                        .onChange(of: asyncShaderCompile) { newValue in
                            cemu_bridge_set_async_shader_compile(newValue)
                        }
                    } header: {
                        Text("Shader Compilation")
                    } footer: {
                        Text("On, the game keeps running while new shaders are built, and you may see something flicker or appear late the first time it is drawn. Off, the game waits for each one, which stutters instead. Neither can build a shader before the game first uses it - the Wii U only reveals them as it draws.\n\nNano Assault Neo specifically breaks with this on - use its own per-game override (long-press the game in your library) rather than turning this off for everyone.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    // Experimental. Aimed at a specific, unconfirmed hypothesis - see
                    // MetalCommon.h's g_metal_reduceEncoderSplitting - not a proven fix,
                    // which is exactly why this exists as a toggle rather than being
                    // baked in unconditionally: it may help the games that show the
                    // intermittent rainbow/garbage geometry and do nothing for others.
                    // Same per-game override pattern as shader compilation, reachable
                    // from the same long-press "View Game Options" screen.
                    Section {
                        Toggle(isOn: $reduceEncoderSplitting) {
                            Text("Reduce Command-Buffer Splitting")
                        }
                        .tint(MuffinTheme.pixelBlue)
                        .onChange(of: reduceEncoderSplitting) { newValue in
                            cemu_bridge_set_reduce_encoder_splitting(newValue)
                        }
                    } header: {
                        Text("Rendering (Experimental)")
                    } footer: {
                        Text("Off by default. Aimed at intermittent, self-correcting rainbow or garbled geometry that some games show for a few seconds at a time - it restricts when the renderer is allowed to split work across command buffers, which on-device testing suggests may be involved, but this has not been confirmed as the actual cause. Turn it on for a game that shows the glitch; leave it off for games that don't, or that render worse with it on. Set per-game in \"View Game Options\" (long-press the game in your library) to override this default for just that one.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    Section {
                        Toggle(isOn: $shaderCachePersistenceEnabled) {
                            Text("Persistent Shader Cache")
                        }
                        .tint(MuffinTheme.pixelBlue)
                        .onChange(of: shaderCachePersistenceEnabled) { newValue in
                            cemu_bridge_set_shader_cache_persistence(newValue)
                        }

                        // Two buttons, not one. Pressing the first costs a slow launch;
                        // pressing the second throws away something only playing can earn
                        // back, and a single "clear cache" button would hide that.
                        HStack {
                            Text("Compiled shaders")
                            Spacer()
                            Text(Self.formatBytes(compiledCacheBytes)).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Learned shaders")
                            Spacer()
                            Text(Self.formatBytes(learnedCacheBytes)).foregroundColor(.secondary)
                        }
                        Button {
                            let freed = cemu_bridge_clear_shader_cache(0, false)
                            cacheStatusMessage = freed < 0
                                ? "Cannot clear this while a game is running."
                                : "Freed \(Self.formatBytes(freed)). The next launch of each game is slow once, then back to normal."
                            refreshCacheStats()
                        } label: {
                            Label("Clear compiled shaders", systemImage: "arrow.counterclockwise")
                        }
                        Button(role: .destructive) { confirmClearLearned = true } label: {
                            Label("Clear everything, including learned", systemImage: "trash")
                        }
                        if let cacheStatusMessage {
                            Text(cacheStatusMessage)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Picker("Resolution", selection: $renderScaleRaw) {
                            ForEach(RenderScale.allCases) { scale in
                                Text(scale.title).tag(scale.rawValue)
                            }
                        }
                        .foregroundColor(MuffinTheme.brownDarkest)

                        Toggle(isOn: $frameStretchEnabled) {
                            Text("Enable Frame Stretching")
                        }
                        .tint(MuffinTheme.pixelBlue)

                        Toggle(isOn: $vsyncEnabled) {
                            Text("VSync")
                        }
                        .tint(MuffinTheme.pixelBlue)
                        .onChange(of: vsyncEnabled) { newValue in
                            cemu_bridge_set_vsync_enabled(newValue)
                        }
                    } header: {
                        Text("Performance")
                    } footer: {
                        // Says "next launch" because it is true: the scale is baked into
                        // the surface at registration, and a running title's swapchain is
                        // not rebuilt underneath it.
                        Text("Persistent Shader Cache keeps what a game teaches Muffin - every shader and pipeline it's revealed by drawing with it - saved to disk under \"Learned shaders\" below, so the next launch skips recompiling what it already learned instead of starting from zero. On by default; turn it off only to compare launch behaviour with a completely cold cache, or to stop it growing on a title you don't plan to keep. Takes effect on the next launch of a game, not the one already running.\n\n\(renderScale.summary)\n\nResolution changes the size of the picture Muffin draws, not the resolution the game runs at - nothing about the emulation changes with it. Takes effect the next time you launch a game.\n\nFrame stretching fills the screen's own shape instead of keeping the Wii U's 1280x720 proportions, which otherwise letterboxes with bars on two sides. Off keeps the picture undistorted; on trades that for using every pixel. Takes effect on the very next frame.\n\nVSync paces new frames to the screen's own refresh instead of showing them the instant they're ready, which avoids tearing at the cost of capping how fast the picture can update. On by default. Turn it off only if a game feels laggy behind your input and you'd rather see torn frames sooner than smooth ones later - most titles under this port's current performance won't notice a difference either way. Takes effect on the next launch of a game.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    // Its own section rather than a third row under Performance, because
                    // it is not a performance setting and calling it one would be the
                    // wrong idea to give: it makes nothing faster. It is the setting that
                    // decides whether a game that is already running slowly can advance
                    // at all, which is a different question and the one that has actually
                    // been blocking this port.
                    Section {
                        Picker("Speed", selection: $timebaseRaw) {
                            ForEach(TimebaseScale.allCases) { scale in
                                Text(scale.title).tag(scale.rawValue)
                            }
                        }
                        .foregroundColor(MuffinTheme.brownDarkest)
                        // Applied immediately, unlike Resolution: the shift is read per
                        // call inside PPCTimer, so changing it mid-title is safe and the
                        // guest's clock still only ever moves forward. Someone watching a
                        // game sit on one frame can walk down this list and see which
                        // value frees it, without relaunching between each try.
                        .onChange(of: timebaseRaw) { raw in
                            guard let scale = TimebaseScale(rawValue: raw) else { return }
                            TimebaseScale.apply(scale)
                        }
                    } header: {
                        Text("Emulated clock")
                    } footer: {
                        Text("\(timebase.summary)\n\nUntil you pick a value here, Muffin finds one itself: if a game has not reached its graphics handover after twelve seconds it steps its own clock down a notch, as far as 1/64, and the log says which value freed it. Choosing anything on this list stops that search for good and keeps your choice.\n\nThis changes how fast the game believes time is passing, not how fast Muffin runs. Without the recompiler the emulated CPU is far slower than the console's, while the game's own clock keeps up with real time - so every deadline it sets itself is already overdue, and it can spend all its time on overdue work and never draw. Slowing its clock puts those deadlines back in reach. Nothing about the emulation is made less accurate by it, and it takes effect straight away.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    // ON by default, which is the reverse of what shipping software
                    // should do, and deliberate while this port is what it is. The
                    // release notes say it plainly: no Wii U title has been shown to
                    // boot. Until one does, the log is not a diagnostic sitting on top
                    // of the feature - it IS the feature, and the only thing a failed
                    // launch produces that is worth anything.
                    //
                    // The concrete reason it flipped: four builds went out asking for a
                    // boot log and none came back, because seeing one first required
                    // knowing this toggle existed and finding it. On screen it can just
                    // be screenshotted. Turn it off here once a game actually boots.
                    //
                    // The device report, above the diagnostics toggles because it is
                    // the thing to send FIRST when something is wrong.
                    //
                    // MuffinEMU installs on any arm64 iPhone or iPad running iOS 15 or
                    // later, and almost none of those have ever run it. Every finding on
                    // this port so far - no BC texture formats, no mesh shaders, the
                    // memory ceiling - depended on knowing exactly which chip was under
                    // it, and a report from hardware nobody here owns is unanswerable
                    // without that. One tap to copy is the difference between a bug
                    // report that can be acted on and one that cannot.
                    Section {
                        Text(deviceReport)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            UIPasteboard.general.string = deviceReport
                            deviceReportCopied = true
                        } label: {
                            Label(deviceReportCopied ? "Copied" : "Copy device report",
                                  systemImage: deviceReportCopied ? "checkmark" : "doc.on.doc")
                        }
                    } header: {
                        Text("This device")
                    } footer: {
                        Text("Send this with any bug report. It says which chip, how much memory, and which build - which is what makes everything else in a log mean something.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    // Collection is always on regardless (see IOSLiveLog.h) - gating
                    // that too would mean the toggle could only ever show the boot AFTER
                    // the one that failed.
                    //
                    // The intro is deliberately in the same section as the launch log
                    // and directly above it, because they occupy the same screen at the
                    // same moment and turning the log on hides the intro. Putting them
                    // apart would make that look like a bug.
                    Section {
                        Toggle(isOn: $launchIntroEnabled) {
                            Label("Play the launch intro", systemImage: "sparkles")
                        }
                        .tint(MuffinTheme.pixelBlue)

                        Toggle(isOn: $showLaunchLog) {
                            Label("Show launch log", systemImage: "text.alignleft")
                        }
                        .tint(MuffinTheme.pixelBlue)
                    } header: {
                        Text("Diagnostics")
                    } footer: {
                        Text("The intro plays over the boot rather than before it, so it costs no extra waiting. The launch log takes priority when both are on: shows what the emulator is doing, with timestamps, while a game boots, which is what you want when a game starts but the screen stays black.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    // Real Wii U games are encrypted and Muffin ships no keys. This is
                    // where the user supplies their own, dumped from their own console.
                    // Optional by design: without it, everything that worked before -
                    // homebrew, .rpx, anything already decrypted - still works.
                    Section {
                        Button(action: { showingKeysImporter = true }) {
                            Label(WiiUKeys.keysFileExists() ? "Replace keys.txt" : "Import keys.txt",
                                  systemImage: "key")
                        }
                        .foregroundColor(MuffinTheme.brownDarkest)

                        if WiiUKeys.keysFileExists() {
                            SettingsRow(label: "Keys loaded", value: "\(keyCount)")
                            Button(role: .destructive, action: { showingKeysRemovalConfirmation = true }) {
                                Label("Remove keys.txt", systemImage: "trash")
                            }
                        }
                    } header: {
                        Text("Wii U keys")
                    } footer: {
                        Text("Optional. Encrypted games (.wux, .wud, .iso, .wua) need the AES keys dumped from your own Wii U, in a plain text file called keys.txt - one key per line. Muffin ships no keys and can't obtain them. Homebrew and already-decrypted dumps need none of this.\n\nYou can also skip this button entirely: open Muffin in the Files app and drop keys.txt straight into the \"keys\" folder. It's picked up on the next launch, no restart needed.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    Section("Library") {
                        SettingsRow(label: "Games", value: "\(gameManager.games.count)")
                        SettingsRow(label: "Favorites", value: "\(gameManager.favorites.count)")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    // Computed live rather than written down, for the same reason
                    // BootFailureView's crash-log hint is: only the OS knows what $HOME
                    // actually resolved to for this install, and that differs between a
                    // normal signed install and a sideloaded one. The Wii U keys section
                    // above already tells someone to "open Muffin in the Files app" -
                    // this is the exact path that instruction means, spelled out, so it
                    // is followable rather than a folder name to guess at.
                    Section {
                        Text(Self.documentsPathHint)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    } header: {
                        Text("Your Files")
                    } footer: {
                        Text("ROMs, saves, shader caches and keys.txt all live in this folder. Installed normally, it shows up as Files \u{2192} On My iPhone/iPad \u{2192} Muffin. Sideloaded through LiveContainer, iOS attributes the folder to LiveContainer instead of to Muffin by name, so look for it under LiveContainer's own Documents, or one level into Data/Application/<its folder>/Documents - the path above is the one to actually search for.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    // Off by default. Everything above and below this section is the
                    // shipping app, unaffected by whatever is chosen here - see
                    // EmulatorViewOptimized's branch on PreviewPadStore.enabledKey for
                    // exactly what turning this on changes and what stays untouched.
                    Section {
                        Toggle(isOn: $previewPadEnabled) {
                            Text("Use the new pad system")
                        }
                        .tint(MuffinTheme.pixelBlue)

                        if previewPadEnabled {
                            Picker("Layout", selection: previewLayoutPresetBinding) {
                                ForEach(PreviewLayoutPreset.allCases) { preset in
                                    Text(preset.title).tag(preset.rawValue)
                                }
                            }
                            Text(previewLayoutPreset.summary)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)

                            Picker("Colours", selection: previewColourPresetBinding) {
                                ForEach(PreviewColourPreset.allCases) { preset in
                                    Text(preset.file.name).tag(preset.rawValue)
                                }
                            }

                            Picker("Picture", selection: previewDisplayModeBinding) {
                                Text("Fit").tag(PadLayout.DisplayMode.fit.rawValue)
                                Text("Native").tag(PadLayout.DisplayMode.native.rawValue)
                            }
                            .pickerStyle(.segmented)

                            Button(role: .destructive) {
                                PreviewPadStore.shared.resetAdjustments()
                            } label: {
                                Label("Reset dragged/resized groups", systemImage: "arrow.counterclockwise")
                            }

                            Button {
                                showingLayoutExporter = true
                            } label: {
                                Label("Export layout (.muffinlyt)", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                showingLayoutImporter = true
                            } label: {
                                Label("Import layout (.muffinlyt)", systemImage: "square.and.arrow.down")
                            }
                            Button {
                                showingColourExporter = true
                            } label: {
                                Label("Export colours (.muffinclr)", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                showingColourImporter = true
                            } label: {
                                Label("Import colours (.muffinclr)", systemImage: "square.and.arrow.down")
                            }
                        }
                    } header: {
                        Text("Preview: New Pad System")
                    } footer: {
                        Text("Every group - both shoulders, both sticks, the d-pad, A/B/X/Y, Start, Select, HOME - can be dragged and pinch-resized once this is on: tap the move icon in the top bar during a game, the same way the shipping pad's edit mode works.\n\nFit fills the screen with controls floating on top. Native sizes the picture to whatever the clusters leave room for and never lets a control cover it - small and letterboxed on a phone, life-size and framed on an iPad.\n\nThis has not run on a real device yet. If something looks wrong, turn it back off - nothing else in the app depends on it.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)
                    .fileExporter(isPresented: $showingLayoutExporter,
                                 document: MuffinLayoutDocument(currentLayoutFile()),
                                 contentType: .muffinLayout,
                                 defaultFilename: previewLayoutPreset.title) { _ in }
                    .fileImporter(isPresented: $showingLayoutImporter, allowedContentTypes: [.muffinLayout]) { result in
                        importLayout(result)
                    }
                    .fileExporter(isPresented: $showingColourExporter,
                                 document: MuffinColourDocument(previewColourPreset.file),
                                 contentType: .muffinColour,
                                 defaultFilename: previewColourPreset.file.name) { _ in }
                    .fileImporter(isPresented: $showingColourImporter, allowedContentTypes: [.muffinColour]) { result in
                        importColour(result)
                    }
                    .alert("Preview pad files", isPresented: .constant(previewFileErrorMessage != nil),
                          presenting: previewFileErrorMessage) { _ in
                        Button("OK") { previewFileErrorMessage = nil }
                    } message: { message in
                        Text(message)
                    }

                    Section("Premium") {
                        if premiumUnlocked {
                            Label("Premium unlocked", systemImage: "sparkles")
                                .foregroundColor(MuffinTheme.brownDarkest)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Unlock code", text: $premiumCodeInput)
                                    #if os(iOS)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled(true)
                                    #endif
                                Button("Unlock") {
                                    if PremiumUnlock.attemptUnlock(code: premiumCodeInput) {
                                        premiumUnlocked = true
                                        premiumCodeInput = ""
                                        premiumCodeError = nil
                                    } else {
                                        premiumCodeError = "That code didn't work."
                                    }
                                }
                                .disabled(premiumCodeInput.isEmpty)
                                if let premiumCodeError {
                                    Text(premiumCodeError)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    Section("About") {
                        SettingsRow(label: "Version", value: Bundle.main.appVersionString)
                        Link(destination: URL(string: "https://github.com/bward-dev1/cemu-ios-muffin")!) {
                            Label("View on GitHub", systemImage: "arrow.up.right.square")
                        }
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView()
            }
            // .item for the same reason the ROM picker uses it: a keys.txt exported by
            // some other tool may carry no useful type at all, and a type filter would
            // grey out the one file this button exists to select. WiiUKeys.importKeys
            // decides what it actually is, by reading it.
            .fileImporter(
                isPresented: $showingKeysImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleKeysImport(result)
            }
            .alert("Couldn't import keys", isPresented: .constant(keysErrorMessage != nil), presenting: keysErrorMessage) { _ in
                Button("OK") { keysErrorMessage = nil }
            } message: { message in
                Text(message)
            }
            .alert("Remove keys.txt?", isPresented: $showingKeysRemovalConfirmation) {
                Button("Remove", role: .destructive) {
                    try? WiiUKeys.removeKeys()
                    keyCount = WiiUKeys.installedKeyCount()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Encrypted games won't run until you import a keys.txt again. Homebrew is unaffected.")
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { refreshCacheStats() }
        .confirmationDialog("Clear learned shaders too?", isPresented: $confirmClearLearned, titleVisibility: .visible) {
            Button("Clear everything", role: .destructive) {
                let freed = cemu_bridge_clear_shader_cache(0, true)
                cacheStatusMessage = freed < 0
                    ? "Cannot clear this while a game is running."
                    : "Freed \(Self.formatBytes(freed)). Games will stutter while they relearn their shaders."
                refreshCacheStats()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone by pressing a button - each game only relearns its shaders by being played again.")
        }
    }

    private func refreshCacheStats() {
        var learned: Int64 = 0
        var compiled: Int64 = 0
        _ = cemu_bridge_shader_cache_stats(0, &learned, &compiled)
        learnedCacheBytes = learned
        compiledCacheBytes = compiled
    }

    /// The real on-device path to Documents/, same computed-not-written-down reasoning as
    /// BootFailureView.crashLogHint above it.
    private static var documentsPathHint: String {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return "Could not resolve a Documents folder for this install."
        }
        return url.path
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "none" }
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 { value /= 1024; unit += 1 }
        return unit == 0 ? "\(Int(value)) B" : String(format: "%.1f %@", value, units[unit])
    }

    private func handleKeysImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                keyCount = try WiiUKeys.importKeys(from: url)
            } catch {
                keysErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            keysErrorMessage = error.localizedDescription
        }
    }
}

/// Reports whether this launch got the PPC recompiler or the interpreter, and why.
///
/// This exists because the answer was previously only obtainable by pulling
/// CemuCrashLog.txt off the device and reading a cs_flags hex value out of it - an absurd
/// thing to ask of someone whose actual question is "did launching through StikJIT do
/// anything". The bridge decides this once at engine init, so a plain `let` read in
/// `init` is correct; there is no path that changes it while this sheet is open.
private struct CPUModeRow: View {
    private let mode = cemu_bridge_cpu_mode()
    private let detail = String(cString: cemu_bridge_cpu_mode_detail())

    private var title: String {
        switch mode {
        case 2:  return "Recompiler (JIT)"
        case 1:  return "Interpreter (3 cores)"
        default: return "Not decided yet"
        }
    }

    private var tint: Color {
        // Amber rather than red for the interpreter: it is slow, but it is a working,
        // correct emulator, and it is the state every launch has been in so far. Red
        // would be claiming something is broken when nothing is.
        switch mode {
        case 2:  return MuffinTheme.pixelBlue
        case 1:  return .orange
        default: return MuffinTheme.brownMid
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CPU")
                Spacer()
                Text(title)
                    .foregroundColor(tint)
            }
            Text(detail)
                .font(.footnote)
                .foregroundColor(MuffinTheme.brownMid)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// LabeledContent needs iOS 16+; this project's deployment target is 15.0.
private struct SettingsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(MuffinTheme.brownMid)
        }
    }
}
