import Foundation
import CryptoKit
import Security

/// Premium unlock codes.
///
/// The check runs on the user's device, so it can be patched or forged locally; only a
/// server could prevent that. It stops casual bypasses: codes are 100 bits of entropy
/// stored only as salted PBKDF2-HMAC-SHA256 hashes (200,000 rounds), and the stored unlock
/// is a token bound to a per-install key rather than a plain flag.
///
/// The token and install key are written to both the Keychain and UserDefaults, and either
/// is accepted: Keychain access groups change when an app is re-signed (SideStore) or run
/// inside LiveContainer, and the unlock must survive that.
enum PremiumUnlock {
    private static let service = "com.cemu.Cemu.premium"
    private static let account = "unlock"
    private static let tokenKey = "muffin.premium.token"
    private static let installKeyDefaultsKey = "muffin.premium.ik"

    /// Salt and iteration count aren't secrets. The salt is the 16 raw bytes (not the ASCII
    /// of a hex string), matching the generator that produced the stored hashes.
    private static let salt = Data([0x86, 0x6c, 0x34, 0x12, 0x4d, 0x50, 0xb5, 0x9e, 0x6c, 0xe5, 0xcc, 0x08, 0x28, 0x3e, 0x00, 0x19])
    private static let iterations = 200000

    /// PBKDF2-HMAC-SHA256 of the normalized code. Codes themselves never appear.
    private static let validCodeHashes: Set<String> = [
        "6c275c666ac816935a8845d593f16d9ad0253707644be53245027d9e22297e36",
        "012736f26112dc7250768c2d6f67408955ad9855098cd0fd7a51d414343e13f2",
        "b0557fedaf5109f8b7b8f8cbcf8515e9179a55c8a401b11d3c79759c3e35f773",
        "30672730a081ad0a4bc1f39619471a56c73bf4657b7eee669bbd4cd5245dbf68",
        "cfd40cd0419ea025b43a35a242ea88d3e5965fb329e6bb4254a0afc8c4827c55",
        "1a945ab350f3356a7ac68f69c6568e29429f8cfd67b5d5929b1f3dac013503cd",
        "17f6719b1e31212193b4356e77f241248dad80a49f1bf938d1010c3ca2bbc7aa",
        "d1cc7b7020654e58d2ca4051df6a85c506dae714039b9938801a5d30ac34e3b9",
        "b76c370d93223d1abf9efc74ff92d971fab2fe1f24a4b5c7e88b70592a2f3df7",
    ]

    static var isUnlocked: Bool {
        let want = expectedToken()
        if let k = keychainRead(), constantTimeEquals(k, want) { return true }
        if let d = UserDefaults.standard.string(forKey: tokenKey), constantTimeEquals(d, want) { return true }
        return false
    }

    /// Uppercases and drops anything that is not a letter or digit, so
    /// "gv9j-bs5k-..." and "GV9J BS5K ..." check the same code. Formatting should
    /// not be the part that has to be exact when it is typed on a phone.
    private static func normalize(_ code: String) -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    @discardableResult
    static func attemptUnlock(code: String) -> Bool {
        let candidate = pbkdf2(normalize(code))
        // Compare against every entry rather than returning on the first match.
        var matched = false
        for known in validCodeHashes where constantTimeEquals(known, candidate) { matched = true }
        guard matched else { return false }
        let token = expectedToken()
        keychainWrite(token)
        UserDefaults.standard.set(token, forKey: tokenKey)
        return true
    }

    /// Same check as `attemptUnlock`, run off the main thread: the derivation is 200,000
    /// HMAC rounds and would freeze the UI if called from a button action.
    static func attemptUnlockOffMain(code: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            attemptUnlock(code: code)
        }.value
    }

    // MARK: - derivation

    /// PBKDF2-HMAC-SHA256 (RFC 2898) on CryptoKit; one 32-byte block is the whole output.
    private static func pbkdf2(_ s: String) -> String {
        let key = SymmetricKey(data: Data(s.utf8))
        var block = salt
        block.append(contentsOf: [0, 0, 0, 1])          // INT(1), big-endian
        var u = Data(HMAC<SHA256>.authenticationCode(for: block, using: key))
        var out = [UInt8](u)
        for _ in 1..<iterations {
            u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
            for (i, b) in u.enumerated() { out[i] ^= b }
        }
        return out.map { String(format: "%02x", $0) }.joined()
    }

    /// The value stored on unlock, bound to a per-install random key.
    private static func expectedToken() -> String {
        let key = SymmetricKey(data: installKey())
        let mac = HMAC<SHA256>.authenticationCode(for: Data("premium-v2".utf8), using: key)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    private static func installKey() -> Data {
        // Also kept in UserDefaults: a Keychain-only key wouldn't survive a re-sign.
        if let existing = keychainRead(account: "installkey"), let d = Data(base64Encoded: existing) {
            return d
        }
        if let s = UserDefaults.standard.string(forKey: installKeyDefaultsKey),
           let d = Data(base64Encoded: s) {
            return d
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let d = Data(bytes)
        keychainWrite(d.base64EncodedString(), account: "installkey")
        UserDefaults.standard.set(d.base64EncodedString(), forKey: installKeyDefaultsKey)
        return d
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    // MARK: - keychain

    private static func keychainRead(account acct: String = account) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainWrite(_ value: String, account acct: String = account) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
