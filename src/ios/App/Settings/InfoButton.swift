// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

/// The full explanation behind an "i" in a settings footer. One short sentence stays inline;
/// the rest opens in a sheet.
///
/// A sheet rather than an alert because UIKit's alert text doesn't scroll on iOS 15.
struct InfoButton: View {
    let title: String
    let text: String
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .semibold))
                // The accent so it stands out from the grey footer text.
                .foregroundColor(MuffinTheme.accentText)
                // 30pt tap target around a 15pt glyph.
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("About \(title)")
        .sheet(isPresented: $showing) {
            // NavigationStack needs iOS 16+; this project's deployment target is 15.0.
            NavigationView {
                ZStack {
                    MuffinTheme.backgroundGradient
                        .ignoresSafeArea()

                    // On a card: straight on the gradient, brown text was dark on dark
                    // in the themes with a dark gradient.
                    ScrollView {
                        MuffinCard {
                            Text(text)
                                .font(.system(size: 15))
                                .lineSpacing(3)
                                .foregroundColor(MuffinTheme.brownDarkest)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                        }
                        .padding(16)
                    }
                }
                .navigationTitle(title)
                .muffinOpaqueNavigationBar()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showing = false }
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
    }
}

extension InfoButton {
    /// A footer row: a short inline sentence plus the "i" that opens the full explanation.
    static func footer(_ short: String, title: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            footerText(short)
            Spacer(minLength: 4)
            InfoButton(title: title, text: text)
                .padding(.trailing, -7)
        }
        .padding(.top, 2)
    }

    /// The same footer typography for a section with nothing to put behind an "i".
    static func footer(_ short: String) -> some View {
        footerText(short)
            .padding(.top, 2)
    }

    /// `lineSpacing` and `fixedSize` keep multi-line footers from truncating in a Form footer.
    private static func footerText(_ short: String) -> some View {
        Text(short)
            .font(.footnote)
            .foregroundColor(MuffinTheme.secondaryText)
            .lineSpacing(2.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}
