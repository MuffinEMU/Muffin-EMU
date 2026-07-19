import Foundation

/// Gates paid-tier features (currently just the 3 "pro" app icons). No IAP/StoreKit
/// system is wired up yet in this app - this stub exists so the icon picker has a
/// single real check to call instead of silently unlocking pro content.
///
/// TODO(monetization): replace with a real StoreKit 2 entitlement check
/// (Transaction.currentEntitlements) once in-app purchases are set up.
enum Entitlements {
    static var hasProPlan: Bool {
        false
    }
}
