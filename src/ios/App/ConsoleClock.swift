// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import Foundation

/// The date and time the emulated Wii U believes it is. Games read it for daily events, timed
/// unlocks and seasons. A real Wii U kept its own clock, set in System Settings, and it kept
/// running from whatever it was set to; MuffinEMU does the same by storing how far the console
/// clock is from this device's clock, so it keeps running between launches.
///
/// Not the Emulated Clock section (TimebaseScale): that changes how fast time passes, this
/// changes what time it is.
enum ConsoleClock {
    /// Seconds the console clock is ahead of this device; negative is behind. Removed, not set to 0,
    /// when it follows real time, so Settings > Changed from default only lists a clock that was set.
    static let offsetKey = "muffin.consoleClock.offsetSeconds"

    /// The engine counts from 1 January 2000, so nothing earlier can be shown. The end is far
    /// enough for any game and keeps the offset well inside the engine's range.
    static let range: ClosedRange<Date> = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.date(from: DateComponents(year: 2000, month: 1, day: 2))!
        let end = utc.date(from: DateComponents(year: 2099, month: 12, day: 31))!
        return start...end
    }()

    static var offset: TimeInterval {
        UserDefaults.standard.double(forKey: offsetKey)
    }

    static var followsRealTime: Bool { offset == 0 }

    /// What the console clock says now.
    static var now: Date { Date().addingTimeInterval(offset) }

    /// Sets the console clock to `date`. A game that is running keeps its clock until the next
    /// game starts, as on the console; use `advance(by:)` to move a running game's clock.
    static func set(_ date: Date) {
        let clamped = min(max(date, range.lowerBound), range.upperBound)
        store(clamped.timeIntervalSinceNow)
    }

    static func useRealTime() {
        store(0)
    }

    /// Moves the running game's clock forward by `seconds` and keeps the change, as changing a
    /// console's clock would. Returns false, and changes nothing, when no game is running.
    @discardableResult
    static func advance(by seconds: Int) -> Bool {
        guard seconds > 0, now.addingTimeInterval(TimeInterval(seconds)) <= range.upperBound,
              cemu_bridge_advance_console_clock(Int64(seconds)) else { return false }
        store(offset + TimeInterval(seconds))
        return true
    }

    /// The engine reads the clock once while a title starts; GameManager calls this before that.
    static func applyForLaunch() {
        cemu_bridge_set_console_clock_offset(Int64(offset.rounded()))
    }

    private static func store(_ seconds: TimeInterval) {
        let whole = seconds.rounded()
        // Under a minute either way is this device's clock: a date picker can't land closer than that.
        if abs(whole) < 60 {
            UserDefaults.standard.removeObject(forKey: offsetKey)
        } else {
            UserDefaults.standard.set(whole, forKey: offsetKey)
        }
        cemu_bridge_set_console_clock_offset(Int64(offset.rounded()))
        NotificationCenter.default.post(name: .muffinConsoleClockChanged, object: nil)
    }
}

extension Notification.Name {
    static let muffinConsoleClockChanged = Notification.Name("muffin.consoleClock.changed")
}

/// The jumps HOME > Console clock offers. Forward only: a game that sees its clock go backwards
/// can treat the gap as cheating or lose a day's progress, and a jump back is never needed to
/// reach an event.
enum ConsoleClockStep: Int, CaseIterable, Identifiable {
    case oneHour = 3_600
    case sixHours = 21_600
    case oneDay = 86_400
    case oneWeek = 604_800
    case thirtyDays = 2_592_000
    case oneYear = 31_536_000

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneHour: return "Forward 1 hour".localized
        case .sixHours: return "Forward 6 hours".localized
        case .oneDay: return "Forward 1 day".localized
        case .oneWeek: return "Forward 1 week".localized
        case .thirtyDays: return "Forward 30 days".localized
        case .oneYear: return "Forward 1 year".localized
        }
    }
}

/// How a console clock date is written in the HOME menu and Settings: this device's own format.
enum ConsoleClockFormat {
    static func string(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    /// "2 days 3 hours", for the custom jump.
    static func duration(days: Int, hours: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: DateComponents(day: days, hour: hours)) ?? ""
    }
}
