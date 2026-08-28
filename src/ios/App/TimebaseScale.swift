import Foundation

/// How fast the emulated console believes time is passing.
///
/// Not a speed control in the sense a game menu means it, and not an overclock. The
/// emulator runs exactly as fast as it runs; this changes what the *guest* thinks the
/// clock is doing while it does.
///
/// It exists because of a mismatch this port cannot avoid while the recompiler is off.
/// The PPC interpreter retires instructions on the order of a hundred times slower than
/// the Espresso it stands in for, but `PPCTimer_getFromRDTSC()` still derives the guest's
/// clock from the host's wall clock. So the emulated console sees a CPU that has, from
/// its point of view, very nearly stopped: every deadline it sets for itself - coreinit
/// alarms, the AX audio callback every few milliseconds, thread quanta - is already long
/// expired by the time it is serviced. coreinit can then spend entire timeslices on
/// overdue timer work and hand the title's own thread nothing at all. What that looks
/// like from the outside is a game that presents one frame and then never advances,
/// which is not a hang and will not be fixed by waiting.
///
/// Slowing the guest's clock puts its deadlines back within reach, so it runs in honest
/// slow motion rather than drowning. Cemu has shipped this knob for years - desktop
/// exposes it as the Timer Speed menu - and iOS simply never set it, so every launch to
/// date ran at real time no matter which CPU it was using.
///
/// No emulated result changes with this. The shift is applied per call to the rate a
/// monotonic tick counter accumulates, so time still only ever moves forward, and it is
/// safe to change while a title is running.
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

    /// One line saying what picking this actually does, in terms of the symptom.
    var summary: String {
        switch self {
        case .realTime:
            return "What every build before this one used. Correct with the recompiler; under the interpreter it is what makes a running game look frozen."
        case .half, .quarter:
            return "A mild correction. Worth trying first if a game advances but stutters badly."
        case .eighth:
            return "The starting point under the interpreter. Enough slack for most titles' own deadlines to stay reachable."
        case .sixteenth, .thirtySecond:
            return "For a title that still will not advance at 1/8. The game plays in slow motion; it does not run slower than it already was."
        case .sixtyFourth:
            return "As slow as this goes. If a game will not move here, the problem is not the clock."
        }
    }

    static let storageKey = "timebaseShift"

    /// Whether the user has ever chosen a value. When they have not, the engine's own
    /// default stands - it is picked in `cemu_bridge_initialize()` from the CPU mode that
    /// launch actually got, which Swift does not know yet at that point. Overriding it
    /// here with a Swift-side guess would throw away the one piece of information that
    /// makes the default correct.
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

    /// Pushes a chosen value to the engine and remembers it. Safe mid-title.
    static func apply(_ scale: TimebaseScale) {
        UserDefaults.standard.set(scale.rawValue, forKey: storageKey)
        cemu_bridge_set_timebase_shift(Int32(scale.rawValue))
    }

    /// Re-applies a stored choice after the engine has initialized, and otherwise leaves
    /// the engine's own default alone. Call once, immediately after
    /// `cemu_bridge_initialize()`.
    static func applyStoredChoiceIfAny() {
        guard hasExplicitChoice,
              let value = TimebaseScale(rawValue: UserDefaults.standard.integer(forKey: storageKey))
        else { return }
        cemu_bridge_set_timebase_shift(Int32(value.rawValue))
    }
}
