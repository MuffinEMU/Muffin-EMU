import SwiftUI
import UIKit

/// Which way the app may turn.
///
/// The library and Settings were drawn for landscape and stay there. An iPhone may turn upright
/// only while a game is on screen, where the picture goes along the top and the controls below
/// it (see `EmulatorViewOptimized.screenLayoutComposition`). iPad is landscape throughout.
///
/// Info.plist (project.yml) lists portrait for iPhone; this narrows it. UIKit asks
/// `AppOrientationDelegate` for the mask every time it decides whether to rotate.
enum OrientationPolicy {
    /// Settings > Display > "Allow portrait during games". On by default; iPhone only.
    static let allowPortraitKey = "muffin.display.allowPortraitInGame"
    static let defaultAllowPortrait = true

    /// True while the emulator view is on screen. Main thread only, like everything that reads it.
    private static var inGame = false

    private static var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private static var portraitAllowed: Bool {
        UserDefaults.standard.object(forKey: allowPortraitKey) as? Bool ?? defaultAllowPortrait
    }

    static var mask: UIInterfaceOrientationMask {
        guard isPhone, inGame, portraitAllowed else { return .landscape }
        return [.landscape, .portrait]
    }

    /// Called when the emulator view appears and disappears.
    static func setInGame(_ value: Bool) {
        guard inGame != value else { return }
        inGame = value
        apply()
    }

    /// Re-reads the mask. Also the way a Settings change takes effect without leaving the game.
    static func apply() {
        guard isPhone else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            let upright = scene.interfaceOrientation.isPortrait
            if #available(iOS 16.0, *) {
                scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                // Leaving the game, or turning the setting off, from an upright phone: the screen
                // being shown is landscape-only now, so turn it rather than wait for the player to.
                if upright && !mask.contains(.portrait) {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
                }
            } else if upright && !mask.contains(.portrait) {
                // No requestGeometryUpdate before iOS 16.
                UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            }
        }
        // Entering a game with the phone already upright: the OS only rotates to the device's
        // pose on its own when the device moves, so ask it to look now.
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

final class AppOrientationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationPolicy.mask
    }
}
