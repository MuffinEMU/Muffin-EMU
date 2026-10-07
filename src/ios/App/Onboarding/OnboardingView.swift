// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import UniformTypeIdentifiers

/// First-launch flow in four pages: welcome, keys, games, and speed/controls. ContentView
/// presents it on first launch and passes in its own `gameManager`.
struct OnboardingView: View {
    @ObservedObject var gameManager: GameManager
    /// Called once "Start playing" is tapped, after OnboardingState.markCompleted() has run.
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
                // Themed dots in the footer replace the system page control (see `pageDots`).
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

    /// Decorative; hidden from VoiceOver since the Back/Next labels already say where you are.
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

/// The illustration at the top of an onboarding page: the app's muffin on the welcome page,
/// a brand-accent symbol on the others.
private enum OnboardingHero {
    case none
    case mark
    case symbol(String)

    @ViewBuilder var view: some View {
        switch self {
        case .none:
            EmptyView()
        case .mark:
            MuffinMark(side: 132)
                .shadow(color: MuffinTheme.shadow.opacity(0.25), radius: 16, x: 0, y: 8)
                .padding(.bottom, 4)
        case .symbol(let name):
            ZStack {
                Circle().fill(MuffinTheme.cream)
                Image(systemName: name)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(MuffinTheme.accentText)
            }
            .frame(width: 72, height: 72)
            .shadow(color: MuffinTheme.shadow.opacity(0.18), radius: 10, x: 0, y: 4)
            .accessibilityHidden(true)
        }
    }
}

/// One page of chrome: a heading, a subtitle, then the page's content. Scrollable and
/// width-capped so long text or large Dynamic Type never gets cut off on any device.
private struct OnboardingPageScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    /// What sits above the heading.
    var hero: OnboardingHero = .none
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero.view
                    .frame(maxWidth: .infinity, alignment: .center)

                // Straight on the background gradient, so the gradient's own ink: the
                // brown inks were dark on dark in the themes with a dark gradient.
                Text(title)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundColor(MuffinTheme.onBackground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(MuffinTheme.onBackgroundMuted)
                    .fixedSize(horizontal: false, vertical: true)

                content

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            // Capped width, centered, so text and cards don't stretch across a landscape iPad.
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// One fact with a leading glyph, used on the speed/controls page.
private struct OnboardingFactRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(MuffinTheme.accentText)
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
            subtitle: "Play your own Wii U games. This takes a minute and you can skip any step.",
            hero: .mark
        ) {
            EmptyView()
        }
    }
}

// MARK: - Page 2: Your keys

private struct OnboardingKeysPage: View {
    /// Advances the flow like "Next".
    var onSkip: () -> Void

    @State private var hasKeys = WiiUKeys.keysFileExists()
    @State private var keyCount = OnboardingKeysPage.currentKeyCount()
    @State private var errorMessage: String?

    var body: some View {
        OnboardingPageScaffold(
            title: "Your keys",
            subtitle: "Encrypted Wii U games need a keys.txt dumped from your own Wii U. MuffinEMU doesn't include one. Homebrew doesn't need it.",
            hero: .symbol("key.fill")
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
                            .foregroundColor(MuffinTheme.alertText)
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
        // DocumentImport's completion runs on the main thread (a picker delegate callback).
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

    /// Same count as KeysSettingsSection. The bridge can only answer once the engine has been
    /// initialized (see cemu_bridge_reload_and_count_keys in CemuBridge.h); before that, read
    /// the file directly through WiiUKeys.
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
            subtitle: "Import games from Files: .wud, .wux, .wua, .iso, a dumped game folder or a homebrew .rpx. You can also drop them into Documents/Roms in the Files app.",
            hero: .symbol("square.and.arrow.down.fill")
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
                            .foregroundColor(MuffinTheme.alertText)
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
            Task { @MainActor in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        try await gameManager.importROM(from: url)
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Page 4: Speed and controls

private struct OnboardingSpeedControlsPage: View {
    var body: some View {
        OnboardingPageScaffold(
            title: "Speed and controls",
            subtitle: "Three things affect speed and control:",
            hero: .symbol("bolt.fill")
        ) {
            MuffinCard {
                VStack(alignment: .leading, spacing: 18) {
                    OnboardingFactRow(
                        systemImage: "bolt.fill",
                        text: "Full speed needs a JIT enabler (StikJIT, SideStore or LiveContainer) attached at launch. Without one, MuffinEMU still runs but much slower. Settings shows which you have."
                    )
                    OnboardingFactRow(
                        systemImage: "checkmark.seal.fill",
                        text: "If a game glitches, desyncs or crashes, turn on Favour accuracy in Settings > CPU. It's slower but more accurate."
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
