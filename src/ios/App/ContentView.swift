import SwiftUI
import MetalKit

struct ContentView: View {
    @StateObject var gameManager = GameManager()
    @State private var selectedGame: GameMetadata?
    @State private var showingGameBrowser = true
    @State private var showingFavorites = false

    var body: some View {
        ZStack {
            if showingGameBrowser {
                GameBrowserView(
                    gameManager: gameManager,
                    selectedGame: $selectedGame,
                    showingGameBrowser: $showingGameBrowser,
                    showingFavorites: $showingFavorites
                )
            } else if let game = selectedGame, gameManager.emulationState == .running {
                EmulatorView(
                    game: game,
                    gameManager: gameManager,
                    isRunning: $showingGameBrowser
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct GameBrowserView: View {
    @ObservedObject var gameManager: GameManager
    @Binding var selectedGame: GameMetadata?
    @Binding var showingGameBrowser: Bool
    @Binding var showingFavorites: Bool
    @State private var searchText = ""

    var filteredGames: [GameMetadata] {
        let gamesToShow = showingFavorites ? gameManager.favorites : gameManager.games
        return searchText.isEmpty
            ? gamesToShow
            : gamesToShow.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Wii U Emulator")
                    .font(.title)
                    .bold()
                    .foregroundColor(.white)

                HStack {
                    Button(action: { showingFavorites.toggle() }) {
                        Label("Favorites", systemImage: "heart.fill")
                            .foregroundColor(showingFavorites ? .red : .gray)
                    }
                    Spacer()
                    Text("\(filteredGames.count) games")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)

                SearchBar(text: $searchText)
            }
            .padding()
            .background(Color(.systemBackground))

            if gameManager.isLoading {
                VStack {
                    ProgressView()
                    Text("Loading games...")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredGames.isEmpty {
                VStack {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No games found")
                        .font(.headline)
                    Text("Place .wua/.wud/.iso/.rpx files in Documents/Roms")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                        ForEach(filteredGames) { game in
                            GameCard(
                                game: game,
                                onTap: {
                                    selectedGame = game
                                    gameManager.launchGame(game)
                                    showingGameBrowser = false
                                },
                                onFavoriteTap: {
                                    gameManager.toggleFavorite(game)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemBackground))
    }
}

struct GameCard: View {
    let game: GameMetadata
    let onTap: () -> Void
    let onFavoriteTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Color.gray
                if let coverPath = game.coverPath {
                    Image(uiImage: UIImage(contentsOfFile: coverPath) ?? UIImage())
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                }
            }
            .aspectRatio(9 / 12, contentMode: .fit)
            .cornerRadius(8)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.caption)
                    .lineLimit(2)
                    .bold()

                HStack {
                    Text(game.region)
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Button(action: onFavoriteTap) {
                        Image(systemName: game.isFavorite ? "heart.fill" : "heart")
                            .font(.caption)
                            .foregroundColor(game.isFavorite ? .red : .gray)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onTap) {
                Text("Play")
                    .font(.caption)
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search games", text: $text)
                .textFieldStyle(.roundedBorder)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct EmulatorView: View {
    let game: GameMetadata
    @ObservedObject var gameManager: GameManager
    @Binding var isRunning: Bool
    @State private var isPaused = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: {
                        gameManager.stopEmulation()
                        isRunning = true
                    }) {
                        Label("Back", systemImage: "chevron.left")
                            .foregroundColor(.white)
                    }
                    .padding()

                    Spacer()

                    Text(game.title)
                        .foregroundColor(.white)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer()

                    Text("\(gameManager.getFrameRate()) FPS")
                        .foregroundColor(.yellow)
                        .font(.caption2)
                        .padding(.horizontal)
                }
                .background(Color.black.opacity(0.7))

                #if os(iOS)
                MetalViewIOS(gameManager: gameManager)
                    .ignoresSafeArea()
                #else
                MetalView(gameManager: gameManager)
                    .ignoresSafeArea()
                #endif

                ControlPanelView()
            }
        }
    }
}

struct ControlPanelView: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                VStack(spacing: 0) {
                    Button(action: {}) {
                        Text("↑")
                            .frame(width: 40, height: 40)
                            .background(Color.gray.opacity(0.5))
                            .cornerRadius(4)
                    }
                    HStack(spacing: 0) {
                        Button(action: {}) {
                            Text("←")
                                .frame(width: 40, height: 40)
                                .background(Color.gray.opacity(0.5))
                                .cornerRadius(4)
                        }
                        Spacer()
                            .frame(width: 40)
                        Button(action: {}) {
                            Text("→")
                                .frame(width: 40, height: 40)
                                .background(Color.gray.opacity(0.5))
                                .cornerRadius(4)
                        }
                    }
                    Button(action: {}) {
                        Text("↓")
                            .frame(width: 40, height: 40)
                            .background(Color.gray.opacity(0.5))
                            .cornerRadius(4)
                    }
                }

                Spacer()

                VStack(spacing: 0) {
                    Button(action: {}) {
                        Text("Y")
                            .frame(width: 40, height: 40)
                            .background(Color.yellow.opacity(0.7))
                            .cornerRadius(20)
                    }
                    HStack(spacing: 0) {
                        Button(action: {}) {
                            Text("X")
                                .frame(width: 40, height: 40)
                                .background(Color.blue.opacity(0.7))
                                .cornerRadius(20)
                        }
                        Spacer()
                            .frame(width: 40)
                        Button(action: {}) {
                            Text("B")
                                .frame(width: 40, height: 40)
                                .background(Color.red.opacity(0.7))
                                .cornerRadius(20)
                        }
                    }
                    Button(action: {}) {
                        Text("A")
                            .frame(width: 40, height: 40)
                            .background(Color.green.opacity(0.7))
                            .cornerRadius(20)
                    }
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.7))
    }
}

#Preview {
    ContentView()
}
