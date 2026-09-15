import SwiftUI

/// Its own section rather than a row under Graphics or CPU, because it is not a
/// performance setting and calling it one would be the wrong idea to give: it makes
/// nothing faster. It is the setting that decides whether a game that is already
/// running slowly can advance at all, which is a different question and the one
/// that has actually been blocking this port.
struct EmulatedClockSection: View {
    /// Defaulted from `TimebaseScale.current` rather than a fixed case, because the
    /// engine picks this one itself at launch from the CPU mode it actually got (real
    /// time under the recompiler, an eighth under the interpreter). A hardcoded default
    /// here would show a value that is not the one in effect, on the single screen whose
    /// job is to say what is in effect.
    @AppStorage(TimebaseScale.storageKey) private var timebaseRaw = TimebaseScale.current.rawValue

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
