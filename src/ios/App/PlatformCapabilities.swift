import Foundation
#if os(iOS)
import UIKit
#endif

/// What the OS under us can do, asked by name instead of scattering raw version numbers.
///
/// Detection is a runtime question (`Running`, from `ProcessInfo`, independent of the SDK the
/// binary was built with). Calling an iOS 27-only API is a compile-time question: it needs an
/// iOS 27 SDK, so `SDK.hasIOS27` is keyed off the Swift compiler version and stays false on
/// older toolchains. The JIT/TXM handling for iOS 27 lives in CemuBridge.mm (`ios_has_txm()`).
///
/// Notes for iOS 27 (Apple's iOS & iPadOS 27 release notes):
/// - Apps built with the 27 SDK need a launch screen key in Info.plist; project.yml sets
///   `INFOPLIST_KEY_UILaunchScreen_Generation`, so don't remove it.
/// - iPad apps become continuously resizable regardless of supported orientations, so
///   `DisplayRouter.deviceContainerDidLayout(_:)` runs far more often during a Split View drag
///   (see `expectsContinuousIPadResize`).
/// - Non-interactive external display scenes are no longer offered automatically; the
///   dual-screen path would have to register `UISceneAccessory.externalNonInteractive`.
enum PlatformCapabilities {

    // MARK: - What the OS under us actually is (runtime, SDK-independent)

    enum Running {
        /// The live OS version. Read once; it can't change inside a process.
        static let version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion

        static func atLeast(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) -> Bool {
            ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch))
        }

        static var isIOS16OrLater: Bool { atLeast(16) }
        static var isIOS26OrLater: Bool { atLeast(26) }
        static var isIOS27OrLater: Bool { atLeast(27) }

        /// "27.0.1" - for logs and the device report, not for comparisons.
        static var displayString: String {
            "\(version.majorVersion).\(version.minorVersion)"
                + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
        }
    }

    // MARK: - What the SDK we were compiled against knows about (compile-time)

    enum SDK {
        /// True when built with a toolchain that contains the iOS 27 SDK (Swift 6.4+). Fails
        /// safe: if wrong, it reports "no iOS 27 SDK" and any iOS 27-only code stays compiled out.
        #if compiler(>=6.4)
        static let hasIOS27 = true
        #else
        static let hasIOS27 = false
        #endif
    }

    /// True when the OS will drive live, continuous container resizes on iPad (iOS 27+).
    static var expectsContinuousIPadResize: Bool {
        #if os(iOS)
        return Running.isIOS27OrLater && UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    // MARK: - Reporting

    /// One line for the device report and the launch log: what was detected and what the
    /// binary can act on. An iOS 27 device running a pre-27 SDK build is a normal state.
    static var summary: String {
        var parts = ["iOS \(Running.displayString)"]
        parts.append(Running.isIOS27OrLater ? "27+ detected" : "pre-27")
        parts.append(SDK.hasIOS27 ? "built with 27 SDK" : "built with pre-27 SDK")
        if Running.isIOS27OrLater && !SDK.hasIOS27 {
            parts.append("new APIs unavailable to this build")
        }
        if expectsContinuousIPadResize {
            parts.append("continuous iPad resize")
        }
        return parts.joined(separator: " · ")
    }
}
