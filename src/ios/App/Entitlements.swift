import Foundation

/// True once the player has unlocked premium with an unlock code. Gates the pro app icons.
enum Entitlements {
    static var hasProPlan: Bool {
        PremiumUnlock.isUnlocked
    }
}
