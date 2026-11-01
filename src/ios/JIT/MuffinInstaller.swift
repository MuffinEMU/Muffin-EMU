// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.
//
// MuffinInstaller, app side: MuffinEMU signs and installs itself with the person's own Apple ID,
// on this device, over the tunnel built-in JIT uses (LocalDevVPN + a pairing file). The work is in
// the device-link library (jit/muffin-jit/src/installer.rs, on isideload, MIT); this file opens it,
// answers its two-factor prompts, and keeps the Apple ID in the Keychain.
//
// The library lives in MuffinJITPairing.framework, embedded but not linked (it needs iOS 17.4 and
// the app supports 15), so it's opened with dlopen, as on-device pairing does.

import Foundation
import Security

enum MuffinInstaller {
    // MARK: What the app knows about how it was installed

    /// How MuffinInstaller last installed this copy: "appleID", "certificate" or "signedIPA". Nil when another tool
    /// (SideStore, AltStore, TrollStore, a computer) did.
    static let methodKey = "muffin.installer.method"
    static let lastInstallKey = "muffin.installer.lastInstall"
    static let appleIDKey = "muffin.installer.appleID"
    static let teamKey = "muffin.installer.team"
    static let anisetteKey = "muffin.installer.anisetteURL"
    static let autoRefreshKey = "muffin.installer.autoRefresh"
    /// With automatic refresh on: install a newer release instead of only re-signing this copy.
    static let autoUpdateKey = "muffin.installer.autoUpdate"

    static var method: String? { UserDefaults.standard.string(forKey: methodKey) }
    static var appleID: String? { UserDefaults.standard.string(forKey: appleIDKey) }
    static var isSignedIn: Bool { appleID.map { Keychain.password(for: $0) != nil } ?? false }

    /// The person's own certificate (.p12) and profile, kept for refreshes; its password is in the Keychain.
    static var certificateURL: URL { storageDirectory.appendingPathComponent("certificate.p12") }
    static var profileURL: URL { storageDirectory.appendingPathComponent("certificate.mobileprovision") }
    static let certificateAccount = "own-certificate"
    static var hasCertificate: Bool {
        FileManager.default.fileExists(atPath: certificateURL.path) && FileManager.default.fileExists(atPath: profileURL.path)
    }
    /// Refresh and Update work when MuffinInstaller can sign: with the Apple ID, or with a stored certificate.
    static var canSign: Bool { isSignedIn || hasCertificate }

    /// iOS 17.4 or later with the device-link framework in the app.
    static var isAvailable: Bool {
        guard #available(iOS 17.4, *) else { return false }
        return FileManager.default.fileExists(atPath: libraryPath)
    }

    private static var libraryPath: String {
        (Bundle.main.privateFrameworksPath ?? "") + "/MuffinJITPairing.framework/MuffinJITPairing"
    }

    /// Where the signing key, certificate and anisette state live. Not backed up to iCloud.
    static var storageDirectory: URL {
        var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MuffinInstaller", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    enum Failure: LocalizedError {
        case unavailable, notSignedIn, noPairing, failed(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: return "MuffinInstaller needs iOS 17.4 or later."
            case .notSignedIn: return "Sign in with your Apple ID first."
            case .noPairing: return "MuffinInstaller needs a pairing file. Settings > JIT > Built-in JIT has one."
            case .failed(let message): return message
            }
        }
    }

    // MARK: The library

    private typealias ProgressFn = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void
    private typealias TwoFactorFn = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?,
                                                    UnsafeMutablePointer<CChar>?, Int) -> Int32
    private typealias SignInFn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
                                                 UnsafePointer<CChar>?, TwoFactorFn?, UnsafeMutableRawPointer?,
                                                 UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
                                                 UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    private typealias ConnectFn = @convention(c) (UnsafePointer<UInt8>?, Int, UnsafePointer<CChar>?, UInt16, Int32,
                                                  ProgressFn?, UnsafeMutableRawPointer?,
                                                  UnsafeMutablePointer<OpaquePointer?>?,
                                                  UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    private typealias LinkFreeFn = @convention(c) (OpaquePointer?) -> Void
    private typealias SignAndInstallFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
                                                         UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
                                                         TwoFactorFn?, UnsafeMutableRawPointer?, ProgressFn?,
                                                         UnsafeMutableRawPointer?,
                                                         UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    private typealias InstallSignedFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
                                                        ProgressFn?, UnsafeMutableRawPointer?,
                                                        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    private typealias StringFreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
    private typealias SignWithCertificateFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?,
                                                              UnsafePointer<UInt8>?, Int, UnsafePointer<CChar>?,
                                                              UnsafePointer<UInt8>?, Int, ProgressFn?,
                                                              UnsafeMutableRawPointer?,
                                                              UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
                                                              UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

    private static func symbol<T>(_ name: String, as type: T.Type) throws -> T {
        guard isAvailable, let handle = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL),
              let sym = dlsym(handle, name) else { throw Failure.unavailable }
        return unsafeBitCast(sym, to: type)
    }

    private static func takeError(_ err: UnsafeMutablePointer<CChar>?, status: Int32) throws -> Never {
        let message = err.map { String(cString: $0) } ?? "it stopped with code \(status)"
        if let err, let free = try? symbol("muffin_jit_string_free", as: StringFreeFn.self) { free(err) }
        throw Failure.failed(message.prefix(1).uppercased() + message.dropFirst() + ".")
    }

    /// What a call reports while it runs, and how it asks for a two-factor code. Called on the main queue.
    struct Callbacks {
        var step: (String) -> Void
        /// Asks for the code Apple sent (by text to the number given, or to the person's devices when nil).
        /// Reply with the code, `.sendToDevices`, or nil to cancel.
        var askCode: (_ textedTo: String?, _ reply: @escaping (CodeAnswer?) -> Void) -> Void
    }

    enum CodeAnswer { case code(String), sendToDevices }

    /// Context passed to C for one call; blocks the library's thread while the person types a code.
    private final class Session {
        let callbacks: Callbacks
        init(_ callbacks: Callbacks) { self.callbacks = callbacks }
    }

    private static let onStep: ProgressFn = { ctx, _, message in
        guard let ctx, let message else { return }
        let session = Unmanaged<Session>.fromOpaque(ctx).takeUnretainedValue()
        let text = String(cString: message)
        DispatchQueue.main.async { session.callbacks.step(text) }
    }

    private static let onTwoFactor: TwoFactorFn = { ctx, viaSMS, destination, out, cap in
        guard let ctx, let out, cap > 1 else { return 0 }
        let session = Unmanaged<Session>.fromOpaque(ctx).takeUnretainedValue()
        let textedTo = viaSMS != 0 ? destination.map { String(cString: $0) } : nil
        let done = DispatchSemaphore(value: 0)
        var answer: CodeAnswer?
        DispatchQueue.main.async {
            session.callbacks.askCode(textedTo) { reply in
                answer = reply
                done.signal()
            }
        }
        done.wait()
        switch answer {
        case .code(let code):
            let bytes = Array(code.utf8.prefix(cap - 1))
            for (i, b) in bytes.enumerated() { out[i] = CChar(bitPattern: b) }
            out[bytes.count] = 0
            return 1
        case .sendToDevices: return 2
        case nil: return 0
        }
    }

    private static var anisetteURL: String? {
        let url = UserDefaults.standard.string(forKey: anisetteKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return url.isEmpty ? nil : url
    }

    // MARK: Calls (each blocks: run them off the main thread)

    /// Checks the Apple ID and password, asking for a two-factor code if Apple wants one. On success
    /// the password goes into the Keychain and the team name is returned.
    static func signIn(appleID: String, password: String, callbacks: Callbacks) throws -> String {
        let fn = try symbol("muffin_installer_sign_in", as: SignInFn.self)
        let session = Session(callbacks)
        let ctx = Unmanaged.passRetained(session).toOpaque()
        defer { Unmanaged<Session>.fromOpaque(ctx).release() }
        var team: UnsafeMutablePointer<CChar>?
        var err: UnsafeMutablePointer<CChar>?
        let status = fn(appleID, password, anisetteURL, storageDirectory.path, onTwoFactor, ctx, &team, &err)
        guard status == 0 else { try takeError(err, status: status) }
        let name = team.map { String(cString: $0) } ?? ""
        if let team, let free = try? symbol("muffin_jit_string_free", as: StringFreeFn.self) { free(team) }
        try Keychain.setPassword(password, for: appleID)
        UserDefaults.standard.set(appleID, forKey: appleIDKey)
        UserDefaults.standard.set(name, forKey: teamKey)
        return name
    }

    static func signOut() {
        if let id = appleID { Keychain.removePassword(for: id) }
        UserDefaults.standard.removeObject(forKey: appleIDKey)
        UserDefaults.standard.removeObject(forKey: teamKey)
        UserDefaults.standard.removeObject(forKey: autoRefreshKey)
    }

    /// Opens the tunnel to this device with the stored pairing file, runs `body` with it, closes it.
    private static func withLink<T>(_ session: Session, _ body: (OpaquePointer) throws -> T) throws -> T {
        guard let pairing = JITPairing.read() else { throw Failure.noPairing }
        let connect = try symbol("muffin_jit_connect", as: ConnectFn.self)
        let free = try symbol("muffin_jit_link_free", as: LinkFreeFn.self)
        let ctx = Unmanaged.passUnretained(session).toOpaque()
        var link: OpaquePointer?
        var err: UnsafeMutablePointer<CChar>?
        let status = pairing.withUnsafeBytes { raw in
            connect(raw.bindMemory(to: UInt8.self).baseAddress, pairing.count, JITHelperRequest.defaultDeviceIP,
                    JITHelperRequest.defaultRSDPort, JITEnvironment.usesCryptexDDI ? 1 : 0, onStep, ctx, &link, &err)
        }
        guard status == 0, let link else { try takeError(err, status: status) }
        defer { free(link) }
        return try body(link)
    }

    /// The signer edits an .app folder in place (an .ipa it unpacks into a temporary folder itself), and an
    /// installed app's own folder is read-only, so an .app is copied to a temporary folder first.
    private static func workingCopy(of appPath: URL) throws -> URL {
        guard appPath.pathExtension == "app" else { return appPath }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MuffinInstallerSign", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(appPath.lastPathComponent)
        try FileManager.default.copyItem(at: appPath, to: copy)
        return copy
    }

    /// Signs `appPath` (an .app or .ipa) with the signed-in Apple ID and installs it. For MuffinEMU's own
    /// bundle that's a refresh; for a downloaded release, an update. iOS closes the app when it installs.
    static func signAndInstall(appPath: URL, callbacks: Callbacks) throws {
        guard let id = appleID, let password = Keychain.password(for: id) else { throw Failure.notSignedIn }
        let fn = try symbol("muffin_installer_sign_and_install", as: SignAndInstallFn.self)
        let source = try workingCopy(of: appPath)
        let session = Session(callbacks)
        let ctx = Unmanaged.passRetained(session).toOpaque()
        defer { Unmanaged<Session>.fromOpaque(ctx).release() }
        try withLink(session) { link in
            var err: UnsafeMutablePointer<CChar>?
            // Marked before the call: a successful install ends this process before it returns.
            UserDefaults.standard.set("appleID", forKey: methodKey)
            UserDefaults.standard.set(Date(), forKey: lastInstallKey)
            let status = fn(link, id, password, anisetteURL, storageDirectory.path, source.path,
                            onTwoFactor, ctx, onStep, ctx, &err)
            guard status == 0 else { try takeError(err, status: status) }
        }
    }

    /// Keeps the person's own certificate, profile and its password for refreshes.
    static func storeCertificate(p12: Data, password: String, profile: Data) throws {
        try p12.write(to: certificateURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try profile.write(to: profileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try Keychain.setPassword(password, for: certificateAccount)
    }

    static func removeCertificate() {
        try? FileManager.default.removeItem(at: certificateURL)
        try? FileManager.default.removeItem(at: profileURL)
        Keychain.removePassword(for: certificateAccount)
    }

    /// Signs `appPath` with the stored certificate and profile and installs it. Returns a note when the
    /// profile is for one exact app ID (the JIT helper extension is then left out).
    @discardableResult
    static func signWithCertificateAndInstall(appPath: URL, callbacks: Callbacks) throws -> String? {
        guard let p12 = try? Data(contentsOf: certificateURL), let profile = try? Data(contentsOf: profileURL) else {
            throw Failure.failed("Add your certificate and profile first.")
        }
        let password = Keychain.password(for: certificateAccount) ?? ""
        let fn = try symbol("muffin_installer_sign_with_certificate_and_install", as: SignWithCertificateFn.self)
        let session = Session(callbacks)
        let ctx = Unmanaged.passRetained(session).toOpaque()
        defer { Unmanaged<Session>.fromOpaque(ctx).release() }
        let source = try workingCopy(of: appPath)
        return try withLink(session) { link -> String? in
            var note: UnsafeMutablePointer<CChar>?
            var err: UnsafeMutablePointer<CChar>?
            UserDefaults.standard.set("certificate", forKey: methodKey)
            UserDefaults.standard.set(Date(), forKey: lastInstallKey)
            let status = p12.withUnsafeBytes { p12Raw in
                profile.withUnsafeBytes { profileRaw in
                    fn(link, source.path, p12Raw.bindMemory(to: UInt8.self).baseAddress, p12.count, password,
                       profileRaw.bindMemory(to: UInt8.self).baseAddress, profile.count, onStep, ctx, &note, &err)
                }
            }
            guard status == 0 else { try takeError(err, status: status) }
            let text = note.map { String(cString: $0) }
            if let note, let free = try? symbol("muffin_jit_string_free", as: StringFreeFn.self) { free(note) }
            return text
        }
    }

    /// Re-signs and installs `appPath` with whichever way MuffinInstaller signs: the stored certificate if
    /// that's how it was last installed, otherwise the Apple ID.
    static func resign(appPath: URL, callbacks: Callbacks) throws {
        if (method == "certificate" || !isSignedIn), hasCertificate {
            try signWithCertificateAndInstall(appPath: appPath, callbacks: callbacks)
        } else {
            try signAndInstall(appPath: appPath, callbacks: callbacks)
        }
    }

    /// Installs an already signed IPA unchanged.
    static func installSigned(ipa: URL, callbacks: Callbacks) throws {
        let fn = try symbol("muffin_installer_install_signed", as: InstallSignedFn.self)
        let session = Session(callbacks)
        let ctx = Unmanaged.passRetained(session).toOpaque()
        defer { Unmanaged<Session>.fromOpaque(ctx).release() }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MuffinInstallerUnpack", isDirectory: true)
        try withLink(session) { link in
            var err: UnsafeMutablePointer<CChar>?
            UserDefaults.standard.set("signedIPA", forKey: methodKey)
            UserDefaults.standard.set(Date(), forKey: lastInstallKey)
            let status = fn(link, ipa.path, work.path, onStep, ctx, &err)
            guard status == 0 else { try takeError(err, status: status) }
        }
    }

    /// One published MuffinEMU release with its unsigned IPA.
    struct Release: Identifiable, Hashable {
        let tag: String
        let version: String
        let title: String
        let published: Date?
        let isPrerelease: Bool
        let ipa: URL
        var id: String { tag }
    }

    /// The releases on GitHub that carry MuffinEMU.ipa, newest first: numbered releases and the rolling
    /// nightly. Empty when GitHub can't be reached.
    static func releases() async -> [Release] {
        guard let url = URL(string: "https://api.github.com/repos/MuffinEMU/Muffin-EMU/releases?per_page=40") else { return [] }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let fetched = try? await URLSession.shared.data(for: request)
        guard let data = fetched?.0,
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return list.compactMap { item in
            guard let tag = item["tag_name"] as? String, (item["draft"] as? Bool) != true,
                  !tag.hasPrefix("experimental"),
                  let assets = item["assets"] as? [[String: Any]],
                  let ipa = assets.first(where: { ($0["name"] as? String) == "MuffinEMU.ipa" }),
                  let link = (ipa["browser_download_url"] as? String).flatMap(URL.init(string:)) else { return nil }
            return Release(tag: tag,
                           version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                           title: item["name"] as? String ?? tag,
                           published: (item["published_at"] as? String).flatMap(iso.date(from:)),
                           isPrerelease: item["prerelease"] as? Bool ?? false,
                           ipa: link)
        }
    }

    /// "10.10" is newer than "10.9": compares dot-separated numbers.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// Downloads one release's MuffinEMU.ipa.
    static func download(_ release: Release) async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: release.ipa)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure.failed("Couldn't download MuffinEMU \(release.version).")
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("MuffinEMU-\(release.tag).ipa")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: temp, to: dest)
        return dest
    }

    /// Downloads the latest release's MuffinEMU.ipa (the unsigned build signers use).
    static func downloadLatestRelease() async throws -> URL {
        let source = URL(string: "https://github.com/MuffinEMU/Muffin-EMU/releases/latest/download/MuffinEMU.ipa")!
        let (temp, response) = try await URLSession.shared.download(from: source)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure.failed("Couldn't download the latest release.")
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("MuffinEMU-latest.ipa")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: temp, to: dest)
        return dest
    }

    /// The latest release's version from GitHub ("10.8"), or nil when it can't be read.
    static func latestReleaseVersion() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/MuffinEMU/Muffin-EMU/releases/latest") else { return nil }
        let fetched = try? await URLSession.shared.data(from: url)
        guard let data = fetched?.0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }
}

/// What this copy of MuffinEMU is signed with, read from its own embedded.mobileprovision. Works however it
/// was installed; TrollStore and ad-hoc installs have no profile and never expire.
struct InstalledSignature {
    let expires: Date?
    let teamName: String?
    let profileName: String?
    let isDevelopment: Bool

    static var current: InstalledSignature {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound],
                                                                     format: nil) as? [String: Any] else {
            return InstalledSignature(expires: nil, teamName: nil, profileName: nil, isDevelopment: false)
        }
        let entitlements = plist["Entitlements"] as? [String: Any]
        return InstalledSignature(expires: plist["ExpirationDate"] as? Date,
                                  teamName: plist["TeamName"] as? String,
                                  profileName: plist["Name"] as? String,
                                  isDevelopment: entitlements?["get-task-allow"] as? Bool ?? false)
    }

    var daysLeft: Int? {
        expires.map { Int(($0.timeIntervalSinceNow / 86_400).rounded(.down)) }
    }
}

/// The Apple ID password, in the Keychain, this device only.
enum Keychain {
    private static let service = "com.void.muffinemu.installer"

    static func setPassword(_ password: String, for account: String) throws {
        removePassword(for: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(password.utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw MuffinInstaller.Failure.failed("Couldn't save the password in the Keychain (\(status)).")
        }
    }

    static func password(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func removePassword(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
