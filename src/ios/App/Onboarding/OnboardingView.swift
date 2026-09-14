import SwiftUI
import UniformTypeIdentifiers

// MARK: - Wiring notes for the lead
//
// Nothing here needed a new closure poked through ContentView or GameManager - both
// actions on screen reuse entry points that already exist and are already public:
//
//   - Keys import: DocumentImport.present(contentTypes: [.item]) + WiiUKeys.importKeys(from:),
//     the exact two calls KeysSettingsSection.swift already makes.
//   - Game import: DocumentImport.present(contentTypes: [.item]) + GameManager.importROM(from:),
//     the exact two calls ContentView.swift's GameBrowserView.beginImport()/handleImport()
//     already make.
//
// The one thing this file cannot do for itself is decide WHEN to appear - that has to
// live in ContentView, which this task was told not to touch. The whole hook is one
// @State var and one .fullScreenCover modifier on ContentView's own body (the
// top-level `struct ContentView: View`, not GameBrowserView):
//
//     struct ContentView: View {
//         @StateObject var gameManager = GameManager()
//         @State private var showingOnboarding = OnboardingState.shouldPresentOnFirstLaunch
//         ...
//         var body: some View {
//             ZStack { /* existing body, unchanged */ }
//                 .ignoresSafeArea()
//                 .fullScreenCover(isPresented: $showingOnboarding) {
//                     OnboardingView(gameManager: gameManager) {
//                         showingOnboarding = false
//                     }
//                 }
//         }
//     }
//
// OnboardingView marks itself complete via OnboardingState.markCompleted() before
// calling onFinished, so a relaunch never shows it again on its own.
//
// To reopen it from Settings later, drop SettingsOnboardingRow (OnboardingState.swift)
// into AboutSettingsSection's Section body, passing an `onRequestReopen` closure that
// flips whatever makes `showingOnboarding` true again - e.g. exposing it as a Binding
// threaded down through GameBrowserView -> SettingsView -> AboutSettingsSection, or a
// small shared ObservableObject flag if that plumbing is unwelcome. The row already
// calls OnboardingState.reset() itself; it only needs to be told how to make the view
// reappear.

/// First-launch flow: what MuffinEMU is, where keys and games come from, and what
/// actually makes it fast. Four pages, one idea each, at most one action per page.
///
/// `gameManager` is the same instance ContentView already owns - passed in rather than
/// re-created, since a second `GameManager()` would start its own background load and
/// answer questions about a library import made through this screen with stale state.
struct OnboardingView: View {
    @ObservedObject var gameManager: GameManager
    /// Called once "Start playing" is tapped, after OnboardingState.markCompleted()
    /// has already run. Wire it to dismiss whatever presented this view - see the
    /// notes above.
    var onFinished: () -> Void

    @State private var page = 0
    private let totalPages = 4

    private var isLastPage: Bool { page == totalPages - 1 }

    var body: some View {
        ZStack {
            MuffinTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    OnboardingWelcomePage()
                        .tag(0)
                    OnboardingKeysPage(onSkip: advance)
                        .tag(1)
                    OnboardingGamesPage(gameManager: gameManager)
                        .tag(2)
                    OnboardingSpeedControlsPage()
                        .tag(3)
                }
                // Themed dots in the footer instead, rather than the system's plain
                // black-and-white page control - see `pageDots` below.
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            pageDots

            HStack {
                Button("Back", action: goBack)
                    .buttonStyle(MuffinSecondaryButtonStyle())
                    .opacity(page == 0 ? 0 : 1)
                    .disabled(page == 0)
                    .accessibilityHidden(page == 0)

                Spacer()

                Button(action: advance) {
                    Text(isLastPage ? "Start playing" : "Next")
                }
                .buttonStyle(MuffinPrimaryButtonStyle())
                .accessibilityLabel(isLastPage ? "Start playing" : "Next")
                .accessibilityHint(isLastPage
                    ? "Finishes the guide and opens your library."
                    : "Goes to the next page of the guide.")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    /// Decorative on their own - `accessibilityHidden` on the HStack, since the
    /// Back/Next buttons' own labels already say where a VoiceOver user is in the
    /// flow, and a row of unlabeled dots would just be noise on top of that.
    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == page ? MuffinTheme.pixelBlue : MuffinTheme.wrapper)
                    .frame(width: index == page ? 9 : 7, height: index == page ? 9 : 7)
            }
        }
        .animation(.easeOut(duration: 0.18), value: page)
        .accessibilityHidden(true)
    }

    private func advance() {
        if isLastPage {
            finish()
        } else {
            withAnimation { page += 1 }
        }
    }

    private func goBack() {
        withAnimation { page = max(0, page - 1) }
    }

    private func finish() {
        OnboardingState.markCompleted()
        onFinished()
    }
}

// MARK: - Shared page chrome

/// One page's worth of chrome: a heading, one or two sentences under it, then
/// whatever the page needs. Wrapped in a ScrollView and width-capped rather than left
/// to stretch full width on an iPad, so a long piece of body text (Dynamic Type
/// pushed up, or a long error message) scrolls instead of ever being cut off, and so
/// text lines don't run edge-to-edge on a landscape iPad.
private struct OnboardingPageScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundColor(MuffinTheme.brownDarkest)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(MuffinTheme.brownMid)
                    .fixedSize(horizontal: false, vertical: true)

                content

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            // Capped width, centered: on a phone this is just "full width, some
            // padding"; on an iPad, landscape included, it keeps lines of text and the
            // action card from stretching absurdly wide.
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// One fact with a leading glyph - used on the speed/controls page, where three short
/// unrelated facts share a page by design (see the task's own page breakdown).
private struct OnboardingFactRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MuffinTheme.pixelBlue)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.body, design: .rounded))
                .foregroundColor(MuffinTheme.brownDarkest)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Page 1: Welcome

private struct OnboardingWelcomePage: View {
    var body: some View {
        OnboardingPageScaffold(
            title: "Welcome to MuffinEMU",
            subtitle: "MuffinEMU runs real Wii U software on your device, using MeloCafe's Cemu core. This guide covers keys, games, and speed in under a minute - skip anything you don't need."
        ) {
            EmptyView()
        }
    }
}

// MARK: - Page 2: Your keys

private struct OnboardingKeysPage: View {
    /// Advances the flow exactly like "Next" would - skipping keys isn't a dead end,
    /// it's just choosing not to do this one optional thing right now.
    var onSkip: () -> Void

    @State private var hasKeys = WiiUKeys.keysFileExists()
    @State private var keyCount = OnboardingKeysPage.currentKeyCount()
    @State private var errorMessage: String?

    var body: some View {
        OnboardingPageScaffold(
            title: "Your keys",
            subtitle: "Real Wii U games are encrypted, and MuffinEMU ships no keys - only a keys.txt dumped from your own Wii U can unlock them. Homebrew needs none of this."
        ) {
            MuffinCard {
                VStack(alignment: .leading, spacing: 16) {
                    Button(action: importKeys) {
                        Label(hasKeys ? "Replace keys.txt" : "Import keys.txt", systemImage: "key")
                    }
                    .buttonStyle(MuffinPrimaryButtonStyle())
                    .accessibilityHint("Opens the Files picker to choose your keys.txt.")

                    if hasKeys {
                        Text("\(keyCount) key\(keyCount == 1 ? "" : "s") loaded")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(MuffinTheme.brownMid)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: onSkip) {
                        Text("Skip - I only play homebrew")
                            .font(.system(.footnote, design: .rounded))
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(MuffinTheme.brownMid)
                    .accessibilityHint("Continues without importing keys. Homebrew doesn't need them, and you can add keys later from Settings.")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func importKeys() {
        // DocumentImport's completion always lands on the main thread - it is called
        // directly from a UIDocumentPickerViewController delegate method, the same
        // assumption KeysSettingsSection.handleKeysImport already makes - so touching
        // @State here needs no extra hop.
        DocumentImport.present(contentTypes: [.item]) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    keyCount = try WiiUKeys.importKeys(from: url)
                    hasKeys = true
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Mirrors KeysSettingsSection's own count, with the same fallback reasoning: the
    /// bridge can only answer once the engine has been initialized (see
    /// cemu_bridge_reload_and_count_keys's doc comment in CemuBridge.h), which has not
    /// happened yet on a first launch - nothing has been booted. Reading the file
    /// directly through WiiUKeys is the same real count, just derived without the
    /// engine.
    private static func currentKeyCount() -> Int {
        let bridgeCount = cemu_bridge_reload_and_count_keys()
        if bridgeCount >= 0 {
            return Int(bridgeCount)
        }
        return WiiUKeys.installedKeyCount()
    }
}

// MARK: - Page 3: Add games

private struct OnboardingGamesPage: View {
    @ObservedObject var gameManager: GameManager
    @State private var errorMessage: String?

    var body: some View {
        OnboardingPageScaffold(
            title: "Add your games",
            subtitle: "Games come from Files - .wud, .wux, .wua, .iso, a dumped game folder, or a homebrew .rpx - through the same Import picker your library's toolbar uses. Drop files straight into Documents/Roms from the Files app instead, if you'd rather."
        ) {
            MuffinCard {
                VStack(alignment: .leading, spacing: 16) {
                    Button(action: importGame) {
                        Label("Import a game", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(MuffinPrimaryButtonStyle())
                    .accessibilityHint("Opens the Files picker to choose a game to import.")

                    if case .copying(let name) = gameManager.importState {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Copying \(name)\u{2026}")
                        }
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(MuffinTheme.brownMid)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func importGame() {
        DocumentImport.present(contentTypes: [.item]) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    do {
                        try await gameManager.importROM(from: url)
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Page 4: Speed and controls

private struct OnboardingSpeedControlsPage: View {
    var body: some View {
        OnboardingPageScaffold(
            title: "Speed and controls",
            subtitle: "MuffinEMU is fastest with the recompiler running. Three things decide how that actually goes for you:"
        ) {
            MuffinCard {
                VStack(alignment: .leading, spacing: 18) {
                    OnboardingFactRow(
                        systemImage: "bolt.fill",
                        text: "The recompiler needs a JIT enabler - StikJIT, SideStore, or LiveContainer - attached at launch. Without one, the interpreter runs instead: it works, just much slower. Settings always shows which one you got."
                    )
                    OnboardingFactRow(
                        systemImage: "checkmark.seal.fill",
                        text: "If a game glitches, desyncs, or crashes, turn on Favour accuracy in Settings > CPU - it trades speed for correctness."
                    )
                    OnboardingFactRow(
                        systemImage: "gamecontroller.fill",
                        text: "The on-screen pad can add analog sticks and comfort controls, and any MFi, Xbox, or PlayStation controller works right alongside it."
                    )
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
