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
    /// Settings > Audio > Respect silent mode. Also read by the core when a game's audio starts (iOSAudioAPI.mm).
    static let respectSilentModeKey = "muffin.audio.respectSilentMode"

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
        // Only in the menus: never while a game is loading, running, paused or showing an error.
        inLibrary = emulationState == .idle
        self.appActive = appActive
        refresh()
    }

    /// Re-reads the settings: called when the toggle, the track or the volume changes.
    func refresh() {
        guard enabled, inLibrary, appActive else {
            if player != nil { log("stopped (on=\(enabled), menus=\(inLibrary), active=\(appActive))") }
            stop(); return
        }
        if let player, playingTrack == track {
            player.volume = volume
            if !player.isPlaying { player.play() }
            return
        }
        start(track)
    }

    /// Starts the music again so a changed audio setting applies now.
    func restart() {
        stop()
        refresh()
    }

    private func start(_ track: Track) {
        stop()
        let session = AVAudioSession.sharedInstance()
        // Someone else's music is playing: leave it alone rather than play over it.
        if session.secondaryAudioShouldBeSilencedHint { log("not started: another app is playing audio"); return }
        guard let url = track.url else { log("not started: \(track.rawValue) is missing from the app"); return }
        // With Respect silent mode on, ambient: the silent switch mutes it. Otherwise it plays through silent
        // mode like the game audio does. Either way it mixes with other sounds. A game sets its own category when
        // its audio starts.
        if defaults.bool(forKey: Self.respectSilentModeKey) {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } else {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try? session.setActive(true)
        let player: AVAudioPlayer
        do { player = try AVAudioPlayer(contentsOf: url) } catch { log("not started: \(error.localizedDescription)"); return }
        player.numberOfLoops = -1
        player.volume = volume
        player.prepareToPlay()
        let ok = player.play()
        log("\(ok ? "playing" : "play() refused") \(track.rawValue), volume \(volume), route \(session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: "+"))")
        self.player = player
        playingTrack = track
    }

    private func log(_ message: String) { cemu_bridge_log_checkpoint("Theme music: " + message) }

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
                Text("Plays MuffinEMU's themes on loop in the menus, never in a game. It stays quiet while another app is playing music.")
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

/// Settings > Audio: let the Ring/Silent switch (or Silent mode in Control Centre) mute MuffinEMU.
struct RespectSilentModeToggle: View {
    @AppStorage(MenuMusic.respectSilentModeKey) private var respect = false

    var body: some View {
        Toggle(isOn: $respect) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Respect silent mode")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("When silent mode is on, games and theme music make no sound. Takes effect from the next game you start. With the microphone on, game audio keeps playing.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(MuffinTheme.accentText)
        .onChange(of: respect) { _ in MenuMusic.shared.restart() }
    }
}
