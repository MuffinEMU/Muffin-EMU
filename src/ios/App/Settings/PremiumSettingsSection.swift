// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

/// Unlock code entry. PremiumUnlock only gates the pro-tier app icons (see
/// Entitlements.hasProPlan and IconManifest.isPro); nothing else in the app is gated.
struct PremiumSettingsSection: View {
    @State private var premiumUnlocked = PremiumUnlock.isUnlocked
    @State private var premiumCodeInput = ""
    @State private var premiumCodeError: String?
    @State private var isCheckingCode = false

    var body: some View {
        Section {
            if premiumUnlocked {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MuffinTheme.onMuffinTop)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(MuffinTheme.muffinTopGradient)
                        )
                        .shadow(color: MuffinTheme.shadow.opacity(0.25), radius: 4, x: 0, y: 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Premium unlocked")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(MuffinTheme.brownDarkest)
                        Text("The pro app icons are yours.")
                            .font(.system(size: 12))
                            .foregroundColor(MuffinTheme.secondaryText)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Unlock code", text: $premiumCodeInput)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        #endif
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(MuffinTheme.wrapper.opacity(0.35))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(premiumCodeError == nil ? MuffinTheme.wrapper : Color.red.opacity(0.6),
                                        lineWidth: 1)
                        )

                    Button {
                        let code = premiumCodeInput
                        isCheckingCode = true
                        Task { @MainActor in
                            let ok = await PremiumUnlock.attemptUnlockOffMain(code: code)
                            isCheckingCode = false
                            if ok {
                                premiumUnlocked = true
                                premiumCodeInput = ""
                                premiumCodeError = nil
                            } else {
                                premiumCodeError = "That code didn't work."
                            }
                        }
                    } label: {
                        if isCheckingCode {
                            ProgressView()
                        } else {
                            Text("Unlock")
                        }
                    }
                    // No extra opacity here: the button style already dims itself when
                    // disabled, and the two together took the label down to about 22%.
                    .buttonStyle(MuffinPrimaryButtonStyle())
                    .disabled(premiumCodeInput.isEmpty || isCheckingCode)

                    if let premiumCodeError {
                        Text(premiumCodeError)
                            .font(.system(size: 12))
                            .foregroundColor(MuffinTheme.alertText)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            SettingsSectionHeader("Premium", icon: "sparkles", accent: .identity)
        } footer: {
            InfoButton.footer("Unlocks the pro app icons. Everything else in MuffinEMU is free.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
