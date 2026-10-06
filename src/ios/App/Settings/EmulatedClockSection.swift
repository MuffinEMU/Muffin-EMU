import SwiftUI

/// Its own section because it isn't a performance setting: it doesn't make anything faster,
/// it decides whether a slow-running game can advance at all.
struct EmulatedClockSection: View {
    /// @State, seeded once, not @AppStorage defaulted from the engine's live value: otherwise
    /// the automatic ladder's own steps would change the picker, fire `.onChange` and get
    /// saved as a user choice. The picker shows what was in effect when the screen opened,
    /// and only a tap writes anything.
    @State private var timebaseRaw = TimebaseScale.current.rawValue
    /// Bumped when the stored choice is cleared, so the row below re-checks it.
    @State private var resetCount = 0

    private var timebase: TimebaseScale {
        TimebaseScale(rawValue: timebaseRaw) ?? .realTime
    }

    /// Applied from the setter, not an onChange: "Let MuffinEMU choose again" and a settings
    /// reset assign `timebaseRaw` too, and those must not be saved as a person's choice. The
    /// shift is read per call inside PPCTimer, so applying it mid-title is safe.
    private var speedChoice: Binding<Int> {
        Binding(
            get: { timebaseRaw },
            set: { raw in
                timebaseRaw = raw
                guard let scale = TimebaseScale(rawValue: raw) else { return }
                TimebaseScale.apply(scale)
            })
    }

    var body: some View {
        Section {
            Picker("Speed", selection: speedChoice) {
                ForEach(TimebaseScale.allCases) { scale in
                    Text(scale.title).tag(scale.rawValue)
                }
            }
            .pickerStyle(.menu)
            .tint(MuffinTheme.accentText)
            .foregroundColor(MuffinTheme.brownDarkest)

            // A way back to automatic; any stored value otherwise disables the ladder for good.
            if TimebaseScale.hasExplicitChoice {
                Button("Let MuffinEMU choose again") {
                    TimebaseScale.clearChoice()
                    timebaseRaw = TimebaseScale.realTime.rawValue
                    resetCount += 1
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            } else {
                Text("Automatic: MuffinEMU slows the clock itself if a game doesn't start drawing.")
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
        } header: {
            SettingsSectionHeader("Emulated Clock", icon: "clock", accent: .core)
        } footer: {
            InfoButton.footer(
                "\(timebase.summary) Changes how fast the game thinks time passes; it doesn't change how fast MuffinEMU runs.",
                title: "Emulated Clock",
                text: "Until you choose a value, MuffinEMU picks one itself: if a game hasn't started drawing after 12 seconds, it slows its clock a step (down to 1/64). Choosing a value here turns that off.\n\nWithout the recompiler the emulated CPU is much slower than the console's, so games can fall behind their own timers and never draw a frame. Slowing the game's clock gives them room. Emulation accuracy isn't affected.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        // Reset settings clears the stored choice from outside this view.
        .onReceive(NotificationCenter.default.publisher(for: .muffinSettingsWereReset)) { _ in
            timebaseRaw = TimebaseScale.current.rawValue
            resetCount += 1
        }
    }
}
