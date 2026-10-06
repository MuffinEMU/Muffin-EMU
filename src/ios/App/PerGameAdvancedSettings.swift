import SwiftUI

/// Per-game options that exist in Advanced mode only (see AdvancedSettings): Resolution, scaling
/// filters, Favour performance, Steady frame rate, One-core mode, screen layout, controller auto-hide
/// and the performance overlay. Each follows the matching global setting until a game is given its own
/// value. The values live in GameOverrides (PerGameSettings.swift); this file reads them back.
///
/// Every `effective...` function ends up in GameManager's launch push and TitleSwitchSettings.apply,
/// like the three older per-game options, and ignores the Advanced ones while Settings mode is Basic.
extension PerGameSettingsStore {
    /// Changes one game's overrides in place. Setting a field back to nil follows the global setting again.
    func updateOverrides(for gameID: String, _ change: (inout GameOverrides) -> Void) {
        var next = overrides(for: gameID)
        change(&next)
        setOverrides(next, for: gameID)
    }

    // MARK: Global values, read the way GameManager reads them

    var globalFavourPerformance: Bool {
        UserDefaults.standard.object(forKey: FavourPerformance.storageKey) as? Bool ?? FavourPerformance.defaultValue
    }

    var globalFullSpeedRenders: Bool {
        UserDefaults.standard.object(forKey: FullSpeedRenders.storageKey) as? Bool ?? FullSpeedRenders.defaultValue
    }

    var globalFullSpeedShaderMode: FullSpeedRenders.ShaderMode {
        FullSpeedRenders.ShaderMode(rawValue: UserDefaults.standard.object(forKey: FullSpeedRenders.shaderModeKey) as? Int
            ?? FullSpeedRenders.defaultShaderMode.rawValue) ?? FullSpeedRenders.defaultShaderMode
    }

    var globalOneCoreMode: Bool {
        UserDefaults.standard.object(forKey: OneCoreMode.storageKey) as? Bool ?? OneCoreMode.defaultValue
    }

    var globalUpscaleFilter: ScaleFilter {
        ScaleFilter(rawValue: UserDefaults.standard.object(forKey: UpscaleFilterSetting.storageKey) as? Int
            ?? UpscaleFilterSetting.defaultValue.rawValue) ?? UpscaleFilterSetting.defaultValue
    }

    var globalDownscaleFilter: ScaleFilter {
        ScaleFilter(rawValue: UserDefaults.standard.object(forKey: DownscaleFilterSetting.storageKey) as? Int
            ?? DownscaleFilterSetting.defaultValue.rawValue) ?? DownscaleFilterSetting.defaultValue
    }

    var globalScreenLayout: ScreenLayout { ScreenLayout.initialValue }

    var globalAutoHideControls: Bool {
        UserDefaults.standard.object(forKey: ControllerLayoutSettings.autoHideWithControllerKey) as? Bool
            ?? ControllerLayoutSettings.defaultAutoHideWithController
    }

    var globalOverlayPosition: ScreenPosition {
        ScreenPosition(rawValue: UserDefaults.standard.object(forKey: OverlaySettings.positionKey) as? Int
            ?? OverlaySettings.defaultPosition.rawValue) ?? OverlaySettings.defaultPosition
    }

    // MARK: What a launch uses: the game's own value first, the global one underneath

    func effectiveRenderScale(for gameID: String) -> RenderScale {
        activeOverrides(for: gameID).renderScale.flatMap(RenderScale.init(rawValue:)) ?? RenderScale.storedChoice
    }

    func effectiveUpscaleFilter(for gameID: String) -> ScaleFilter {
        activeOverrides(for: gameID).upscaleFilter.flatMap(ScaleFilter.init(rawValue:)) ?? globalUpscaleFilter
    }

    func effectiveDownscaleFilter(for gameID: String) -> ScaleFilter {
        activeOverrides(for: gameID).downscaleFilter.flatMap(ScaleFilter.init(rawValue:)) ?? globalDownscaleFilter
    }

    func effectiveFavourPerformance(for gameID: String) -> Bool {
        activeOverrides(for: gameID).favourPerformance ?? globalFavourPerformance
    }

    func effectiveFullSpeedRenders(for gameID: String) -> Bool {
        activeOverrides(for: gameID).fullSpeedRenders ?? globalFullSpeedRenders
    }

    func effectiveFullSpeedShaderMode(for gameID: String) -> FullSpeedRenders.ShaderMode {
        activeOverrides(for: gameID).fullSpeedShaderMode.flatMap(FullSpeedRenders.ShaderMode.init(rawValue:))
            ?? globalFullSpeedShaderMode
    }

    func effectiveOneCoreMode(for gameID: String) -> Bool {
        activeOverrides(for: gameID).oneCoreMode ?? globalOneCoreMode
    }

    /// The overlay's corner for this game. Off turns it off; On uses the corner chosen in Settings, or top
    /// left when Settings has the overlay off.
    func effectiveOverlayPosition(for gameID: String) -> ScreenPosition {
        switch activeOverrides(for: gameID).performanceOverlay {
        case .none:        return globalOverlayPosition
        case .some(false): return .disabled
        case .some(true):  return globalOverlayPosition == .disabled ? .topLeft : globalOverlayPosition
        }
    }

    /// The two filters a launch pushes (upscale, downscale). Favour performance swaps both for linear, the
    /// cheapest blend, unless the game favours accuracy, which wins as it does in the bridge.
    func filtersToPush(for gameID: String) -> (upscale: Int32, downscale: Int32) {
        if effectiveFavourPerformance(for: gameID) && !effectiveFavourAccuracy(for: gameID) {
            return (Int32(ScaleFilter.linear.rawValue), Int32(ScaleFilter.linear.rawValue))
        }
        return (Int32(effectiveUpscaleFilter(for: gameID).rawValue), Int32(effectiveDownscaleFilter(for: gameID).rawValue))
    }

    /// Pushes Steady frame rate for this game (both the switch and the shader choice).
    func applyFullSpeedRenders(for gameID: String) {
        cemu_bridge_set_full_speed_renders(effectiveFullSpeedRenders(for: gameID),
                                           Int32(effectiveFullSpeedShaderMode(for: gameID).rawValue))
    }
}

/// The per-game "Advanced" block on a game's options screen. Hidden in Basic mode.
struct AdvancedGameOptionsSection: View {
    let game: GameMetadata
    @ObservedObject var store: PerGameSettingsStore
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue
    @State private var confirmReset = false

    /// Three real states, like the shader override: following Settings has to be a choice you can go back to.
    private enum Choice: String, CaseIterable, Identifiable {
        case useGlobalDefault, on, off
        var id: String { rawValue }
        var title: String {
            switch self {
            case .useGlobalDefault: return "Use Global Default"
            case .on: return "On"
            case .off: return "Off"
            }
        }
    }

    private var gameKey: String { game.settingsKey }
    private var own: GameOverrides { store.overrides(for: gameKey) }

    // MARK: Bindings

    private func toggleChoice(_ path: WritableKeyPath<GameOverrides, Bool?>) -> Binding<Choice> {
        Binding(
            get: {
                switch store.overrides(for: gameKey)[keyPath: path] {
                case .none: return .useGlobalDefault
                case .some(true): return .on
                case .some(false): return .off
                }
            },
            set: { choice in
                store.updateOverrides(for: gameKey) { next in
                    switch choice {
                    case .useGlobalDefault: next[keyPath: path] = nil
                    case .on: next[keyPath: path] = true
                    case .off: next[keyPath: path] = false
                    }
                }
            })
    }

    /// "" is Use Global Default, otherwise the value's own raw string.
    private func textChoice(_ path: WritableKeyPath<GameOverrides, String?>, known: [String]) -> Binding<String> {
        Binding(
            get: {
                guard let raw = store.overrides(for: gameKey)[keyPath: path], known.contains(raw) else { return "" }
                return raw
            },
            set: { raw in store.updateOverrides(for: gameKey) { $0[keyPath: path] = raw.isEmpty ? nil : raw } })
    }

    /// -1 is Use Global Default, otherwise the value's own raw number.
    private func numberChoice(_ path: WritableKeyPath<GameOverrides, Int?>, known: [Int]) -> Binding<Int> {
        Binding(
            get: {
                guard let raw = store.overrides(for: gameKey)[keyPath: path], known.contains(raw) else { return -1 }
                return raw
            },
            set: { raw in store.updateOverrides(for: gameKey) { $0[keyPath: path] = raw < 0 ? nil : raw } })
    }

    private func caption(pinned: Bool, settingsValue: String) -> String {
        pinned
            ? "Set for this game only. Settings has it \(settingsValue)."
            : "Follows Settings, which has it \(settingsValue)."
    }

    private func onOff(_ value: Bool) -> String { value ? "on" : "off" }

    // MARK: Body

    var body: some View {
        if SettingsMode.isAdvanced(raw: settingsModeRaw) {
            Section {
                graphicsRows
                performanceRows
                screenRows
                resetButton
            } header: {
                SettingsSectionHeader("Advanced", icon: "slider.horizontal.3", accent: .core)
            } footer: {
                InfoButton.footer(
                    "Extra options for this game only. \"Use Global Default\" follows Settings. They apply the next time you start the game.",
                    title: "Advanced game options",
                    text: "Each option here follows the matching setting in Settings until you give this game its own value, and then keeps it whatever Settings says.\n\nResolution and the two scaling filters change how the picture is drawn for this game. Favour performance, Steady frame rate and One-core mode work as they do in Settings, for this game only.\n\nScreen layout and Hide on-screen controls when a controller is connected are put in place when the game starts, and your own choices come back when it stops. A layout change you make during the game is not kept.\n\nPerformance overlay turns the readout on or off for this game. On uses the corner chosen in Settings, or the top left if Settings has it off.\n\nReset this game's options puts every option for this game, in this screen and the one above, back on Settings.")
            }
            .confirmationDialog("Reset this game's options?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { store.clearOverrides(for: gameKey) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\(game.title) goes back to following Settings for everything.")
            }
        }
    }

    // MARK: Rows

    @ViewBuilder private var graphicsRows: some View {
        AdvancedOverrideRow(
            title: "Resolution",
            caption: caption(pinned: own.renderScale != nil, settingsValue: "set to \(RenderScale.storedChoice.title)"),
            selection: textChoice(\.renderScale, known: RenderScale.allCases.map(\.rawValue))
        ) {
            Text("Use Global Default").tag("")
            ForEach(RenderScale.allCases) { scale in
                Text(scale.title).tag(scale.rawValue)
            }
        }
        AdvancedOverrideRow(
            title: "Filter when enlarging",
            caption: caption(pinned: own.upscaleFilter != nil, settingsValue: "set to \(store.globalUpscaleFilter.title)"),
            selection: numberChoice(\.upscaleFilter, known: ScaleFilter.allCases.map(\.rawValue))
        ) {
            Text("Use Global Default").tag(-1)
            ForEach(ScaleFilter.allCases) { filter in
                Text(filter.title).tag(filter.rawValue)
            }
        }
        AdvancedOverrideRow(
            title: "Filter when shrinking",
            caption: caption(pinned: own.downscaleFilter != nil, settingsValue: "set to \(store.globalDownscaleFilter.title)"),
            selection: numberChoice(\.downscaleFilter, known: ScaleFilter.allCases.map(\.rawValue))
        ) {
            Text("Use Global Default").tag(-1)
            ForEach(ScaleFilter.allCases) { filter in
                Text(filter.title).tag(filter.rawValue)
            }
        }
    }

    @ViewBuilder private var performanceRows: some View {
        AdvancedOverrideRow(
            title: "Favour performance",
            caption: caption(pinned: own.favourPerformance != nil, settingsValue: onOff(store.globalFavourPerformance)),
            selection: toggleChoice(\.favourPerformance)
        ) {
            ForEach(Choice.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        }
        AdvancedOverrideRow(
            title: "Steady frame rate",
            caption: caption(pinned: own.fullSpeedRenders != nil, settingsValue: onOff(store.globalFullSpeedRenders)),
            selection: toggleChoice(\.fullSpeedRenders)
        ) {
            ForEach(Choice.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        }
        if store.overrides(for: gameKey).fullSpeedRenders ?? store.globalFullSpeedRenders {
            AdvancedOverrideRow(
                title: "First time a new effect appears",
                caption: caption(pinned: own.fullSpeedShaderMode != nil,
                                 settingsValue: "set to \(store.globalFullSpeedShaderMode.title)"),
                selection: numberChoice(\.fullSpeedShaderMode, known: FullSpeedRenders.ShaderMode.allCases.map(\.rawValue))
            ) {
                Text("Use Global Default").tag(-1)
                ForEach(FullSpeedRenders.ShaderMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
        }
        AdvancedOverrideRow(
            title: "One-core mode",
            caption: caption(pinned: own.oneCoreMode != nil, settingsValue: onOff(store.globalOneCoreMode)),
            selection: toggleChoice(\.oneCoreMode)
        ) {
            ForEach(Choice.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        }
    }

    @ViewBuilder private var screenRows: some View {
        AdvancedOverrideRow(
            title: "Screen layout",
            caption: caption(pinned: own.screenLayout != nil, settingsValue: "set to \(store.globalScreenLayout.string)"),
            selection: textChoice(\.screenLayout, known: ScreenLayout.allCases.map(\.rawValue))
        ) {
            Text("Use Global Default").tag("")
            ForEach(ScreenLayout.allCases) { layout in
                Text(layout.string).tag(layout.rawValue)
            }
        }
        AdvancedOverrideRow(
            title: "Hide on-screen controls when a controller is connected",
            caption: caption(pinned: own.autoHideControls != nil, settingsValue: onOff(store.globalAutoHideControls)),
            selection: toggleChoice(\.autoHideControls)
        ) {
            ForEach(Choice.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        }
        AdvancedOverrideRow(
            title: "Performance overlay",
            caption: caption(pinned: own.performanceOverlay != nil,
                             settingsValue: store.globalOverlayPosition == .disabled ? "off" : "on"),
            selection: toggleChoice(\.performanceOverlay)
        ) {
            ForEach(Choice.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        }
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            confirmReset = true
        } label: {
            DestructiveSettingsLabel(title: "Reset this game's options", systemImage: "arrow.uturn.backward")
        }
        .disabled(own.isIdentity)
    }
}

/// One per-game choice: the setting's name and menu, and a line saying what it follows or what this game has.
private struct AdvancedOverrideRow<Selection: Hashable, Options: View>: View {
    let title: String
    let caption: String
    let selection: Binding<Selection>
    let options: Options

    init(title: String, caption: String, selection: Binding<Selection>, @ViewBuilder options: () -> Options) {
        self.title = title
        self.caption = caption
        self.selection = selection
        self.options = options()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(selection: selection) {
                options
            } label: {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .pickerStyle(.menu)
            .tint(MuffinTheme.accentText)
            Text(caption)
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
