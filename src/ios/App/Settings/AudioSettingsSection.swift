import SwiftUI

/// The three channel layouts CemuConfig.h's `enum AudioChannels` defines (kMono = 0,
/// kStereo = 1, kSurround = 2). Declared here rather than shared with a hypothetical
/// desktop-parity enum because nothing else in this port surfaces channel layout yet -
/// see GraphicsSettingsSection.swift's `ScaleFilter` for the same "one small Int enum
/// per picker" shape this follows.
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

/// Storage keys and defaults for the six in-scope audio settings, one enum per screen
/// the way `DisplayLayoutSettings` in DisplayRouter.swift keys the display-routing
/// settings. Defaults mirror CemuConfig.h's own field initializers (tv_audio_enabled =
/// true, pad_audio_enabled = false, both channels = kStereo, both volumes = 50) rather
/// than the different numbers CemuConfig.cpp's XML loader falls back to (20 for TV
/// volume, 0 for GamePad) when a config.xml predates these fields - that fallback never
/// actually surfaces here, because GameManager pushes every one of these keys into the
/// engine before every boot (see the boot-time push block), so the engine's config
/// always ends up matching whatever this file's defaults or the user's own choice say,
/// not whatever a stale XML fallback would have produced.
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
}

/// TV and GamePad output audio - on/off, level, and channel layout for each, backed by
/// CemuConfig.h's tv_audio_enabled/tv_volume/tv_channels and pad_audio_enabled/
/// pad_volume/pad_channels. audio_delay and microphone_enabled are deliberately not
/// here (out of scope for this page - the former is an AV-sync knob, the latter a mic
/// permission concern, not audio output), and neither is device selection
/// (tv_device/pad_device): those name a host audio device, which has no equivalent on
/// iOS, where CoreAudio owns the one active output route for the whole app.
///
/// TV and GamePad audio are two independent output devices in the engine
/// (g_tvAudio/g_padAudio in ax_out.cpp), each enabled, muted and mixed on its own - the
/// GamePad's audio track is not gated on whether a second physical screen is attached.
/// Whether turning it on is actually useful the way DisplayRouter.swift's dual-screen
/// video routing is - i.e., whether most titles route anything distinct to the GamePad
/// speaker versus just duplicating the TV mix - is a question about individual titles'
/// own audio design, not about this engine, and this file does not claim an answer
/// either way; it only exposes the switch honestly; the toggle works identically with
/// or without a second display connected.
struct AudioSettingsSection: View {
    @AppStorage(AudioSettings.tvEnabledKey) private var tvEnabled = AudioSettings.defaultTvEnabled
    @AppStorage(AudioSettings.tvVolumeKey) private var tvVolume = AudioSettings.defaultTvVolume
    @AppStorage(AudioSettings.tvChannelsKey) private var tvChannelsRaw = AudioSettings.defaultTvChannels

    @AppStorage(AudioSettings.padEnabledKey) private var padEnabled = AudioSettings.defaultPadEnabled
    @AppStorage(AudioSettings.padVolumeKey) private var padVolume = AudioSettings.defaultPadVolume
    @AppStorage(AudioSettings.padChannelsKey) private var padChannelsRaw = AudioSettings.defaultPadChannels

    var body: some View {
        Section {
            tvGroup
            padGroup
        } header: {
            Text("Audio")
        } footer: {
            InfoButton.footer(
                "TV and GamePad have their own volume and channel layout. Turning GamePad audio on plays its track on this device's own speaker or headphones, whether or not a second screen is connected.",
                title: "Audio",
                text: fullText)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    @ViewBuilder private var tvGroup: some View {
        Toggle(isOn: $tvEnabled) {
            Text("TV Audio")
        }
        .tint(MuffinTheme.pixelBlue)
        .onChange(of: tvEnabled) { newValue in
            cemu_bridge_set_tv_audio_enabled(newValue)
        }

        if tvEnabled {
            volumeRow(label: "TV Volume", volume: $tvVolume) { newValue in
                cemu_bridge_set_tv_volume(Int32(newValue))
            }
            Picker("TV Channels", selection: $tvChannelsRaw) {
                ForEach(AudioChannelSetting.allCases) { channels in
                    Text(channels.title).tag(channels.rawValue)
                }
            }
            .foregroundColor(MuffinTheme.brownDarkest)
            .onChange(of: tvChannelsRaw) { newValue in
                cemu_bridge_set_tv_channels(Int32(newValue))
            }
        }
    }

    @ViewBuilder private var padGroup: some View {
        Toggle(isOn: $padEnabled) {
            Text("GamePad Audio")
        }
        .tint(MuffinTheme.pixelBlue)
        .onChange(of: padEnabled) { newValue in
            cemu_bridge_set_pad_audio_enabled(newValue)
        }

        if padEnabled {
            volumeRow(label: "GamePad Volume", volume: $padVolume) { newValue in
                cemu_bridge_set_pad_volume(Int32(newValue))
            }
            Picker("GamePad Channels", selection: $padChannelsRaw) {
                ForEach(AudioChannelSetting.allCases) { channels in
                    Text(channels.title).tag(channels.rawValue)
                }
            }
            .foregroundColor(MuffinTheme.brownDarkest)
            .onChange(of: padChannelsRaw) { newValue in
                cemu_bridge_set_pad_channels(Int32(newValue))
            }
        }
    }

    // Shared row for both volumes: an Int @AppStorage backs the bridge call (it wants
    // 0-100), and this wraps it in a Double Binding for Slider the same way
    // PreviewPadSection.swift wraps its own enum @AppStorage in a Binding rather than
    // storing the Slider's native type directly - the stored type and the control's
    // type just don't match here, so this rounds on the way back in.
    private func volumeRow(label: String, volume: Binding<Int>, onChange: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(volume.wrappedValue)%")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
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
        }
    }

    private var fullText: String {
        "TV Audio and GamePad Audio are separate output tracks, each with its own on/off switch, volume and channel layout - the same three controls desktop Cemu's Audio settings page exposes for TV/GamePad/input, minus device selection (there's only one audio route on iOS, so there's nothing to pick) and minus the input tab (that's a microphone/Wii Remote input path, not output).\n\nChannel layout controls how many speakers the mix expects: Mono collapses everything to one channel, Stereo (the default for both) splits left/right, and Surround asks the game's own mixer for more channels where a title supports it - most don't, and Stereo is the safe default either way.\n\nGamePad Audio is a genuinely separate track from the engine's point of view, not something gated on having a second screen connected - turning it on plays whatever the game sends to the GamePad speaker on this device's own output. Whether a given title actually sends it anything different from the TV mix depends on that title, not on this switch."
    }
}
