import Foundation
import SwiftUI

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

    /// Same escape hatch, for Settings' "Favour accuracy". A new Optional field on an
    /// existing Codable struct decodes to nil for every override already saved on
    /// disk before this existed - Swift's synthesized Decodable calls
    /// decodeIfPresent for Optional properties, so old JSON with no
    /// "favourAccuracy" key is not a decode failure, it's just nil, which is
    /// exactly the "follow the global default" behaviour a game nobody has
    /// overridden yet should have.
    var favourAccuracy: Bool?

    static let identity = GameOverrides()
    var isIdentity: Bool { self == GameOverrides.identity }
}

/// Where per-game overrides live, keyed by `GameMetadata.id`.
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
        let globalDefault = defaults.object(forKey: "muffin.shaders.asyncCompile") as? Bool ?? true
        return overrides(for: gameID).preCompileShaders ?? globalDefault
    }

    func setPreCompileShaders(_ value: Bool?, for gameID: String) {
        var next = overrides(for: gameID)
        next.preCompileShaders = value
        write(next, for: gameID)
    }

    /// Same "per-game override first, global default underneath" read GameManager
    /// already does for shader compilation, for the lead's Favour accuracy push
    /// before boot - see cemu_bridge_set_favour_accuracy's call site.
    func effectiveFavourAccuracy(for gameID: String) -> Bool {
        let globalDefault = defaults.object(forKey: "muffin.cpu.favourAccuracy") as? Bool ?? false
        return overrides(for: gameID).favourAccuracy ?? globalDefault
    }

    func setFavourAccuracy(_ value: Bool?, for gameID: String) {
        var next = overrides(for: gameID)
        next.favourAccuracy = value
        write(next, for: gameID)
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

/// The quick actions offered from a long-press on a library title - same pattern as
/// Manic's game grid: a couple of fast toggles right in the context menu, plus a way into
/// the full screen for everything else. Applied at the call site as a `.contextMenu`
/// modifier on the game's card, so it needs no changes to `GameCardOptimized` itself.
struct GameContextMenu: View {
    let game: GameMetadata
    @ObservedObject var store: PerGameSettingsStore
    let onViewOptions: () -> Void
    let onDecryptToFiles: () -> Void
    let onImportDLC: () -> Void
    let onImportUpdate: () -> Void
    let onRemoveDLC: () -> Void
    let onRemoveUpdate: () -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { store.effectivePreCompileShaders(for: game.id) },
            set: { store.setPreCompileShaders($0, for: game.id) }
        )) {
            Label("Pre-Compile Shaders", systemImage: "bolt.fill")
        }
        Button(action: onViewOptions) {
            Label("View Game Options", systemImage: "slider.horizontal.3")
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
                Label("Remove DLC", systemImage: "trash")
            }
        }
        if installed.hasUpdate {
            Button(role: .destructive, action: onRemoveUpdate) {
                Label("Remove Update", systemImage: "trash")
            }
        }
    }
}

/// The full per-game settings screen "View Game Options" opens into.
struct GameOptionsView: View {
    let game: GameMetadata
    @ObservedObject var store: PerGameSettingsStore
    @Environment(\.dismiss) private var dismiss

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
                switch store.overrides(for: game.id)[keyPath: keyPath] {
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
        binding(for: \.preCompileShaders) { store.setPreCompileShaders($0, for: game.id) }
    }

    private var favourAccuracyChoice: Binding<TriState> {
        binding(for: \.favourAccuracy) { store.setFavourAccuracy($0, for: game.id) }
    }

    var body: some View {
        // NavigationStack needs iOS 16+; this project's deployment target is 15.0 -
        // same reasoning as SettingsView.swift's own NavigationView, whose overall
        // shape (a background gradient behind a Form, rather than the plain white
        // Form this screen had before) this now matches exactly - this was the one
        // real settings screen in the app that hadn't picked it up.
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient
                    .ignoresSafeArea()

                Form {
                    Section {
                        HStack {
                            Text("Pre-Compile Shaders")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Spacer()
                            Picker("Pre-Compile Shaders", selection: shaderChoice) {
                                ForEach(TriState.allCases) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(MuffinTheme.pixelBlue)
                        }
                        // Next to Pre-Compile Shaders rather than its own section: both
                        // are the same shape of override on the same screen, and Favour
                        // accuracy is exactly the setting Nano Assault Neo's own
                        // shader-compile override sits next to in Settings itself.
                        HStack {
                            Text("Favour Accuracy")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Spacer()
                            Picker("Favour Accuracy", selection: favourAccuracyChoice) {
                                ForEach(TriState.allCases) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(MuffinTheme.pixelBlue)
                        }
                    } header: {
                        Text("Overrides")
                    } footer: {
                        // Same "one short sentence inline, the rest one tap away" shape
                        // every other settings section's footer in this app already
                        // uses - see InfoButton.swift - instead of a single paragraph
                        // dump nobody who already knows what these do has to read past.
                        InfoButton.footer(
                            "\"Use Global Default\" tracks Settings; On/Off pins this game regardless of it.",
                            title: "Overrides",
                            text: "Pre-Compile Shaders renders and compiles every shader ahead of time so the game runs faster even without the recompiler. Most games want this on; Nano Assault Neo specifically breaks with it on, which is why this is a per-game choice rather than only a global one.\n\nFavour Accuracy trades speed for stability on a game that glitches, desyncs or crashes - see Settings > CPU for what it changes.\n\n\"Use Global Default\" tracks whatever Settings currently says for that setting, even if you change it later. On/Off pins this game regardless of what the global setting does."
                        )
                    }
                }
            }
            .navigationTitle(game.title)
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
