import Foundation
#if os(iOS)
import UIKit

/// Starting points for titles that cannot be played well with MuffinEMU's defaults.
///
/// Each hint is applied at launch, only when the person has never set that option themselves, and
/// only writes the same setting they could have chosen in Settings, so changing it afterwards sticks.
/// A title not listed here gets no hints.
enum GameControlHints {
    /// Splatoon: USA, Europe, Japan. Movement and camera are both analog, and the map and super jump
    /// live on the GamePad screen.
    private static let splatoonTitleIds: Set<UInt64> = [
        0x0005000010176900,
        0x0005000010176A00,
        0x0005000010162B00,
    ]

    static func applyBeforeLaunch(titleId: UInt64?) {
        guard let titleId, splatoonTitleIds.contains(titleId) else { return }
        let defaults = UserDefaults.standard

        // Both sticks on screen: without them there is no way to move or turn.
        if defaults.object(forKey: ControllerLayoutSettings.joystickKey) == nil {
            defaults.set(true, forKey: ControllerLayoutSettings.joystickKey)
        }

        // Show the GamePad screen as well as the TV, sized to the device: side by side where there is
        // room (iPad), as a small inset on a phone, where half the screen each would be too small to play.
        if defaults.object(forKey: LocalScreenLayoutSettings.layoutKey) == nil {
            let layout: ScreenLayout = UIDevice.current.userInterfaceIdiom == .pad ? .bothScreens : .smallGamePadTopRight
            defaults.set(layout.rawValue, forKey: LocalScreenLayoutSettings.layoutKey)
        }
    }
}
#endif
