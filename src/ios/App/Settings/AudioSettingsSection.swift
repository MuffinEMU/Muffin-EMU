import SwiftUI
import UIKit

/// The channel layouts from CemuConfig.h's `enum AudioChannels` (kMono = 0, kStereo = 1,
/// kSurround = 2).
enum AudioChannelSetting: Int, CaseIterable, Identifiable {
    case mono = 0
    case stereo = 1
    case surround = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .mono:     return "Mono"
        case .stereo:   return "Stereo"
        case .surround: return "Surround"
        }
    }
}

/// Storage keys and defaults for the audio settings. Defaults mirror CemuConfig.h's field
/// initializers; GameManager pushes every key into the engine before each boot.
enum AudioSettings {
    static let tvEnabledKey = "muffin.audio.tvEnabled"
    static let defaultTvEnabled = true

    static let tvVolumeKey = "muffin.audio.tvVolume"
    static let defaultTvVolume = 50

    static let tvChannelsKey = "muffin.audio.tvChannels"
    static let defaultTvChannels = AudioChannelSetting.stereo.rawValue

    static let padEnabledKey = "muffin.audio.padEnabled"
    static let defaultPadEnabled = false

    static let padVolumeKey = "muffin.audio.padVolume"
    static let defaultPadVolume = 50

    static let padChannelsKey = "muffin.audio.padChannels"
    static let defaultPadChannels = AudioChannelSetting.stereo.rawValue

    static let microphoneEnabledKey = "muffin.audio.microphoneEnabled"
    static let defaultMicrophoneEnabled = false

    static let inputVolumeKey = "muffin.audio.inputVolume"
    static let defaultInputVolume = 50
}

/// TV and GamePad output audio (on/off, volume, channel layout for each) and the GamePad
/// microphone input. Audio delay, input channels and device selection are left out: there
/// is a single audio route on iOS.
struct AudioSettingsSection: View {
    @AppStorage(AudioSettings.tvEnabledKey) private var tvEnabled = AudioSettings.defaultTvEnabled
    @AppStorage(AudioSettings.tvVolumeKey) private var tvVolume = AudioSettings.defaultTvVolume
    @AppStorage(AudioSettings.tvChannelsKey) private var tvChannelsRaw = AudioSettings.defaultTvChannels

    @AppStorage(AudioSettings.padEnabledKey) private var padEnabled = AudioSettings.defaultPadEnabled
    @AppStorage(AudioSettings.padVolumeKey) private var padVolume = AudioSettings.defaultPadVolume
    @AppStorage(AudioSettings.padChannelsKey) private var padChannelsRaw = AudioSettings.defaultPadChannels

    @AppStorage(AudioSettings.microphoneEnabledKey) private var microphoneEnabled = AudioSettings.defaultMicrophoneEnabled
    @AppStorage(AudioSettings.inputVolumeKey) private var inputVolume = AudioSettings.defaultInputVolume
    @State private var showMicDenied = false
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue
    @AppStorage(AudioRecorder.autoRecordKey) private var autoRecord = false

    private var advanced: Bool { SettingsMode.isAdvanced(raw: settingsModeRaw) }

    private var deviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    var body: some View {
        Section {
            Toggle(isOn: $autoRecord) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save all audio automatically")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Records every game's music and sound to an M4A in Files > MuffinEMU > Recordings, from start to quit.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(MuffinTheme.accentText)
            MenuMusicSettingsGroup()
            tvGroup
            padGroup
            microphoneGroup
        } header: {
            SettingsSectionHeader("Audio", icon: "speaker.wave.2", accent: .io)
        } footer: {
            InfoButton.footer(
                "TV and GamePad audio have their own volume and channel layout. GamePad audio plays through this device's speaker or headphones. Use the microphone to give games your real voice and sounds through the GamePad mic; otherwise the in-game Blow button covers games that ask you to blow.",
                title: "Audio",
                text: fullText)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    @ViewBuilder private var tvGroup: some View {
        Toggle(isOn: $tvEnabled) {
            Text("TV audio")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.accentText)
        .onChange(of: tvEnabled) { newValue in
            cemu_bridge_set_tv_audio_enabled(newValue)
        }

        if tvEnabled {
            volumeRow(label: "TV volume", volume: $tvVolume) { newValue in
                cemu_bridge_set_tv_volume(Int32(newValue))
            }
            // Channel layout is Advanced mode only (see AdvancedSettings).
            if advanced {
                Picker("TV channels", selection: $tvChannelsRaw) {
                    ForEach(AudioChannelSetting.allCases) { channels in
                        Text(channels.title).tag(channels.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(MuffinTheme.accentText)
                .foregroundColor(MuffinTheme.brownDarkest)
                .onChange(of: tvChannelsRaw) { newValue in
                    cemu_bridge_set_tv_channels(Int32(newValue))
                }
            }
        }
    }

    @ViewBuilder private var padGroup: some View {
        Toggle(isOn: $padEnabled) {
            Text("GamePad audio")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.accentText)
        .onChange(of: padEnabled) { newValue in
            cemu_bridge_set_pad_audio_enabled(newValue)
        }

        if padEnabled {
            volumeRow(label: "GamePad volume", volume: $padVolume) { newValue in
                cemu_bridge_set_pad_volume(Int32(newValue))
            }
            // Channel layout is Advanced mode only (see AdvancedSettings).
            if advanced {
                Picker("GamePad channels", selection: $padChannelsRaw) {
                    ForEach(AudioChannelSetting.allCases) { channels in
                        Text(channels.title).tag(channels.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(MuffinTheme.accentText)
                .foregroundColor(MuffinTheme.brownDarkest)
                .onChange(of: padChannelsRaw) { newValue in
                    cemu_bridge_set_pad_channels(Int32(newValue))
                }
            }
        }
    }

    // No channel picker for input: input_channels has no effect even in desktop Cemu.
    //
    // Off (default): games still see a GamePad mic, but it only carries what the in-game Blow
    // button generates, so iOS never asks for permission. On: the real microphone is captured
    // while a game has the mic open, and the Blow button is hidden.
    @ViewBuilder private var microphoneGroup: some View {
        Toggle(isOn: $microphoneEnabled) {
            Text("Use \(deviceName) microphone")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .tint(MuffinTheme.accentText)
        .onChange(of: microphoneEnabled) { newValue in
            guard newValue else {
                cemu_bridge_set_microphone_enabled(false)
                return
            }
            // Asks the first time; a stored denial comes back as false without a prompt.
            MicrophoneAccess.request { granted in
                if granted {
                    cemu_bridge_set_microphone_enabled(true)
                } else {
                    microphoneEnabled = false
                    cemu_bridge_set_microphone_enabled(false)
                    showMicDenied = true
                }
            }
        }
        .onAppear {
            // Permission can be revoked in iOS Settings while this switch stays on.
            if microphoneEnabled && MicrophoneAccess.status == .denied {
                microphoneEnabled = false
                cemu_bridge_set_microphone_enabled(false)
            }
        }
        .alert("Microphone access is off", isPresented: $showMicDenied) {
            Button("Open Settings") { MicrophoneAccess.openSystemSettings() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("MuffinEMU can't use your \(deviceName)'s microphone until you allow it in iOS Settings. Until then, games use the Blow button in the top bar instead.")
        }

        if microphoneEnabled {
            volumeRow(label: "Microphone volume", volume: $inputVolume) { newValue in
                cemu_bridge_set_input_volume(Int32(newValue))
            }
        }
    }

    // Shared row for all three volumes: Int storage (the bridge wants 0-100) wrapped in a
    // Double Binding for the Slider.
    private func volumeRow(label: String, volume: Binding<Int>, onChange: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(volume.wrappedValue)%")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
            Slider(
                value: Binding<Double>(
                    get: { Double(volume.wrappedValue) },
                    set: { newValue in
                        let rounded = Int(newValue.rounded())
                        volume.wrappedValue = rounded
                        onChange(rounded)
                    }),
                in: 0...100,
                step: 1)
                .accessibilityLabel(label)
        }
    }

    private var fullText: String {
        "TV and GamePad audio are separate tracks with their own on/off, volume and channel layout.\n\nChannels: Mono mixes everything to one channel, Stereo splits left and right (default), Surround asks the game for more channels; most games only use stereo. Turning TV or GamePad audio on or off, and changing channels, applies the next time you start a game.\n\nGamePad audio plays whatever the game sends to the GamePad speaker. Many games send nothing different from the TV mix.\n\nUse microphone feeds your device's real microphone to games that ask for the GamePad mic, while the game has the mic open. iOS asks for permission the first time you turn it on; if you say no, it switches back off. While it's on, the in-game Blow button is hidden. When it's off, games still see a GamePad mic, but it only hears the Blow button (a simulated puff of air) and iOS never asks for permission. Microphone volume (50 is normal, 100 is twice as loud) applies the next time a game opens the mic."
    }
}
