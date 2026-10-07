// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Theme music in the menus: MuffinEMU's own songs, or the player's own tracks from Documents/Theme Music.
/// Off until it's switched on in Settings > Audio. It stops when a game starts or the app goes to the background.
final class MenuMusic: NSObject, AVAudioPlayerDelegate {
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
            for bundle in [Bundle.main, Bundle(for: MenuMusic.self)] {
                if let url = bundle.url(forResource: "MenuMusic-" + rawValue, withExtension: "caf")
                    ?? bundle.url(forResource: "MenuMusic-" + rawValue, withExtension: "wav") { return url }
            }
            return nil
        }
    }

    /// What the Song picker can choose besides the built-in tracks: every one of the player's own tracks in turn,
    /// or one of them (stored as "custom:" + its file name).
    static let customAllTag = "CustomAll"
    static let customPrefix = "custom:"

    /// Documents/Theme Music: the player's own tracks. Files shows it, so tracks can also be dropped in there.
    static var customFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Theme Music", isDirectory: true)
    }
    static let customExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4"]

    /// The player's own tracks, sorted by name.
    static func customTracks() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: customFolder, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])) ?? []
        return files.filter { customExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private var player: AVAudioPlayer?
    /// The picker value the current player was started for.
    private var playingSelection: String?
    /// For "All my tracks": the queue being played and where it is.
    private var queue: [URL] = []
    private var queueIndex = 0
    private var inLibrary = true
    private var appActive = true

    private var defaults: UserDefaults { .standard }
    private var enabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    private var selection: String { defaults.string(forKey: Self.trackKey) ?? Track.allSongs.rawValue }
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
        if let player, playingSelection == selection {
            player.volume = volume
            if !player.isPlaying { player.play() }
            return
        }
        start(selection)
    }

    /// The files a picker value plays, in order, and whether one file loops on its own.
    private func files(for selection: String) -> (urls: [URL], loopOne: Bool) {
        if selection == Self.customAllTag {
            let all = Self.customTracks()
            return (all, all.count == 1)
        }
        if selection.hasPrefix(Self.customPrefix) {
            let url = Self.customFolder.appendingPathComponent(String(selection.dropFirst(Self.customPrefix.count)))
            return (FileManager.default.fileExists(atPath: url.path) ? [url] : [], true)
        }
        let track = Track(rawValue: selection) ?? .allSongs
        return (track.url.map { [$0] } ?? [], true)
    }

    /// Starts the music again so a changed audio setting applies now.
    func restart() {
        stop()
        refresh()
    }

    private func start(_ selection: String) {
        stop()
        let (urls, loopOne) = files(for: selection)
        guard !urls.isEmpty else { log("not started: nothing to play for \(selection)"); return }
        let session = AVAudioSession.sharedInstance()
        // With Respect silent mode on, ambient: the silent switch mutes it. Otherwise it plays through silent
        // mode like the game audio does. Either way it mixes with other sounds. A game sets its own category when
        // its audio starts.
        if defaults.bool(forKey: Self.respectSilentModeKey) {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } else {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try? session.setActive(true)
        playingSelection = selection
        queue = urls
        queueIndex = 0
        play(at: 0, loop: loopOne)
    }

    /// Plays one file of the queue: looping forever when it is the only one, otherwise once, then the next.
    private func play(at index: Int, loop: Bool) {
        let url = queue[index]
        let player: AVAudioPlayer
        do { player = try AVAudioPlayer(contentsOf: url) } catch {
            log("couldn't play \(url.lastPathComponent): \(error.localizedDescription)")
            // A file that won't play is skipped, as long as another one in the queue might.
            if queue.count > 1, index + 1 < queue.count { play(at: index + 1, loop: false) }
            return
        }
        player.numberOfLoops = loop ? -1 : 0
        player.volume = volume
        player.delegate = self
        player.prepareToPlay()
        let ok = player.play()
        let route = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue).joined(separator: "+")
        log("\(ok ? "playing" : "play() refused") \(url.lastPathComponent), volume \(volume), route \(route)")
        self.player = player
        queueIndex = index
    }

    /// The next of the player's own tracks, back to the first after the last.
    func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, finished === self.player, self.queue.count > 1 else { return }
            self.play(at: (self.queueIndex + 1) % self.queue.count, loop: false)
        }
    }

    private func log(_ message: String) { cemu_bridge_log_checkpoint("Theme music: " + message) }

    private func stop() {
        player?.delegate = nil
        player?.stop()
        player = nil
        playingSelection = nil
        queue = []
    }

    /// Copies picked audio files into Documents/Theme Music; the originals are left where they are.
    /// Returns how many were added.
    @discardableResult
    static func importTracks(_ urls: [URL]) -> Int {
        let fm = FileManager.default
        try? fm.createDirectory(at: customFolder, withIntermediateDirectories: true)
        var added = 0
        for url in urls where customExtensions.contains(url.pathExtension.lowercased()) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var dest = customFolder.appendingPathComponent(url.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                dest = customFolder.appendingPathComponent(
                    "\(url.deletingPathExtension().lastPathComponent) \(n).\(url.pathExtension)")
                n += 1
            }
            if (try? fm.copyItem(at: url, to: dest)) != nil { added += 1 }
        }
        return added
    }
}

/// Settings > Audio: the library's theme music.
struct MenuMusicSettingsGroup: View {
    @AppStorage(MenuMusic.enabledKey) private var enabled = false
    @AppStorage(MenuMusic.trackKey) private var trackRaw = MenuMusic.Track.allSongs.rawValue
    @AppStorage(MenuMusic.volumeKey) private var volume = MenuMusic.defaultVolume
    @State private var customTracks = MenuMusic.customTracks()
    @State private var importing = false

    var body: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Theme music")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Plays MuffinEMU's themes, or your own tracks, on loop in the menus, never in a game.")
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
                if !customTracks.isEmpty {
                    Text("All my tracks").tag(MenuMusic.customAllTag)
                    ForEach(customTracks, id: \.self) { url in
                        Text(url.deletingPathExtension().lastPathComponent)
                            .tag(MenuMusic.customPrefix + url.lastPathComponent)
                    }
                }
            }
            .onChange(of: trackRaw) { _ in MenuMusic.shared.refresh() }

            Button {
                importing = true
            } label: {
                Label("Add your own tracks", systemImage: "plus.circle")
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result, MenuMusic.importTracks(urls) > 0 else { return }
                customTracks = MenuMusic.customTracks()
                // Adding tracks for the first time switches to them, which is what the player came here for.
                if !trackRaw.hasPrefix(MenuMusic.customPrefix) && trackRaw != MenuMusic.customAllTag {
                    trackRaw = MenuMusic.customAllTag
                }
                MenuMusic.shared.restart()
            }

            ForEach(customTracks, id: \.self) { url in
                Label(url.deletingPathExtension().lastPathComponent, systemImage: "music.note")
                    .font(.system(size: 14))
                    .lineLimit(1)
            }
            .onDelete { offsets in
                for i in offsets { try? FileManager.default.removeItem(at: customTracks[i]) }
                customTracks = MenuMusic.customTracks()
                let stillThere = trackRaw == MenuMusic.customAllTag
                    ? !customTracks.isEmpty
                    : !trackRaw.hasPrefix(MenuMusic.customPrefix)
                        || customTracks.contains { MenuMusic.customPrefix + $0.lastPathComponent == trackRaw }
                if !stillThere { trackRaw = MenuMusic.Track.allSongs.rawValue }
                MenuMusic.shared.restart()
            }

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
