import Foundation
import SwiftUI
// For UTType.folder, which the import picker is restricted to.
import UniformTypeIdentifiers

/// Per-game overrides on top of the global defaults in Settings.
///
/// `nil` means "follow whatever the global setting currently says" - a real third state,
/// not the same as `false`. A game nobody has ever overridden should keep tracking the
/// global default as it changes, not freeze at whatever that default happened to be the
/// first time the game was seen.
struct GameOverrides: Codable, Equatable {
    /// Exists because Nano Assault Neo specifically breaks with background shader
    /// compilation on, while every other tested game is fine with it on. A single global
    /// toggle cannot be right for both at once, so this is the escape hatch: nil follows
    /// Settings' "Compile shaders in the background", true/false pin this one game.
    var preCompileShaders: Bool?

    /// Same escape hatch, for Settings' "Favour accuracy". Decodes to nil for overrides saved
    /// before this field existed (follow the global default).
    var favourAccuracy: Bool?

    /// CoreMode.rawValue ("auto", "single", "multi"), or nil to follow Settings > CPU. A string
    /// rather than the enum so an unknown value from a future version decodes instead of
    /// throwing away every override.
    var coreMode: String?

    // The options below are Advanced mode only (see AdvancedSettings and PerGameAdvancedSettings.swift).
    // Each nil follows the global setting. Raw values rather than enums, like coreMode.
    /// RenderScale.rawValue.
    var renderScale: String?
    /// ScaleFilter.rawValue, for the upscale and downscale filters.
    var upscaleFilter: Int?
    var downscaleFilter: Int?
    var favourPerformance: Bool?
    var fullSpeedRenders: Bool?
    /// FullSpeedRenders.ShaderMode.rawValue.
    var fullSpeedShaderMode: Int?
    var oneCoreMode: Bool?
    /// ScreenLayout.rawValue.
    var screenLayout: String?
    /// Hide the on-screen controls while a controller is connected.
    var autoHideControls: Bool?
    /// On shows the performance overlay, off hides it.
    var performanceOverlay: Bool?

    static let identity = GameOverrides()
    var isIdentity: Bool { self == GameOverrides.identity }
}

/// Where per-game overrides live, keyed by `GameMetadata.settingsKey` (the game's title ID, or its file-name id when no title ID
/// could be read).
///
/// One JSON blob rather than a key per game per setting - the same shape
/// `ControllerCustomLayout` already uses for per-element pad overrides - because the game
/// list is open-ended and `@AppStorage` needs a key known at compile time.
final class PerGameSettingsStore: ObservableObject {
    static let shared = PerGameSettingsStore()
    static let storageKey = "muffin.perGame.overrides"

    @Published private(set) var overridesByGame: [String: GameOverrides]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: GameOverrides].self, from: data) {
            overridesByGame = decoded
        } else {
            overridesByGame = [:]
        }
    }

    func overrides(for gameID: String) -> GameOverrides {
        overridesByGame[gameID] ?? .identity
    }

    /// What will actually reach the bridge for this game at launch: its own override if
    /// it has one, otherwise the global default read the same way GameManager already
    /// reads it (`UserDefaults` directly, since the engine cannot see `@AppStorage` and a
    /// value that only lived in a SwiftUI property wrapper would silently revert on every
    /// relaunch).
    func effectivePreCompileShaders(for gameID: String) -> Bool {
        overrides(for: gameID).preCompileShaders ?? globalPreCompileShaders
    }

    /// What Settings says right now, for the screens that show it beside a game's own choice.
    var globalPreCompileShaders: Bool {
        defaults.object(forKey: "muffin.shaders.asyncCompile") as? Bool ?? true
    }

    var globalFavourAccuracy: Bool {
        defaults.object(forKey: "muffin.cpu.favourAccuracy") as? Bool ?? false
    }

    func setPreCompileShaders(_ value: Bool?, for gameID: String) {
        var next = overrides(for: gameID)
        next.preCompileShaders = value
        write(next, for: gameID)
    }

    /// Per-game override first, global default underneath. Read before boot (see
    /// cemu_bridge_set_favour_accuracy's call site).
    func effectiveFavourAccuracy(for gameID: String) -> Bool {
        activeOverrides(for: gameID).favourAccuracy ?? globalFavourAccuracy
    }

    func setFavourAccuracy(_ value: Bool?, for gameID: String) {
        var next = overrides(for: gameID)
        next.favourAccuracy = value
        write(next, for: gameID)
    }

    /// Per-game core count first, Settings' choice underneath. Read before boot.
    func effectiveCoreMode(for gameID: String) -> CoreMode {
        if let raw = activeOverrides(for: gameID).coreMode, let mode = CoreMode(rawValue: raw) {
            return mode
        }
        return CoreMode.current
    }

    func setCoreMode(_ value: CoreMode?, for gameID: String) {
        var next = overrides(for: gameID)
        next.coreMode = value?.rawValue
        write(next, for: gameID)
    }

    /// Moves overrides saved under the game's file-name id (before settings were keyed by title ID) to its title-ID key. An entry
    /// already under the title-ID key is never overwritten, and the old one is only removed once it has been moved.
    func adoptTitleIDKey(for game: GameMetadata) {
        let key = game.settingsKey
        guard key != game.id, let legacy = overridesByGame[game.id], overridesByGame[key] == nil else { return }
        overridesByGame[key] = legacy
        overridesByGame.removeValue(forKey: game.id)
        persist()
    }

    /// Replaces every game's overrides at once. Settings mode uses it to clear the Advanced options
    /// when switching to Basic and to put them back on Restore (see AdvancedSettings).
    func replaceOverrides(_ next: [String: GameOverrides]) {
        overridesByGame = next.filter { !$0.value.isIdentity }
        persist()
    }

    /// Writes one game's overrides. An empty set is removed, like every other write.
    func setOverrides(_ value: GameOverrides, for gameID: String) {
        write(value, for: gameID)
    }

    /// Puts one game back on the global settings.
    func clearOverrides(for gameID: String) {
        write(.identity, for: gameID)
    }

    /// Clears every per-game override at once - used by Settings > About > "Reset
    /// Settings and Per-Game Options", the only path that touches this store from
    /// the global reset. Ordinary "Reset Settings" leaves it alone entirely.
    func removeAllOverrides() {
        overridesByGame = [:]
        persist()
    }

    private func write(_ value: GameOverrides, for gameID: String) {
        if value.isIdentity {
            overridesByGame.removeValue(forKey: gameID)
        } else {
            overridesByGame[gameID] = value
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(overridesByGame) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Carries everything a game's settings stored under its file name over to its title-ID key (GameMetadata.settingsKey): the
/// per-game overrides, Auto's memory of a bad three-core run, and the pad layouts. Run on every library scan. Each step only
/// acts on a game that still has something under the old name and nothing under the new key, so it is safe to repeat and a
/// game attached later (a disc image whose key arrived after the first scan) is picked up too. Nothing is deleted that was
/// not moved or copied first. Save states, covers, favourites and the library's own caches stay keyed by file name.
enum PerGameKeyMigration {
    @MainActor static func run(games: [GameMetadata]) {
        for game in games where game.titleId != nil && game.settingsKey != game.id {
            PerGameSettingsStore.shared.adoptTitleIDKey(for: game)
            AutoCoreHistory.adoptTitleIDKey(from: game.id, to: game.settingsKey)
            TouchLabSettings.adoptAdaptiveKey(from: game.id, to: game.settingsKey)
            MeloControlsSetting.adoptLayout(from: game.id, to: game.settingsKey)
        }
    }
}

/// Quick actions offered from a long-press on a library title: a couple of toggles, plus a
/// way into the full options screen. Applied as a `.contextMenu` modifier on the game's card.
struct GameContextMenu: View {
    let game: GameMetadata
    @ObservedObject var store: PerGameSettingsStore
    /// Used to check/clear a manual cover override; the picker screen takes its own reference.
    @ObservedObject var gameManager: GameManager
    let onViewOptions: () -> Void
    let onDecryptToFiles: () -> Void
    let onImportDLC: () -> Void
    let onImportUpdate: () -> Void
    let onRemoveDLC: () -> Void
    let onRemoveUpdate: () -> Void
    let onChangeCoverArt: () -> Void
    var onRename: () -> Void = {}

    var body: some View {
        if let installLabel = game.installLabel {
            Text("\(game.cardName.name) \u{2022} \(installLabel)")
            Divider()
        }
        Toggle(isOn: Binding(
            get: { store.effectivePreCompileShaders(for: game.settingsKey) },
            set: { store.setPreCompileShaders($0, for: game.settingsKey) }
        )) {
            Label("Compile Shaders in the Background", systemImage: "bolt.fill")
        }
        // The toggle above always sets this game's own choice, so when it has one, say so and
        // offer the way back to following Settings without a trip into the options screen.
        if store.overrides(for: game.settingsKey).preCompileShaders != nil {
            Button {
                store.setPreCompileShaders(nil, for: game.settingsKey)
            } label: {
                Label("Use Global Shader Setting", systemImage: "arrow.uturn.backward")
            }
        }
        Button(action: onViewOptions) {
            Label("View Game Options", systemImage: "slider.horizontal.3")
        }
        Button(action: onRename) {
            Label("Rename\u{2026}", systemImage: "pencil")
        }
        if LibraryCustomNames.shared.name(for: game.installKey) != nil {
            Button {
                LibraryCustomNames.shared.set(nil, for: game.installKey)
            } label: {
                Label("Reset to Original Title", systemImage: "arrow.uturn.backward")
            }
        }
        // The escape hatch for a card still showing the plain gamepad placeholder
        // (or the wrong art) because GameTDB's automatic fetch (CoverArtFetcher)
        // never found anything for it - homebrew, or an obscure title GameTDB
        // simply doesn't list. Opens CoverArtPickerView; the automatic fetch itself
        // is untouched and still runs first, same as always.
        Button(action: onChangeCoverArt) {
            Label("Change Cover Art\u{2026}", systemImage: "photo")
        }
        // Only offered once there's actually an override to clear - checked fresh
        // against disk each time the menu opens, same as the DLC/update removal
        // actions below, rather than a separately-kept record that could drift.
        if gameManager.hasManualCoverOverride(forGameID: game.id) {
            Button(role: .destructive) {
                gameManager.removeManualCover(forGameID: game.id)
            } label: {
                DestructiveSettingsLabel(title: "Remove Custom Cover", systemImage: "photo.badge.minus")
            }
        }
        // Disc images only - see gameSupportsDecryptToFiles() in DecryptROMView.swift for
        // why a folder dump, homebrew .rpx/.elf, and .wuhb don't get this action.
        if gameSupportsDecryptToFiles(romPath: game.romPath) {
            Button(action: onDecryptToFiles) {
                // Opens a choice of "Decrypt to Raw Source" or "Decrypt to WUA" -
                // DecryptROMView.swift's formatChoiceBody - so this entry names the
                // action, not a specific destination.
                Label("Decrypt\u{2026}", systemImage: "lock.open")
            }
        }
        // Both go through DlcUpdateImport - see that file for the actual copy/match/
        // install logic. Long-pressing a specific game is what tells the import which
        // game the content is FOR when auto-matching by title ID can't (the manual
        // fallback), so these live here rather than behind the general import menu.
        Button(action: onImportDLC) {
            Label("Import DLC\u{2026}", systemImage: "shippingbox")
        }
        Button(action: onImportUpdate) {
            Label("Import Update\u{2026}", systemImage: "arrow.triangle.2.circlepath")
        }
        // Checked fresh each time the menu opens, against what's actually on disk under
        // Documents/mlc - not a separately-kept record, which could drift from it. A
        // game with nothing installed simply doesn't offer a removal action for it.
        let installed = DlcUpdateImport.installedContent(for: game)
        if installed.hasDLC {
            Button(role: .destructive, action: onRemoveDLC) {
                DestructiveSettingsLabel(title: "Remove DLC", systemImage: "trash")
            }
        }
        if installed.hasUpdate {
            Button(role: .destructive, action: onRemoveUpdate) {
                DestructiveSettingsLabel(title: "Remove Update", systemImage: "trash")
            }
        }
    }
}

/// One override row: the setting's name and menu, with a line under it saying what it follows
/// or what this game has been set to. Used for every per-game choice on the options screen.
private struct OverridePickerRow<Selection: Hashable, Options: View>: View {
    let title: String
    let caption: String
    let selection: Binding<Selection>
    let isDisabled: Bool
    let options: Options

    init(title: String, caption: String, selection: Binding<Selection>, isDisabled: Bool = false,
         @ViewBuilder options: () -> Options) {
        self.title = title
        self.caption = caption
        self.selection = selection
        self.isDisabled = isDisabled
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
            .disabled(isDisabled)
            Text(caption)
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The full per-game settings screen "View Game Options" opens into.
///
/// Only reachable from the library, so a game is never running while these change: every
/// choice here is read when the game next starts.
struct GameOptionsView: View {
    let game: GameMetadata
    @ObservedObject var store: PerGameSettingsStore
    /// The whole library, so a cache file that belongs to another game can say which one.
    var libraryGames: [GameMetadata] = []
    /// Needed by the dashboard (cover, Info) at the top of the screen.
    let gameManager: GameManager
    /// Starts the game; the dashboard's Play closes this screen first.
    var onPlay: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue

    /// One line of feedback under the buttons rather than an alert. An alert for a
    /// success is a second tap for something the person already knows they did; the
    /// failures here are all short enough to read in place.
    @State private var saveTransferMessage: String?
    @State private var saveTransferFailed = false
    @State private var showingImportConfirmation = false

    /// Same idea for the shader cache imports: one line under the buttons, red when nothing was imported.
    @State private var cacheImportMessage: String?
    @State private var cacheImportFailed = false
    @State private var cacheImportBusy = false
    /// A pipeline cache whose name doesn't say which renderer made it, waiting for the answer.
    @State private var pendingPipeline: PendingPipeline?

    private struct PendingPipeline: Identifiable {
        let id = UUID()
        let staged: URL
        let name: String
    }

    /// Three real states, not two - "use whichever the global setting is right now" has
    /// to be a choice you can return to, not just wherever the toggle happens to land.
    /// Shared by every per-game override on this screen, not just shaders.
    private enum TriState: String, CaseIterable, Identifiable {
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

    private func binding(for keyPath: WritableKeyPath<GameOverrides, Bool?>,
                         set setter: @escaping (Bool?) -> Void) -> Binding<TriState> {
        Binding(
            get: {
                switch store.overrides(for: game.settingsKey)[keyPath: keyPath] {
                case .none: return .useGlobalDefault
                case .some(true): return .on
                case .some(false): return .off
                }
            },
            set: { choice in
                switch choice {
                case .useGlobalDefault: setter(nil)
                case .on: setter(true)
                case .off: setter(false)
                }
            })
    }

    private var shaderChoice: Binding<TriState> {
        binding(for: \.preCompileShaders) { store.setPreCompileShaders($0, for: game.settingsKey) }
    }

    private var favourAccuracyChoice: Binding<TriState> {
        binding(for: \.favourAccuracy) { store.setFavourAccuracy($0, for: game.settingsKey) }
    }

    /// nil is "Use Global Default"; the tag is CoreMode.rawValue otherwise. A stored value this
    /// version does not know (saved by a newer one) reads as "Use Global Default", which is what
    /// the launch does with it.
    private var coreModeChoice: Binding<String> {
        Binding(
            get: {
                guard let raw = store.overrides(for: game.settingsKey).coreMode, CoreMode(rawValue: raw) != nil else { return "" }
                return raw
            },
            set: { store.setCoreMode(CoreMode(rawValue: $0), for: game.settingsKey) })
    }

    // MARK: Captions

    /// "Follows Settings, which has it on." or "Set for this game only. Settings has it on."
    private func caption(pinned: Bool, settingsValue: String) -> String {
        pinned
            ? "Set for this game only. Settings has it \(settingsValue)."
            : "Follows Settings, which has it \(settingsValue)."
    }

    private var shaderCaption: String {
        caption(pinned: store.overrides(for: game.settingsKey).preCompileShaders != nil,
                settingsValue: store.globalPreCompileShaders ? "on" : "off")
    }

    private var favourAccuracyCaption: String {
        caption(pinned: store.overrides(for: game.settingsKey).favourAccuracy != nil,
                settingsValue: store.globalFavourAccuracy ? "on" : "off")
    }

    private var coreModeCaption: String {
        guard DeviceCapabilities.current.multicoreViable else { return DeviceCapabilities.oneCoreOnlyText }
        let base = caption(pinned: store.overrides(for: game.settingsKey).coreMode != nil,
                           settingsValue: "set to \(CoreMode.current.title)")
        guard store.effectiveCoreMode(for: game.settingsKey) != .single else { return base }
        if store.effectiveFavourAccuracy(for: game.settingsKey) {
            return base + " Favour accuracy is on for this game, so it runs on one core whatever this says."
        }
        if OneCoreMode.isEnabled {
            return base + " One-core mode is on in Settings, so games run on one core whatever this says."
        }
        return base
    }

    // MARK: Sections

    private var overridesSection: some View {
        Section {
            OverridePickerRow(title: "Compile shaders in the background", caption: shaderCaption, selection: shaderChoice) {
                ForEach(TriState.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            // Advanced mode only (see AdvancedSettings).
            if SettingsMode.isAdvanced(raw: settingsModeRaw) {
                OverridePickerRow(title: "Favour accuracy", caption: favourAccuracyCaption, selection: favourAccuracyChoice) {
                    ForEach(TriState.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                OverridePickerRow(title: "CPU cores", caption: coreModeCaption, selection: coreModeChoice,
                                  isDisabled: !DeviceCapabilities.current.multicoreViable) {
                    Text("Use Global Default").tag("")
                    ForEach(CoreMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
            }
            if !store.overrides(for: game.settingsKey).isIdentity {
                Button {
                    store.clearOverrides(for: game.settingsKey)
                } label: {
                    Label("Use Global Defaults for All", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }
        } header: {
            SettingsSectionHeader("Overrides", icon: "slider.horizontal.3", accent: .core)
        } footer: {
            InfoButton.footer(
                "\"Use Global Default\" follows Settings; On or Off sets this game only. Changes apply the next time you start the game.",
                title: "Overrides",
                text: "Compile shaders in the background builds shaders while the game keeps running. Most games want this on; Nano Assault Neo breaks with it, so it can be set per game.\n\nFavour accuracy is slower but more accurate, and can fix a game that glitches or crashes. It also keeps the game on one CPU core. See Settings > CPU.\n\nCPU cores picks how many cores run the game. Auto decides for each game and device.\n\n\"Use Global Default\" follows the matching setting in Settings, even if you change it later. On or Off sets this game only.\n\nChanges apply the next time you start the game."
            )
        }
    }

    private var graphicPacksSection: some View {
        Section {
            NavigationLink {
                GraphicPacksView(game: game)
            } label: {
                Label("Graphic Packs", systemImage: "wand.and.stars")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        } header: {
            SettingsSectionHeader("Graphic packs", icon: "paintpalette", accent: .core)
        } footer: {
            InfoButton.footer(
                "Resolution, frame rate, fixes and mods for this game. They apply the next time you start it.",
                title: "Graphic packs",
                text: "Graphic packs change how a game looks or plays: higher resolutions, frame-rate patches, fixes for known glitches and mods. Download the community packs, turn on the ones you want for this game, and pick their options. Nothing is turned on automatically.\n\nHigher resolutions cost speed and memory, and what is reasonable depends on the device, so the options show a suggestion for this one.\n\nPacks listed under All games apply to every game, not just this one. Packs apply the next time you start the game."
            )
        }
    }

    private var gameSavesSection: some View {
        Section {
            exportSaveButton
            importSaveButton
            if let saveTransferMessage {
                Text(saveTransferMessage)
                    .font(.system(size: 12))
                    .foregroundColor(saveTransferFailed ? .red : MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SettingsSectionHeader("Game saves", icon: "externaldrive", accent: .io)
        } footer: {
            InfoButton.footer(
                "The save the game itself writes. Not a save state. Export is available once the game has saved.",
                title: "Game saves",
                text: "This is the save the game itself writes. It uses the Wii U\'s own format, so it can move between MuffinEMU, desktop Cemu and a real console. A save state is a snapshot of the whole emulated console and only MuffinEMU can read it.\n\nExport writes a folder named after the game and title ID. Import accepts that folder, a folder named after the title ID from another Cemu install, or its \'user\' folder. Importing replaces the current save; the old one is first copied to save-backups in MuffinEMU\'s Documents folder."
            )
        }
    }

    private var exportSaveButton: some View {
        Button {
            GameSaveTransfer.export(game) { result in
                switch result {
                case .success(let note):
                    saveTransferMessage = note
                    saveTransferFailed = false
                case .failure(let error):
                    saveTransferMessage = error.localizedDescription
                    // Backing out of the picker is not an error, so it is not shown as one.
                    if case GameSaveTransfer.TransferError.cancelled = error {
                        saveTransferFailed = false
                    } else {
                        saveTransferFailed = true
                    }
                }
            }
        } label: {
            Label("Export game saves", systemImage: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .disabled(!GameSaveTransfer.hasSave(for: game))
    }

    // Confirmed, unlike export: this one replaces what is already there. It is backed up
    // either way, but someone should know they are about to swap their progress out before
    // the picker opens, not after.
    private var importSaveButton: some View {
        Button(role: .destructive) {
            showingImportConfirmation = true
        } label: {
            Label("Import game save folder", systemImage: "square.and.arrow.down")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
    }

    private func pickSaveFolder() {
        DocumentImport.present(contentTypes: [.folder]) { result in
            switch result {
            case .success(let urls):
                guard let picked = urls.first else { return }
                do {
                    saveTransferMessage = try GameSaveTransfer.importSave(game, from: picked)
                    saveTransferFailed = false
                } catch {
                    saveTransferMessage = error.localizedDescription
                    saveTransferFailed = true
                }
            case .failure(let error):
                saveTransferMessage = error.localizedDescription
                saveTransferFailed = true
            }
        }
    }

    // MARK: Shader caches

    private var shaderCachesSection: some View {
        Section {
            Button {
                pickCacheFile(.shaders)
            } label: {
                Label("Import learned shaders", systemImage: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .disabled(cacheImportBusy)
            Button {
                pickCacheFile(.pipeline)
            } label: {
                Label("Import shader pipeline caches", systemImage: "square.and.arrow.down.on.square")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .disabled(cacheImportBusy)
            if cacheImportBusy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Importing\u{2026}")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            if let cacheImportMessage {
                Text(cacheImportMessage)
                    .font(.system(size: 12))
                    .foregroundColor(cacheImportFailed ? .red : MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SettingsSectionHeader("Shader caches", icon: "hammer", accent: .core)
        } footer: {
            InfoButton.footer(
                "Add a shader cache from desktop Cemu or another MuffinEMU, so this game starts with its shaders already learned.",
                title: "Shader caches",
                text: "Learned shaders are what a game has revealed by drawing with them. Importing adds them to this game's own file: anything the game already has stays as it is, and the file is never replaced.\n\nThe file has to be this game's: MuffinEMU checks the version stamp inside it, not the name. Desktop Cemu's files work: learned shaders are named like 000500001010ec00_shaders.bin and are converted the first time the game starts. MuffinEMU's are named ..._mtlshaders.bin. Desktop caches from before Cemu 1.16 use another format and can't be converted.\n\nPipeline caches are named ..._vkpipeline.bin (desktop Cemu, Vulkan) or ..._mtlpipeline.bin (MuffinEMU, Metal). A Vulkan one only helps the Vulkan renderer and a Metal one only the Metal renderer; it's stored either way and used when you switch. Each also needs the game's learned shaders. Import with the game closed. The sizes in Settings update the next time you open it."
            )
        }
    }

    private func pickCacheFile(_ kind: ShaderCacheImport.Kind) {
        DocumentImport.present(contentTypes: ShaderCacheImport.pickerTypes) { result in
            switch result {
            case .success(let urls):
                guard let picked = urls.first else { return }
                let name = picked.lastPathComponent
                cacheImportBusy = true
                cacheImportMessage = nil
                DispatchQueue.global(qos: .userInitiated).async {
                    let staged: URL
                    do {
                        staged = try ShaderCacheImport.stage(picked)
                    } catch {
                        DispatchQueue.main.async {
                            finishCacheImport(ShaderCacheImport.Outcome(message: "Couldn't read \"\(name)\": \(error.localizedDescription)", failed: true))
                        }
                        return
                    }
                    if kind == .pipeline, ShaderCacheImport.pipelineIsVulkan(fileName: name) == nil {
                        // the contents don't say which renderer wrote it, so ask
                        DispatchQueue.main.async {
                            cacheImportBusy = false
                            pendingPipeline = PendingPipeline(staged: staged, name: name)
                        }
                        return
                    }
                    runCacheImport(kind, staged: staged, name: name, pipelineIsVulkan: ShaderCacheImport.pipelineIsVulkan(fileName: name))
                }
            case .failure(let error):
                finishCacheImport(ShaderCacheImport.Outcome(message: error.localizedDescription, failed: true))
            }
        }
    }

    /// Runs on a background queue.
    private func runCacheImport(_ kind: ShaderCacheImport.Kind, staged: URL, name: String, pipelineIsVulkan: Bool?) {
        let outcome = ShaderCacheImport.run(kind: kind, game: game, library: libraryGames, staged: staged,
                                            originalName: name, pipelineIsVulkan: pipelineIsVulkan)
        DispatchQueue.main.async { finishCacheImport(outcome) }
    }

    private func finishCacheImport(_ outcome: ShaderCacheImport.Outcome) {
        cacheImportBusy = false
        cacheImportMessage = outcome.message
        cacheImportFailed = outcome.failed
    }

    private func answerPipelineRenderer(_ pending: PendingPipeline, vulkan: Bool) {
        pendingPipeline = nil
        cacheImportBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            runCacheImport(.pipeline, staged: pending.staged, name: pending.name, pipelineIsVulkan: vulkan)
        }
    }

    private func discardPending(_ pending: PendingPipeline) {
        try? FileManager.default.removeItem(at: pending.staged)
    }

    private var optionsForm: some View {
        Form {
            GameDashboardSection(game: game, gameManager: gameManager, onPlay: onPlay)
            overridesSection
            AdvancedGameOptionsSection(game: game, store: store)
            GameShaderCacheSection(game: game)
            graphicPacksSection
            gameSavesSection
            shaderCachesSection
        }
    }

    var body: some View {
        // NavigationStack needs iOS 16+; the deployment target is 15.0.
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient
                    .ignoresSafeArea()

                optionsForm
            }
            .confirmationDialog("Import a save folder?", isPresented: $showingImportConfirmation, titleVisibility: .visible) {
                Button("Choose folder", role: .destructive, action: pickSaveFolder)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This replaces \(game.title)\'s current save. The one you have now is backed up first, and the game should be closed before you do this.")
            }
            .confirmationDialog("Which renderer made this pipeline cache?", isPresented: Binding(
                get: { pendingPipeline != nil },
                set: { if !$0 { pendingPipeline = nil } }
            ), titleVisibility: .visible, presenting: pendingPipeline) { pending in
                Button("Vulkan (desktop Cemu)") { answerPipelineRenderer(pending, vulkan: true) }
                Button("Metal (MuffinEMU)") { answerPipelineRenderer(pending, vulkan: false) }
                Button("Cancel", role: .cancel) { discardPending(pending) }
            } message: { pending in
                Text("\"\(pending.name)\" doesn't say. Desktop Cemu's are named ..._vkpipeline.bin and MuffinEMU's ..._mtlpipeline.bin. It's stored under the matching name either way.")
            }
            .navigationTitle(game.title)
            .muffinOpaqueNavigationBar(MuffinTheme.formGround)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
