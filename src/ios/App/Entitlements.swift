import Foundation

/// Gates paid-tier features (currently just the 3 "pro" app icons). No IAP/StoreKit
/// system is wired up yet in this app - this stub exists so the icon picker has a
/// single real check to call instead of silently unlocking pro content.
///
/// TODO(monetization): replace with a real StoreKit 2 entitlement check
/// (Transaction.currentEntitlements) once in-app purchases are set up.
enum Entitlements {
    /// Wired to the unlock-code system, which is the only way to get premium in this
    /// app - there is no StoreKit product to buy.
    ///
    /// This returned a hardcoded `false` before, which meant redeeming a valid code did
    /// visibly nothing: PremiumUnlock.attemptUnlock() accepted the code and persisted
    /// muffin.premium.unlocked, the Settings row flipped to "Premium unlocked", and the
    /// pro icons stayed greyed out anyway, because the icon picker asks this and this
    /// never said yes. Two correct halves of one feature that were never connected -
    /// PremiumUnlock's own header even records that nothing read isUnlocked yet.
    static var hasProPlan: Bool {
        PremiumUnlock.isUnlocked
    }
}
