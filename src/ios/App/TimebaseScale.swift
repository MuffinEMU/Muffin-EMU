import Foundation

/// How fast the emulated console believes time is passing. Not an overclock: the emulator
/// runs exactly as fast as it runs; this changes the clock the guest sees.
///
/// Without the recompiler the PPC interpreter is far slower than the real CPU, but the
/// guest's clock still follows the host's wall clock, so its own deadlines (alarms, the AX
/// audio callback, thread quanta) are already overdue when serviced and a game can present
/// one frame and never advance. Slowing the guest clock puts those deadlines back in reach.
/// This is Cemu's Timer Speed setting. It is safe to change while a title is running, and
/// guest time still only moves forward.
enum TimebaseScale: Int, CaseIterable, Identifiable {
    /// Values are the right-shift factor Cemu's `ActiveSettings::SetTimerShiftFactor()`
    /// takes: the accumulated tick delta is shifted left 3 and then right by this, so 3
    /// is 1x and each step up halves the rate.
    case realTime = 3
    case half = 4
    case quarter = 5
    case eighth = 6
    case sixteenth = 7
    case thirtySecond = 8
    case sixtyFourth = 9

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .realTime:     return "Real time"
        case .half:         return "1/2 speed"
        case .quarter:      return "1/4 speed"
        case .eighth:       return "1/8 speed"
        case .sixteenth:    return "1/16 speed"
        case .thirtySecond: return "1/32 speed"
        case .sixtyFourth:  return "1/64 speed"
        }
    }

    /// One line saying what picking this does.
    var summary: String {
        switch self {
        case .realTime:
            return "Normal game speed. Right when the recompiler is running."
        case .half, .quarter:
            return "Slows the game a little. Try this first if a game runs but stutters."
        case .eighth:
            return "Slows the game a lot. Helps most games under the interpreter."
        case .sixteenth, .thirtySecond:
            return "For games that still won't advance at 1/8. Gameplay runs in slow motion."
        case .sixtyFourth:
            return "The slowest setting. If a game still won't move, the clock isn't the problem."
        }
    }

    static let storageKey = "timebaseShift"

    /// Whether the user has ever chosen a value. When they haven't, the engine's own default
    /// stands (picked in `cemu_bridge_initialize()` from the CPU mode that launch got).
    static var hasExplicitChoice: Bool {
        UserDefaults.standard.object(forKey: storageKey) != nil
    }

    /// The user's choice, or the engine's current setting when they have not made one.
    static var current: TimebaseScale {
        if hasExplicitChoice,
           let value = TimebaseScale(rawValue: UserDefaults.standard.integer(forKey: storageKey)) {
            return value
        }
        return TimebaseScale(rawValue: Int(cemu_bridge_get_timebase_shift())) ?? .realTime
    }

    /// Pushes a chosen value to the engine and remembers it. Safe mid-title. Choosing a value
    /// turns the automatic ladder off for good, including on later launches.
    static func apply(_ scale: TimebaseScale) {
        UserDefaults.standard.set(scale.rawValue, forKey: storageKey)
        cemu_bridge_set_timebase_auto_enabled(false)
        cemu_bridge_set_timebase_shift(Int32(scale.rawValue))
    }

    /// Forgets the stored choice and hands the decision back to the engine's automatic ladder.
    static func clearChoice() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        cemu_bridge_set_timebase_shift(Int32(TimebaseScale.realTime.rawValue))
        cemu_bridge_set_timebase_auto_enabled(true)
    }

    /// One-time repair: an older version wrote the automatic ladder's own stepped value as if
    /// it were a user choice, pinning some installs at a fraction of real speed. Clears a
    /// stored slowed clock once, guarded by its own flag so a later deliberate choice is
    /// never touched. A stored real-time choice is kept.
    private static let repairedKey = "muffin.timebase.clearedAccidentalChoice"

    static func repairAccidentalChoiceOnce() {
        guard !UserDefaults.standard.bool(forKey: repairedKey) else { return }
        UserDefaults.standard.set(true, forKey: repairedKey)
        guard hasExplicitChoice,
              let stored = TimebaseScale(rawValue: UserDefaults.standard.integer(forKey: storageKey)),
              stored != .realTime
        else { return }
        UserDefaults.standard.removeObject(forKey: storageKey)
        cemu_bridge_log_line("timebase: cleared a stored \(stored.title) clock that the app had written to itself; back to automatic")
    }

    /// Re-applies a stored choice after the engine has initialized; otherwise arms the
    /// automatic ladder.
    static func applyStoredChoiceIfAny() {
        // Run the repair before reading the stored value.
        repairAccidentalChoiceOnce()
        guard hasExplicitChoice,
              let value = TimebaseScale(rawValue: UserDefaults.standard.integer(forKey: storageKey))
        else {
            cemu_bridge_set_timebase_auto_enabled(true)
            return
        }
        cemu_bridge_set_timebase_auto_enabled(false)
        cemu_bridge_set_timebase_shift(Int32(value.rawValue))
    }
}
