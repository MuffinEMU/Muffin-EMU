import Foundation
import CryptoKit
import Security

/// Premium unlock codes.
///
/// WHAT THIS ACTUALLY DEFENDS AGAINST, stated plainly so nobody trusts it further
/// than it goes. The check runs on a device the user controls, and this app's
/// audience installs through TrollStore, which means filesystem access. Anything
/// computable on-device is forgeable on-device, and a determined person can patch
/// the binary. There is no client-side design that prevents that - only a server
/// that decides, which this app does not have.
///
/// So the goal is not "impossible". It is to move the bar from *read a comment*
/// to *reverse-engineer and patch the app*, which it does:
///
///  - GUESSING: dead. Codes carry 100 bits of entropy over a 32-character
///    alphabet. The previous code was MUFFIN-VIP-0001, which fell to brute force
///    from its hash alone in under a millisecond - the whole keyspace was 10,000
///    candidates because the format was guessable.
///  - READING THE SOURCE: dead. No plaintext code appears anywhere in this file
///    or in the binary. The old version printed the code in a comment directly
///    above its own hash.
///  - REVERSING A LEAKED HASH: PBKDF2-HMAC-SHA256, 200,000 iterations, salted.
///    Moot at 100 bits of entropy, but it costs nothing and means a future short
///    code does not become an instant loss.
///  - FLIPPING THE STORED FLAG: previously `UserDefaults.bool(forKey:)` - one
///    line in a plist editor, no code required at all. It is now a token bound to
///    a per-install random key, so forging it means running the HMAC rather than
///    typing `true`. A speed bump, not a wall, and deliberately not the load-
///    bearing part.
///
/// WHY THE TOKEN IS NOT KEYCHAIN-ONLY, which was the first attempt here.
/// Most of this app's users arrive through SideStore or LiveContainer, not
/// TrollStore, and keychain-only storage breaks under both:
///
///  - SideStore re-signs the IPA with the user's own certificate. A generic
///    password's default access group is derived from the signing Team ID, so an
///    item written under one identity is unreadable after a re-sign under
///    another. Switching install method, or re-signing with a different Apple ID,
///    silently loses the unlock.
///  - LiveContainer runs guest apps inside its own process and container, so
///    keychain semantics are the host's, shared across guests, and not
///    guaranteed to survive a LiveContainer update.
///
/// Losing a paid unlock every time someone changes how they install is a far
/// worse outcome than a determined person forging a token, so the token is
/// written to BOTH the keychain and UserDefaults and either is accepted. The
/// keychain copy is the durable one where it works; UserDefaults lives in the
/// app's data container and survives a re-sign.
///
/// This costs little, because storage was never where the security was. The real
/// property is that codes carry 100 bits of entropy and appear nowhere in the
/// binary - and that holds identically under TrollStore, SideStore and
/// LiveContainer.
enum PremiumUnlock {
    private static let service = "com.cemu.Cemu.premium"
    private static let account = "unlock"
    private static let tokenKey = "muffin.premium.token"
    private static let installKeyDefaultsKey = "muffin.premium.ik"

    /// Salt and iteration count are public by construction - they are in the
    /// binary either way. They are not secrets; the entropy of the code is.
    /// The salt, as the 16 RAW BYTES the hex spells - NOT the ASCII of the hex string.
    ///
    /// The generator that produced the stored hashes salted with the decoded bytes
    /// (Python `bytes.fromhex`). Salting with `Data("...".utf8)` fed PBKDF2 a
    /// different 32-byte salt, so every hash came out different and every valid
    /// code would have been rejected - with no error a user could act on, because
    /// "that code didn't work" is all the UI can say.
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
        // Constant-time-ish: compare against every entry rather than returning on
        // the first match, so response time carries no information about which
        // code was close. The set is tiny, so this costs nothing.
        var matched = false
        for known in validCodeHashes where constantTimeEquals(known, candidate) { matched = true }
        guard matched else { return false }
        let token = expectedToken()
        keychainWrite(token)
        UserDefaults.standard.set(token, forKey: tokenKey)
        return true
    }

    // MARK: - derivation

    /// PBKDF2-HMAC-SHA256, implemented on CryptoKit rather than CommonCrypto.
    ///
    /// CommonCrypto needs `import CommonCrypto`, which is a module this target does
    /// not link, and its C pointer API does not bridge cleanly from a Swift
    /// `[UInt8]` - the first attempt failed the build on both counts
    /// (`cannot find 'CCKeyDerivationPBKDF' in scope`, and `UnsafePointer<UInt8>`
    /// has no `assumingMemoryBound`). CryptoKit is already imported, already used
    /// for the HMAC below, and is pure Swift at the call site.
    ///
    /// This is the standard construction from RFC 2898: for each block, U1 = PRF
    /// (password, salt || INT(i)), then U2..Uc = PRF(password, U(n-1)), all XORed
    /// together. One block is enough - SHA-256 gives 32 bytes and that is the whole
    /// output length.
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

    /// The value stored on unlock. Bound to a per-install random key held in the
    /// Keychain, so the stored blob is useless on any other device and cannot be
    /// shared around as a "patch".
    private static func expectedToken() -> String {
        let key = SymmetricKey(data: installKey())
        let mac = HMAC<SHA256>.authenticationCode(for: Data("premium-v2".utf8), using: key)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    private static func installKey() -> Data {
        // Same reasoning as the token: if this is keychain-only it does not survive
        // a re-sign, and then expectedToken() changes and a legitimately unlocked
        // user is locked out through no action of their own.
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
