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
                Label("Premium unlocked", systemImage: "sparkles")
                    .foregroundColor(MuffinTheme.brownDarkest)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Unlock code", text: $premiumCodeInput)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        #endif
                    Button("Unlock") {
                        if PremiumUnlock.attemptUnlock(code: premiumCodeInput) {
                            premiumUnlocked = true
                            premiumCodeInput = ""
                            premiumCodeError = nil
                        } else {
                            premiumCodeError = "That code didn't work."
                        }
                    }
                    .disabled(premiumCodeInput.isEmpty)
                    if let premiumCodeError {
                        Text(premiumCodeError)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("Premium")
        } footer: {
            Text("Unlocks the pro app icons. Everything else in MuffinEMU is free.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
