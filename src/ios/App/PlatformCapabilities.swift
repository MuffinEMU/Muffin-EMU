import Foundation
#if os(iOS)
import UIKit
#endif

/// One place that answers "what can the OS under us actually do", so the rest of the app
/// asks for a capability by name instead of scattering raw version numbers across call
/// sites.
///
/// MuffinEMU deploys back to iOS 15 (`src/ios/project.yml`) and iOS 27 shipped on
/// 2026-09-14, so this app spans thirteen major releases. Before this file the Swift side
/// had exactly four loose `#available(iOS 16.0, *)` checks and nothing that knew iOS 27
/// existed at all - while the ObjC bridge already branched on it correctly for TXM/JIT
/// (`ios_has_txm()` in CemuBridge.mm). This closes that gap on the Swift side.
///
/// # The two halves of "support a new iOS", and why they are not the same thing
///
/// **Detection is a runtime question.** `ProcessInfo.operatingSystemVersion` reports
/// whatever the device is actually running, regardless of which SDK the binary was built
/// against. Everything in `Running` below works today, on the current toolchain, with no
/// build change at all.
///
/// **Adoption is a compile-time question.** You cannot *call* an iOS 27 API unless the
/// SDK you compile against declares it. `.github/workflows/build-ios-app.yml` currently
/// pins `runs-on: macos-15` and `xcode-select -s /Applications/Xcode_26.3.app`, which is
/// an iOS 26 SDK. Against that SDK, `if #available(iOS 27.0, *)` compiles fine - it is
/// only a version comparison - but any iOS 27-only symbol inside it does not exist and
/// the build fails. So this file deliberately does NOT contain invented calls to
/// unavailable frameworks. `SDK.hasIOS27` below is the switch that lights those up, and
/// it flips on its own the moment CI moves to an Xcode 27 image (GitHub publishes one
/// under the `xcode-27` runner label; note it is arm64-only, which is a real change for a
/// pipeline that currently builds Cemu.framework on x86_64 macos-15, and so is a
/// deliberate decision rather than something to slip in).
///
/// # Automatic vs. opt-in, which is a taste decision and not a technical one
///
/// Capabilities are split into `Running` (what the OS is) and two adoption groups:
///
/// - `Adopt.automatic...` - correctness, compatibility and performance. These change what
///   works or how fast it is, never how it looks, so a newer OS should get them silently.
/// - `Adopt.visualOptIn...` - anything that changes appearance. These default to OFF.
///   Void's verdict on the iOS 26 Liquid Glass adoption was "it just makes the ui feel
///   clunky and weird, it doesn't feel nice anymore", and it was reverted the same day.
///   iOS 27's SwiftUI changes are largely descendants of that same design language, so
///   adopting them automatically would repeat a mistake we have already paid for once.
///   The mechanism is here; turning any of it on is a choice someone makes on purpose.
enum PlatformCapabilities {

    // MARK: - What the OS under us actually is (runtime, SDK-independent)

    enum Running {
        /// The live OS version. Read once - it cannot change inside a process.
        static let version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion

        /// `ProcessInfo`'s own comparison rather than hand-rolled `>=` on the components,
        /// which is the classic place a patch-release check gets written backwards.
        static func atLeast(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) -> Bool {
            ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch))
        }

        static var isIOS16OrLater: Bool { atLeast(16) }
        static var isIOS26OrLater: Bool { atLeast(26) }
        /// Released 2026-09-14.
        static var isIOS27OrLater: Bool { atLeast(27) }

        /// "27.0.1" - for logs and the device report, not for comparisons.
        static var displayString: String {
            "\(version.majorVersion).\(version.minorVersion)"
                + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
        }
    }

    // MARK: - What the SDK we were compiled against knows about (compile-time)

    enum SDK {
        /// True when this binary was built with a toolchain new enough to contain the
        /// iOS 27 SDK, which is what makes iOS 27-only symbols exist at all.
        ///
        /// Keyed off the Swift compiler version rather than a framework name on purpose.
        /// `#if canImport(SomeFramework)` is the usual idiom, but it requires naming a
        /// framework that is genuinely new in 27 and not merely new-ish - get that wrong
        /// and this silently reports the opposite of the truth, which is worse than not
        /// having it. The toolchain version is a fact about the build, not a guess about
        /// Apple's framework history: Swift 6.4 ships with the Xcode that carries the
        /// iOS 27 SDK.
        ///
        /// If this is ever wrong it fails SAFE - it reports "no iOS 27 SDK", every
        /// adoption block below stays compiled out, and the app behaves exactly as it
        /// does today.
        #if compiler(>=6.4)
        static let hasIOS27 = true
        #else
        static let hasIOS27 = false
        #endif
    }

    // MARK: - What iOS 27 actually changes for THIS app
    //
    // Taken from Apple's iOS & iPadOS 27 release notes, not from guesswork. Radar
    // numbers are quoted so every claim below can be checked against the source:
    // https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes
    //
    // Audited 2026-09-15 against this tree. Four of the six are already satisfied; the
    // other two are recorded because they are real and will matter.
    //
    // 1. LAUNCH SCREEN - SATISFIED, and it is a hard requirement, not advice. Apps built
    //    with the 27.0 SDK must have one of UILaunchStoryboardName / UILaunchStoryboards
    //    / UILaunchScreen / UILaunchScreens in Info.plist, and are REJECTED by the App
    //    Store without one (168247372). project.yml sets
    //    INFOPLIST_KEY_UILaunchScreen_Generation: 'YES', which emits UILaunchScreen. Do
    //    not remove that key thinking it is cosmetic.
    //
    // 2. DEPRECATED STATUS BAR ACCESSORS - SATISFIED. Built with the 27.0 SDK,
    //    UIApplication.statusBarFrame / statusBarOrientation / statusBarStyle /
    //    isStatusBarHidden may return NaN or null (162044221). This app touches none of
    //    them; it hides the status bar declaratively via INFOPLIST_KEY_UIStatusBarHidden.
    //
    // 3. UIRequiresFullScreen - SATISFIED by not setting it. On the 27.0 SDK an iPad app
    //    that sets it gets a UIScreen.main whose bounds change on resize, and continuous
    //    resize updates where it should get discrete new-UIScreen changes
    //    (both listed as resolved issues). We have never set it.
    //
    // 4. @State BECOMES A MACRO in Xcode 27 (105893279) - SATISFIED, but this is the one
    //    to watch when CI moves toolchains. It breaks two patterns: an initial value at
    //    the declaration that is then reassigned in init, and the compiler-synthesized
    //    private init. CreateAccountView is the only view here with a custom init, and it
    //    already uses the correct form - a bare `@State private var x: T` declaration
    //    plus `_x = State(initialValue:)` in init - so it is safe as written.
    //
    // 5. iPad CONTINUOUS RESIZABILITY - A REAL BEHAVIOUR CHANGE FOR US. Apple fixed
    //    UISupportedInterfaceOrientations being a condition for continuous resizability
    //    (the "Fixed:" framing matters - the OLD behaviour was the bug). project.yml
    //    lists only UIInterfaceOrientationLandscapeLeft/Right, so under the old rule this
    //    app was NOT continuously resizable; from iOS 27 it is, regardless of that list.
    //    Consequence: `DisplayRouter.deviceContainerDidLayout(_:)` will fire far more
    //    often, continuously, while a user drags an iPad Split View divider - a path that
    //    previously saw a handful of discrete sizes. That function's size-equality
    //    early-return is what keeps this cheap, and `resizeTVSurfaceIfRegistered()` does
    //    real work (a frame assignment plus a bridge call into
    //    CemuUIKit_UpdateMainWindowSize) on every genuine change. It is correct under
    //    continuous resize, but it is now on a hot path it was not written for.
    //    See `expectsContinuousIPadResize` below.
    //
    // 6. EXTERNAL DISPLAY SCENES - a real, documented reason the dual-screen path will
    //    not start working on iOS 27. Built with the 27.0 SDK,
    //    `windowExternalDisplayNonInteractive` scenes are NO LONGER OFFERED AUTOMATICALLY
    //    by the system; an app must call `UIViewController.registerSceneAccessory(_:)`
    //    with a `UISceneAccessory.externalNonInteractive` instance (177015874).
    //    DisplayRouter's `.dualScreen` placement is already documented as never having
    //    been exercised - `externalWindowScene(for:)` is expected to return nil today
    //    because the app ships no external-display scene configuration. This is now the
    //    named API that path would have to adopt, rather than an open question.
    //    Not implemented here: it needs the 27.0 SDK to compile, and it should be written
    //    against real hardware rather than blind.
    //
    // Also true but requiring nothing of us: the PlayStation Access controller is now
    // supported on iOS/iPadOS (168071382) - that reaches the app through the core's own
    // GCControllerProvider, since the Swift-side physical-controller manager was reverted
    // on 2026-09-15 along with the rest of the day's controller changes; and two Metal
    // sampler clamp-to-edge fixes landed (172520325, 177318505), the second of which is
    // specific to the Apple 10 GPU family and so does not describe the A12Z this port
    // targets.

    /// True when the OS will drive live, continuous container resizes on iPad - see
    /// note 5 above. Exposed as a named capability so the render-sizing path can be
    /// reasoned about and, if it ever needs coalescing, has one flag to key off rather
    /// than a version number buried in DisplayRouter.
    static var expectsContinuousIPadResize: Bool {
        #if os(iOS)
        return Running.isIOS27OrLater && UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    // MARK: - Adoption

    enum Adopt {
        /// Correctness and performance only - safe to take silently on a newer OS.
        ///
        /// Note what is already handled elsewhere and deliberately NOT duplicated here:
        /// the JIT/TXM path in `CemuBridge.mm` (`ios_has_txm()`, `ios_configure_jit_
        /// environment()`) already branches on `ios_os_at_least(27, 0)` and knows that
        /// A12 is the last A-series chip without TXM. That is the single most
        /// consequential iOS 27 behaviour difference for this app, it is already correct,
        /// and re-deriving it in Swift would create a second source of truth for
        /// something that decides whether the recompiler can run at all.
        static var automaticModernOSBehaviour: Bool { Running.isIOS27OrLater }

        /// Appearance changes. OFF by default - see this type's doc comment.
        ///
        /// Gated on BOTH the running OS and a stored preference, so that turning the
        /// preference on cannot affect anyone on an older OS, and running iOS 27 cannot
        /// change the look without someone asking for it.
        static let visualOptInKey = "muffin.platform.adoptNewSystemAppearance"
        static var visualOptInDefault: Bool { false }
        static var visualOptInEnabled: Bool {
            UserDefaults.standard.object(forKey: visualOptInKey) as? Bool ?? visualOptInDefault
        }
        static var usesNewSystemAppearance: Bool {
            Running.isIOS27OrLater && visualOptInEnabled
        }
    }

    // MARK: - Reporting

    /// One line for the device report and the launch log. Says what was detected AND what
    /// the binary can act on, because those are different and the difference is exactly
    /// what someone debugging "why didn't it use the new thing" needs to see: an iOS 27
    /// device running a binary built on the iOS 26 SDK is a completely normal state here,
    /// not a fault.
    static var summary: String {
        var parts = ["iOS \(Running.displayString)"]
        parts.append(Running.isIOS27OrLater ? "27+ detected" : "pre-27")
        parts.append(SDK.hasIOS27 ? "built with 27 SDK" : "built with pre-27 SDK")
        if Running.isIOS27OrLater && !SDK.hasIOS27 {
            parts.append("new APIs unavailable to this build")
        }
        parts.append("new appearance " + (Adopt.usesNewSystemAppearance ? "on" : "off"))
        if expectsContinuousIPadResize {
            parts.append("continuous iPad resize")
        }
        return parts.joined(separator: " · ")
    }
}
