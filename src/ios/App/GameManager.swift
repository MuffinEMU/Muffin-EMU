import Foundation
import SwiftUI

struct GameMetadata: Codable, Identifiable {
    let id: String
    let title: String
    let romPath: String
    let coverPath: String?
    let region: String
    let releaseDate: String
    let genre: String
    var isFavorite: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, romPath, coverPath, region, releaseDate, genre
    }
}

@MainActor
class GameManager: ObservableObject {
    @Published var games: [GameMetadata] = []
    @Published var favorites: [GameMetadata] = []
    @Published var isLoading = false
    @Published var currentGame: GameMetadata?
    @Published var emulationState: EmulationState = .idle

    private let romsDirectory = "Roms"
    private let gameListFile = "games.json"
    private var emulationEngine: EmulationEngine?

    init() {
        emulationEngine = EmulationEngine()
        Task {
            await loadGames()
        }
    }

    func loadGames() async {
        isLoading = true
        defer { isLoading = false }

        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let romsPath = documentsPath.appendingPathComponent(romsDirectory)

        try? fileManager.createDirectory(at: romsPath, withIntermediateDirectories: true)

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: romsPath,
                includingPropertiesForKeys: nil
            )

            var discoveredGames: [GameMetadata] = []

            for item in contents {
                let pathExtension = item.pathExtension.lowercased()
                guard ["wua", "wud", "iso", "rpx"].contains(pathExtension) else { continue }

                let gameID = item.deletingPathExtension().lastPathComponent

                let gameMetadata = GameMetadata(
                    id: gameID,
                    title: gameID,
                    romPath: item.path,
                    coverPath: findCover(for: gameID, in: romsPath),
                    region: "Unknown",
                    releaseDate: "Unknown",
                    genre: "Game"
                )

                discoveredGames.append(gameMetadata)
            }

            self.games = discoveredGames.sorted { $0.title < $1.title }
            self.favorites = self.games.filter { $0.isFavorite }
        } catch {
            print("Error scanning Roms directory: \(error)")
        }
    }

    private func findCover(for gameID: String, in directory: URL) -> String? {
        let fileManager = FileManager.default

        for ext in ["jpg", "jpeg", "png"] {
            let coverPath = directory.appendingPathComponent("\(gameID)_cover.\(ext)")
            if fileManager.fileExists(atPath: coverPath.path) {
                return coverPath.path
            }
        }

        return nil
    }

    func toggleFavorite(_ game: GameMetadata) {
        if let index = games.firstIndex(where: { $0.id == game.id }) {
            games[index].isFavorite.toggle()

            if games[index].isFavorite {
                favorites.append(games[index])
            } else {
                favorites.removeAll { $0.id == game.id }
            }
        }
    }

    func launchGame(_ game: GameMetadata) {
        currentGame = game
        emulationState = .loading

        guard let engine = emulationEngine else {
            emulationState = .error
            return
        }

        engine.loadROM(game.romPath)
        engine.startEmulation()
        emulationState = .running
    }

    func stopEmulation() {
        emulationEngine?.stopEmulation()
        emulationState = .idle
        currentGame = nil
    }

    func getEmulationEngine() -> EmulationEngine? {
        return emulationEngine
    }

    func getFrameTexture() -> MTLTexture? {
        return emulationEngine?.getFrameTexture()
    }

    func getFrameRate() -> Int {
        return emulationEngine?.frameRate ?? 0
    }
}

enum EmulationState {
    case idle
    case loading
    case running
    case paused
    case error
}
