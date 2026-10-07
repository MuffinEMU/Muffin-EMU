// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

/// The library entry for the Wii U Menu, pinned above the game grid so it reads as the
/// console's own home rather than one more game. Shown only while a Menu title is
/// installed (Settings > Wii U Menu) and not hidden there. Tapping it checks the pieces the
/// Menu is known not to work without and, if any are missing, says which before launching.
/// With "Show Wii U Menu as a game card" on, WiiUMenuCard (below) takes its place in the grid.
struct WiiUMenuTile: View {
    @ObservedObject private var store = WiiUMenuStore.shared
    let onLaunch: (GameMetadata) -> Void
    @State private var showingPreflight = false

    var body: some View {
        if let entry = WiiUMenu.libraryEntry(for: store.status) {
            Button(action: { attemptLaunch(entry) }) {
                HStack(spacing: 14) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(colors: [MuffinTheme.pixelBlue, MuffinTheme.blueberryNavy],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Wii U Menu")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(MuffinTheme.brownDarkest)
                        Text(subtitle(entry))
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(MuffinTheme.brownMid)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Text("Experimental")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(MuffinTheme.cautionText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(MuffinTheme.cautionText, lineWidth: 1))
                    Image(systemName: "play.fill")
                        .foregroundColor(MuffinTheme.accentText)
                }
                .padding(12)
                .background(MuffinTheme.cream)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MuffinTheme.pixelBlue, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .accessibilityLabel("Wii U Menu, experimental")
            .wiiuMenuPreflightAlert(isPresented: $showingPreflight, missing: store.status.missingRequired) {
                onLaunch(entry)
            }
        }
    }

    private func subtitle(_ entry: GameMetadata) -> String {
        let missing = store.status.missingRequired
        if missing.isEmpty {
            return "\(entry.region ?? "System") - your games appear in it"
        }
        return "Missing files - tap for details"
    }

    private func attemptLaunch(_ entry: GameMetadata) {
        store.refresh()
        if store.status.missingRequired.isEmpty {
            onLaunch(entry)
        } else {
            showingPreflight = true
        }
    }
}

/// The Menu as a card in the game grid, the same size and shape as a game's card. Used
/// instead of WiiUMenuTile when Settings > Wii U Menu > "Show Wii U Menu as a game card" is on.
/// The caller only adds it while a Menu title is installed.
struct WiiUMenuCard: View {
    @ObservedObject private var store = WiiUMenuStore.shared
    let onLaunch: (GameMetadata) -> Void
    @State private var showingPreflight = false

    var body: some View {
        if let entry = WiiUMenu.libraryEntry(for: store.status) {
            VStack(spacing: 0) {
                cover
                details(entry)
            }
            .background(MuffinTheme.cream)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MuffinTheme.pixelBlue, lineWidth: 2)
            )
            .shadow(color: MuffinTheme.shadow.opacity(0.15), radius: 8, x: 0, y: 4)
            .wiiuMenuPreflightAlert(isPresented: $showingPreflight, missing: store.status.missingRequired) {
                onLaunch(entry)
            }
        }
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [MuffinTheme.pixelBlue, MuffinTheme.blueberryNavy],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "house.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(.white)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
    }

    private func details(_ entry: GameMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wii U Menu")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .foregroundColor(MuffinTheme.brownDarkest)
            HStack(spacing: 8) {
                Text("Experimental")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(MuffinTheme.cautionText)
                Spacer()
            }
            Button(action: { attemptLaunch(entry) }) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Play")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(MuffinPrimaryButtonStyle())
            .accessibilityLabel("Play the Wii U Menu, experimental")
        }
        .padding(12)
        .background(MuffinTheme.cream)
    }

    private func attemptLaunch(_ entry: GameMetadata) {
        store.refresh()
        if store.status.missingRequired.isEmpty {
            onLaunch(entry)
        } else {
            showingPreflight = true
        }
    }
}

private extension View {
    /// The "may not start" warning shared by the bar and the card.
    func wiiuMenuPreflightAlert(isPresented: Binding<Bool>, missing: [String], launchAnyway: @escaping () -> Void) -> some View {
        alert("The Wii U Menu may not start", isPresented: isPresented) {
            Button("Launch anyway", action: launchAnyway)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Missing: " + missing.joined(separator: ", ")
                 + ".\n\nImport them in Settings > Wii U Menu. Without them the Menu is likely to crash a few seconds in.")
        }
    }
}
