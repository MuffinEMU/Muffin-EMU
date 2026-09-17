import SwiftUI

/// Its own section rather than a row under Graphics or CPU, because it is not a
/// performance setting and calling it one would be the wrong idea to give: it makes
/// nothing faster. It is the setting that decides whether a game that is already
/// running slowly can advance at all, which is a different question and the one
/// that has actually been blocking this port.
struct EmulatedClockSection: View {
    /// @State, seeded once - NOT @AppStorage defaulted from the engine's live value.
    ///
    /// It used to be the latter, and that turned the automatic ladder's searching into a
    /// permanent user choice. @AppStorage returns its default while the key is unset, and
    /// that default was `TimebaseScale.current`, which reads the engine's CURRENT shift.
    /// So when the ladder stepped the clock down, this view's value changed underneath
    /// it, `.onChange` fired, and `apply()` wrote the ladder's guess to disk as though
    /// somebody had picked it - which also switched the ladder off for good. From then on
    /// every launch re-applied it. A device that once booted a title slowly ran every
    /// title at a fraction of speed afterwards, through every update, with nothing saying
    /// why.
    ///
    /// @State is evaluated once for this view's lifetime, so the picker cannot move on
    /// its own any more. It shows what was in effect when the screen opened, and only a
    /// tap writes anything.
    @State private var timebaseRaw = TimebaseScale.current.rawValue

    private var timebase: TimebaseScale {
        TimebaseScale(rawValue: timebaseRaw) ?? .realTime
    }

    var body: some View {
        Section {
            Picker("Speed", selection: $timebaseRaw) {
                ForEach(TimebaseScale.allCases) { scale in
                    Text(scale.title).tag(scale.rawValue)
                }
            }
            .pickerStyle(.menu)
            .tint(MuffinTheme.pixelBlue)
            .foregroundColor(MuffinTheme.brownDarkest)
            // Applied immediately, unlike Resolution: the shift is read per
            // call inside PPCTimer, so changing it mid-title is safe and the
            // guest's clock still only ever moves forward. Someone watching a
            // game sit on one frame can walk down this list and see which
            // value frees it, without relaunching between each try.
            .onChange(of: timebaseRaw) { raw in
                guard let scale = TimebaseScale(rawValue: raw) else { return }
                TimebaseScale.apply(scale)
            }

            // A way back to automatic. Without it, one tap on this picker - or, before
            // the fix above, no tap at all - was a one-way door: any stored value
            // disables the ladder for good, and nothing else in the app could clear it.
            if TimebaseScale.hasExplicitChoice {
                Button("Let MuffinEMU choose again") {
                    TimebaseScale.clearChoice()
                    timebaseRaw = TimebaseScale.realTime.rawValue
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        } header: {
            SettingsSectionHeader("Emulated Clock", icon: "clock", accent: .core)
        } footer: {
            InfoButton.footer(
                "\(timebase.summary) Changes how fast the game believes time passes, not how fast MuffinEMU runs, and takes effect immediately.",
                title: "Emulated Clock",
                text: "\(timebase.summary)\n\nUntil you pick a value here, MuffinEMU finds one itself: if a game has not reached its graphics handover after twelve seconds it steps its own clock down a notch, as far as 1/64, and the log says which value freed it. Choosing anything on this list stops that search for good and keeps your choice.\n\nThis changes how fast the game believes time is passing, not how fast MuffinEMU runs. Without the recompiler the emulated CPU is far slower than the console's, while the game's own clock keeps up with real time - so every deadline it sets itself is already overdue, and it can spend all its time on overdue work and never draw. Slowing its clock puts those deadlines back in reach. Nothing about the emulation is made less accurate by it, and it takes effect straight away.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
