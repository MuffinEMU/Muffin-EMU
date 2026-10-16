// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.


import SwiftUI

/// Where the community Discord invite lives. The card in the library and the Import menu's
/// "Discord" row open the same page, which redirects to the current invite.
enum DiscordInvite {
    static let url = URL(string: "https://muffinemu.github.io/MuffinEMU/discord")!

    /// Own key: nothing else reads or writes it, and it is separate from the onboarding flag.
    static let dismissedKey = "muffin.discordCard.dismissed"
}

/// A one-time card above the library inviting people to the Discord. Joining or closing it
/// sets DiscordInvite.dismissedKey, so it never comes back; the Import menu keeps a row for
/// anyone who wants the link later.
struct DiscordInviteCard: View {
    let onDismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        MuffinCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Join the MuffinEMU Discord")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(MuffinTheme.brownDarkest)
                    Text("Get help with setup, report how games run and try beta builds.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(MuffinTheme.brownMid)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Join") {
                        openURL(DiscordInvite.url)
                        onDismiss()
                    }
                    .buttonStyle(MuffinPrimaryButtonStyle())
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MuffinTheme.brownMid)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                // Pulls the 44pt target into the corner without growing the card.
                .padding(.top, -10)
                .padding(.trailing, -10)
            }
            .padding(14)
        }
        .padding(.horizontal, 16)
    }
}
