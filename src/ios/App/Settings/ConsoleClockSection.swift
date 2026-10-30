// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// Settings > Date & Time: the console clock games read (ConsoleClock). The Wii U's own System
/// Settings had the same choice, so it is a Basic setting, not an Advanced one.
struct ConsoleClockSection: View {
    /// Seeded when the screen opens. The toggle and picker write through ConsoleClock; they never
    /// read back mid-edit, so the picker doesn't jump while someone is turning its wheels.
    @State private var followsRealTime = ConsoleClock.followsRealTime
    @State private var chosen = ConsoleClock.now

    private var followBinding: Binding<Bool> {
        Binding(
            get: { followsRealTime },
            set: { follow in
                followsRealTime = follow
                if follow {
                    ConsoleClock.useRealTime()
                } else {
                    chosen = ConsoleClock.now
                }
            })
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { chosen },
            set: { date in
                chosen = date
                ConsoleClock.set(date)
            })
    }

    var body: some View {
        Section {
            Toggle(isOn: followBinding) {
                Text("Use this device's date and time")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.accentText)

            if !followsRealTime {
                DatePicker("Date", selection: dateBinding, in: ConsoleClock.range, displayedComponents: .date)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .tint(MuffinTheme.accentText)
                DatePicker("Time", selection: dateBinding, in: ConsoleClock.range, displayedComponents: .hourAndMinute)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .tint(MuffinTheme.accentText)
            }

            // Updates on its own, so the line is right after a game moved the clock from HOME.
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                HStack {
                    Text("Console clock now")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(ConsoleClockFormat.string(ConsoleClock.now))
                        .font(.system(size: 15))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            SettingsSectionHeader("Date & Time".localized, icon: "calendar.badge.clock", accent: .core)
        } footer: {
            InfoButton.footer(
                "The date and time games see. A change shows in the next game you start; to move a game's clock while it runs, use HOME > Console clock.".localized,
                title: "Date & Time".localized,
                text: "Games read the console's clock for daily events, timed unlocks and seasons. Turn off \"Use this device's date and time\" to pick another date; the clock keeps running from it, between launches too, as a Wii U's clock did.\n\nWhile a game runs, HOME > Console clock moves its clock forward by an hour up to a year, or by an amount you choose. That change is kept here. Some games only check the date when they start, so quit and start them again to see it.\n\nThis isn't Emulated Clock, which changes how fast time passes inside a game.".localized)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        // Only ever turns the toggle off (a game moved the clock from HOME). Turning it back on here
        // would hide the pickers under someone who scrolled to within a minute of now.
        .onReceive(NotificationCenter.default.publisher(for: .muffinConsoleClockChanged)) { _ in
            if !ConsoleClock.followsRealTime {
                followsRealTime = false
                chosen = ConsoleClock.now
            }
        }
        // Reset settings clears the stored offset from outside this view.
        .onReceive(NotificationCenter.default.publisher(for: .muffinSettingsWereReset)) { _ in
            followsRealTime = ConsoleClock.followsRealTime
            chosen = ConsoleClock.now
            ConsoleClock.applyForLaunch()
        }
    }
}
