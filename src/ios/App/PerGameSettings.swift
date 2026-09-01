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

    /// nil = follow Settings' "Reduce Command-Buffer Splitting (Experimental)".
    /// Per-game because it targets an unconfirmed hypothesis, not a proven fix - it may
    /// help the games that show the intermittent rainbow/garbage geometry and do nothing
    /// (or, in principle, something worse) on others, which is exactly why this needs to
    /// be a per-game dial rather than one global switch.
    var reduceEncoderSplitting: Bool?

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

    /// Same resolution order as shaders: per-game override first, the global
    /// "Reduce Command-Buffer Splitting" toggle underneath it. Off both ways unless
    /// someone has actually turned it on somewhere - see GameOverrides.reduceEncoderSplitting.
    func effectiveReduceEncoderSplitting(for gameID: String) -> Bool {
        let globalDefault = defaults.object(forKey: "muffin.render.reduceEncoderSplitting") as? Bool ?? false
        return overrides(for: gameID).reduceEncoderSplitting ?? globalDefault
    }

    func setReduceEncoderSplitting(_ value: Bool?, for gameID: String) {
        var next = overrides(for: gameID)
        next.reduceEncoderSplitting = value
        write(next, for: gameID)
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
    private var encoderSplittingChoice: Binding<TriState> {
        binding(for: \.reduceEncoderSplitting) { store.setReduceEncoderSplitting($0, for: game.id) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Pre-Compile Shaders", selection: shaderChoice) {
                        ForEach(TriState.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                } header: {
                    Text("Shader Compilation")
                } footer: {
                    Text("Renders and compiles every shader ahead of time so the game runs faster even without the recompiler. Most games want this on; Nano Assault Neo specifically breaks with it on, which is why this is a per-game choice rather than only a global one.\n\n\"Use Global Default\" tracks whatever Settings > Shader Compilation currently says, even if you change it later. On/Off pins this game regardless of what the global setting does.")
                }

                Section {
                    Picker("Reduce Command-Buffer Splitting", selection: encoderSplittingChoice) {
                        ForEach(TriState.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                } header: {
                    Text("Rendering (Experimental)")
                } footer: {
                    Text("Aimed at intermittent rainbow or garbled geometry some games show for a few seconds at a time. Not a confirmed fix - try On if this game shows that glitch, and leave it Off (or set it back to Use Global Default) if it doesn't help or makes things render worse.")
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
    }
}
