import SwiftUI

/// Its own section because it isn't a performance setting: it doesn't make anything faster,
/// it decides whether a slow-running game can advance at all.
struct EmulatedClockSection: View {
    /// @State, seeded once, not @AppStorage defaulted from the engine's live value: otherwise
    /// the automatic ladder's own steps would change the picker, fire `.onChange` and get
    /// saved as a user choice. The picker shows what was in effect when the screen opened,
    /// and only a tap writes anything.
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
            .tint(MuffinTheme.accentText)
            .foregroundColor(MuffinTheme.brownDarkest)
            // Applied immediately: the shift is read per call inside PPCTimer, so changing it
            // mid-title is safe.
            .onChange(of: timebaseRaw) { raw in
                guard let scale = TimebaseScale(rawValue: raw) else { return }
                TimebaseScale.apply(scale)
            }

            // A way back to automatic; any stored value otherwise disables the ladder for good.
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
                "\(timebase.summary) Changes how fast the game thinks time passes; it doesn't change how fast MuffinEMU runs.",
                title: "Emulated Clock",
                text: "Until you choose a value, MuffinEMU picks one itself: if a game hasn't started drawing after 12 seconds, it slows its clock a step (down to 1/64). Choosing a value here turns that off.\n\nWithout the recompiler the emulated CPU is much slower than the console's, so games can fall behind their own timers and never draw a frame. Slowing the game's clock gives them room. Emulation accuracy isn't affected.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
