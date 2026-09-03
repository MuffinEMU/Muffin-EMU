import Foundation
import CryptoKit

/// A hidden unlock-code system Void asked for as its own thing - "top-secret premium
/// unlock codes that unlock premium" - not tied to any store or purchase, since this app
/// has neither. A code is valid if its SHA-256 matches one of the hashes below; the raw
/// codes themselves are never stored in the binary, only their hashes, so `strings` on
/// the shipped app doesn't hand out working codes for free.
///
/// "Premium" itself gates nothing yet - no feature currently checks
/// PremiumUnlock.isUnlocked - because nothing was specified for it to gate. It exists so
/// there's a real switch to build against once there's something to attach it to,
/// exactly as asked: an unlock system, plus one real working code.
enum PremiumUnlock {
    private static let unlockedKey = "muffin.premium.unlocked"

    /// SHA-256 hex digests of valid codes. Add more the same way: uppercase and strip
    /// whitespace/dashes from the raw code first (normalize(_:) does this identically
    /// for a submitted code), then hash that normalized string.
    private static let validCodeHashes: Set<String> = [
        // MUFFIN-VIP-0001 - actual SHA-256 of the normalized string "MUFFINVIP0001",
        // computed with `shasum -a 256`, not invented.
        "f3fd64b76f9e144a5127d50f8f62a4c3582cb103fcf5f02724f555b0bd6991bc",
    ]

    static var isUnlocked: Bool {
        UserDefaults.standard.bool(forKey: unlockedKey)
    }

    /// Uppercases and strips whitespace/dashes, so "muffin-vip-0001", "MUFFIN VIP 0001"
    /// and "MUFFINVIP0001" all check the same code - a code is something typed on a
    /// phone keyboard, and formatting shouldn't be the part that has to be exact.
    private static func normalize(_ code: String) -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Checks `code` and, if valid, persists the unlock and returns true. Returns false
    /// (and changes nothing) for anything that doesn't match - no partial credit, no
    /// hint about how close it was.
    @discardableResult
    static func attemptUnlock(code: String) -> Bool {
        let hash = sha256Hex(normalize(code))
        guard validCodeHashes.contains(hash) else { return false }
        UserDefaults.standard.set(true, forKey: unlockedKey)
        return true
    }
}
