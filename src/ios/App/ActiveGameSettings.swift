import Foundation

/// The game that is booting or running, and what its own options say, for the readers that sit outside the
/// launch push in GameManager: the presented Resolution (RenderScale.current) and the Favour performance
/// cap on it, which the display code reads on its own whenever a surface is sized.
///
/// Two options live in global @AppStorage keys that the views read directly (the on-screen layout and
/// "Hide on-screen controls when a controller is connected"). For a game that has its own value, `begin`
/// writes it into the global key and remembers what the key held; `end` puts that back. The remembered
/// values are stored, so a launch that follows a crash puts them back too (GameManager.init calls `end`).
/// A layout change made inside the game doesn't carry over to the next game.
enum ActiveGameSettings {
    private static let lock = NSLock()
    private static var active: GameOverrides = .identity

    /// Where the player's own values wait while a game's value is in the global key. "values" holds the
    /// key's old value; "absent" lists keys that had none.
    private static let swapKey = "muffin.perGame.swappedGlobals"

    /// This game's overrides in the current Settings mode (the Advanced ones are ignored in Basic).
    static var overrides: GameOverrides {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    /// A game is starting, or the Wii U Menu is switching to one. Returns whether its Resolution is
    /// different from what was in effect a moment ago, so a switch knows whether to resize the surfaces.
    @discardableResult
    static func begin(gameID id: String) -> Bool {
        let before = RenderScale.current
        restoreSwappedGlobals()
        let next = PerGameSettingsStore.shared.activeOverrides(for: id)
        lock.lock()
        active = next
        lock.unlock()
        let defaults = UserDefaults.standard
        var values: [String: Any] = [:]
        var absent: [String] = []
        func swap(_ key: String, to value: Any) {
            if let old = defaults.object(forKey: key) { values[key] = old } else { absent.append(key) }
            defaults.set(value, forKey: key)
        }
        if let layout = next.screenLayout, ScreenLayout(rawValue: layout) != nil {
            swap(LocalScreenLayoutSettings.layoutKey, to: layout)
        }
        if let hide = next.autoHideControls {
            swap(ControllerLayoutSettings.autoHideWithControllerKey, to: hide)
        }
        if !values.isEmpty || !absent.isEmpty {
            defaults.set(["values": values, "absent": absent], forKey: swapKey)
        }
        return RenderScale.current != before
    }

    /// The game has stopped (or the app has just started): the player's own values go back.
    static func end() {
        lock.lock()
        active = .identity
        lock.unlock()
        restoreSwappedGlobals()
    }

    private static func restoreSwappedGlobals() {
        let defaults = UserDefaults.standard
        guard let saved = defaults.dictionary(forKey: swapKey) else { return }
        for (key, value) in saved["values"] as? [String: Any] ?? [:] { defaults.set(value, forKey: key) }
        for key in saved["absent"] as? [String] ?? [] { defaults.removeObject(forKey: key) }
        defaults.removeObject(forKey: swapKey)
    }
}
