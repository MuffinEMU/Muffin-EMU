import Foundation
#if os(iOS)
import UIKit

/// Starting points for titles that cannot be played well with MuffinEMU's defaults.
///
/// Each hint is applied at launch, only when the person has never set that option themselves, and
/// only for as long as that title is the one running. The settings behind it are global (on-screen
/// sticks, screen layout), so a hint writes the value for the session and takes it back again when
/// the title stops, the library comes back, or the next title starts. Without that, playing Splatoon
/// once would turn the sticks and the two-screen layout on for every other game as well, and the
/// person would have no way to tell the app had done it. A value the person changes while the title
/// is running is theirs and is left alone. A title not listed here gets no hints.
enum GameControlHints {
    /// Splatoon: USA, Europe, Japan. Movement and camera are both analog, and the map and super jump
    /// live on the GamePad screen.
    private static let splatoonTitleIds: Set<UInt64> = [
        0x0005000010176900,
        0x0005000010176A00,
        0x0005000010162B00,
    ]

    /// Mario Kart 8: USA, Europe, Japan. The Racing control style is built for it.
    private static let marioKart8TitleIds: Set<UInt64> = [
        0x000500001010ec00,
        0x000500001010ed00,
        0x000500001010eb00,
    ]

    /// What the player's control style was before Racing was picked for Mario Kart 8: the stored
    /// string, or "<unset>" when nothing was stored. Put back when the game ends.
    private static let previousSchemeKey = "muffin.hints.previousControlStyle"
    private static let unset = "<unset>"

    /// What the last launch wrote into the global keys, as key -> the value it wrote, so a later
    /// call (even in a new app session, if the app was closed mid-game) can undo exactly that and
    /// nothing the person has chosen since.
    private static let appliedKey = "muffin.hints.appliedGlobals"
    private static let lock = NSLock()

    static func applyBeforeLaunch(titleId: UInt64?) {
        lock.lock()
        defer { lock.unlock() }
        // Whatever the previous title's hints wrote ends here, whether or not this title has its own.
        undoLocked()
        guard let titleId else { return }
        let defaults = UserDefaults.standard
        var applied: [String: String] = [:]

        // Racing for Mario Kart 8, for a player on MuffinEMU's own pad. Someone who chose a TouchLab
        // style, Melo-Controller or the preview pad has made a choice about controls, so it stays.
        if marioKart8TitleIds.contains(titleId) {
            let current = defaults.string(forKey: TouchLabSettings.schemeKey) ?? ""
            let hasOtherPad = defaults.bool(forKey: MeloControlsSetting.storageKey)
                || defaults.bool(forKey: PreviewPadStore.enabledKey)
            if current.isEmpty, !hasOtherPad {
                defaults.set(defaults.string(forKey: TouchLabSettings.schemeKey) ?? unset, forKey: previousSchemeKey)
                defaults.set(TouchLabSettings.racingStyleID, forKey: TouchLabSettings.schemeKey)
                applied[TouchLabSettings.schemeKey] = described(TouchLabSettings.schemeKey)
                defaults.set(applied, forKey: appliedKey)
            }
            return
        }
        guard splatoonTitleIds.contains(titleId) else { return }

        // Both sticks on screen: without them there is no way to move or turn.
        if defaults.object(forKey: ControllerLayoutSettings.joystickKey) == nil {
            defaults.set(true, forKey: ControllerLayoutSettings.joystickKey)
            applied[ControllerLayoutSettings.joystickKey] = described(ControllerLayoutSettings.joystickKey)
        }

        // Show the GamePad screen as well as the TV, sized to the device: side by side where there is
        // room (iPad), as a small inset on a phone, where half the screen each would be too small to play.
        if defaults.object(forKey: LocalScreenLayoutSettings.layoutKey) == nil {
            let layout: ScreenLayout = UIDevice.current.userInterfaceIdiom == .pad ? .bothScreens : .smallGamePadTopRight
            defaults.set(layout.rawValue, forKey: LocalScreenLayoutSettings.layoutKey)
            applied[LocalScreenLayoutSettings.layoutKey] = described(LocalScreenLayoutSettings.layoutKey)
        }

        if !applied.isEmpty { defaults.set(applied, forKey: appliedKey) }
    }

    /// Takes back what a launch's hints wrote, if the person has not changed it since. Safe to call
    /// at any time with no title running; does nothing when there is nothing to take back.
    static func restoreGlobals() {
        lock.lock()
        defer { lock.unlock() }
        undoLocked()
    }

    private static func undoLocked() {
        let defaults = UserDefaults.standard
        guard let applied = defaults.dictionary(forKey: appliedKey) as? [String: String] else { return }
        defaults.removeObject(forKey: appliedKey)
        let previousScheme = defaults.string(forKey: previousSchemeKey)
        defaults.removeObject(forKey: previousSchemeKey)
        for (key, written) in applied where described(key) == written {
            if key == TouchLabSettings.schemeKey, let previousScheme, previousScheme != unset {
                // Back to exactly what was stored, not just "unset".
                defaults.set(previousScheme, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private static func described(_ key: String) -> String? {
        UserDefaults.standard.object(forKey: key).map { "\($0)" }
    }
}
#endif
