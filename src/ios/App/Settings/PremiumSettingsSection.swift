import SwiftUI

/// The only paid tier in the app - see Entitlements.hasProPlan and
/// IconManifest.isPro. There is no StoreKit product; PremiumUnlock is the entire
/// purchase path, and what it unlocks is exactly the pro-tier app icons, nothing
/// else in the app is gated.
struct PremiumSettingsSection: View {
    @State private var premiumUnlocked = PremiumUnlock.isUnlocked
    @State private var premiumCodeInput = ""
    @State private var premiumCodeError: String?

    var body: some View {
        Section {
            if premiumUnlocked {
                // The one moment in Settings that is a reward rather than a control, so
                // it gets the muffin-top gradient treatment the app's primary buttons
                // use - the same ink the brand spends on "yes, this worked".
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(MuffinTheme.sparkleCream)
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
                            .foregroundColor(.secondary)
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

                    // MuffinPrimaryButtonStyle rather than a plain Form button: this is
                    // the only purchase action in the app, and on iOS 26 that style is
                    // real Liquid Glass tinted muffin-top, which is exactly the weight a
                    // paid-tier call to action should carry.
                    Button("Unlock") {
                        if PremiumUnlock.attemptUnlock(code: premiumCodeInput) {
                            premiumUnlocked = true
                            premiumCodeInput = ""
                            premiumCodeError = nil
                        } else {
                            premiumCodeError = "That code didn't work."
                        }
                    }
                    .buttonStyle(MuffinPrimaryButtonStyle())
                    .disabled(premiumCodeInput.isEmpty)
                    .opacity(premiumCodeInput.isEmpty ? 0.5 : 1.0)

                    if let premiumCodeError {
                        Text(premiumCodeError)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
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
