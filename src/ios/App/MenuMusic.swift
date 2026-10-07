import AVFoundation
import SwiftUI

/// MuffinEMU's own theme songs, looping quietly behind the library while no game is running.
/// Off until it's switched on in Settings > Audio. It stops when a game starts or the app leaves the
/// screen, and it never plays over music from another app.
final class MenuMusic {
    static let shared = MenuMusic()

    static let enabledKey = "muffin.menuMusic.enabled"
    static let trackKey = "muffin.menuMusic.track"
    static let volumeKey = "muffin.menuMusic.volume"
    static let defaultVolume = 0.6

    enum Track: String, CaseIterable, Identifiable {
        /// All five, four times each, crossfaded into one another, with the end crossfaded back into the start:
        /// one file mixed ahead of time, so it loops with no gap or click.
        case allSongs = "AllSongs"
        case muffinTheme = "MuffinTheme"
        case horizonDrive = "HorizonDrive"
        case starfall = "Starfall"
        case phaseShift = "PhaseShift"
        case labRats = "LabRats"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .allSongs: return "All songs"
            case .muffinTheme: return "MuffinEMU Theme"
            case .horizonDrive: return "Horizon Drive"
            case .starfall: return "Starfall"
            case .phaseShift: return "Phase Shift"
            case .labRats: return "Lab Rats"
            }
        }

        var url: URL? {
            Bundle.main.url(forResource: "MenuMusic-" + rawValue, withExtension: "caf")
                ?? Bundle.main.url(forResource: "MenuMusic-" + rawValue, withExtension: "wav")
        }
    }

    private var player: AVAudioPlayer?
    private var playingTrack: Track?
    private var inLibrary = true
    private var appActive = true

    private var defaults: UserDefaults { .standard }
    private var enabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    private var track: Track { Track(rawValue: defaults.string(forKey: Self.trackKey) ?? "") ?? .allSongs }
    private var volume: Float {
        Float(defaults.object(forKey: Self.volumeKey) as? Double ?? Self.defaultVolume)
    }

    /// Called whenever the emulation state or the scene phase changes.
    func update(emulationState: EmulationState, appActive: Bool) {
        inLibrary = emulationState == .idle || emulationState == .error
        self.appActive = appActive
        refresh()
    }

    /// Re-reads the settings: called when the toggle, the track or the volume changes.
    func refresh() {
        guard enabled, inLibrary, appActive else { stop(); return }
        if let player, playingTrack == track {
            player.volume = volume
            if !player.isPlaying { player.play() }
            return
        }
        start(track)
    }

    private func start(_ track: Track) {
        stop()
        let session = AVAudioSession.sharedInstance()
        // Someone else's music is playing: leave it alone rather than play over it.
        guard !session.secondaryAudioShouldBeSilencedHint, let url = track.url else { return }
        // Ambient: mixes with other sounds and follows the silent switch, like menu music should.
        // A game sets its own category when its audio starts.
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = volume
        player.prepareToPlay()
        player.play()
        self.player = player
        playingTrack = track
    }

    private func stop() {
        player?.stop()
        player = nil
        playingTrack = nil
    }
}

/// Settings > Audio: the library's theme music.
struct MenuMusicSettingsGroup: View {
    @AppStorage(MenuMusic.enabledKey) private var enabled = false
    @AppStorage(MenuMusic.trackKey) private var trackRaw = MenuMusic.Track.allSongs.rawValue
    @AppStorage(MenuMusic.volumeKey) private var volume = MenuMusic.defaultVolume

    var body: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Theme music")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Plays MuffinEMU's themes on loop in the library. It stops when a game starts, and stays quiet while another app is playing music.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(MuffinTheme.accentText)
        .onChange(of: enabled) { _ in MenuMusic.shared.refresh() }

        if enabled {
            Picker("Song", selection: $trackRaw) {
                ForEach(MenuMusic.Track.allCases) { track in
                    Text(track.title).tag(track.rawValue)
                }
            }
            .onChange(of: trackRaw) { _ in MenuMusic.shared.refresh() }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").foregroundColor(.secondary)
                Slider(value: $volume, in: 0...1)
                    .tint(MuffinTheme.accentText)
                    .onChange(of: volume) { _ in MenuMusic.shared.refresh() }
                Image(systemName: "speaker.wave.3.fill").foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Theme music volume")
        }
    }
}
