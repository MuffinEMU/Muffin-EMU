import SwiftUI
import MetalKit

struct ContentView: View {
    @StateObject var gameManager = GameManager()
    @State private var selectedGame: GameMetadata?
    @State private var showingGameBrowser = true
    @State private var showingFavorites = false
    @State private var selectedSkin: WiiUControllerSkin = WiiUControllerSkin.standard

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
                EmulatorViewOptimized(
                    game: game,
                    gameManager: gameManager,
                    isRunning: $showingGameBrowser,
                    controllerSkin: $selectedSkin
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
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.15),
                    Color(red: 0.08, green: 0.10, blue: 0.20)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wii U")
                            .font(.system(size: 28, weight: .bold, design: .default))
                            .foregroundColor(.white)

                        Text("Emulator")
                            .font(.system(size: 18, weight: .semibold, design: .default))
                            .foregroundColor(Color(red: 0.4, green: 0.6, blue: 1.0))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 8) {
                            Button(action: { showingFavorites.toggle() }) {
                                Image(systemName: showingFavorites ? "heart.fill" : "heart")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(showingFavorites ? Color(red: 1.0, green: 0.4, blue: 0.4) : Color(red: 0.6, green: 0.6, blue: 0.6))
                            }
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(filteredGames.count)")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                Text("games")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                            }
                        }
                    }
                }
                .padding(20)
                .background(Color.white.opacity(0.03))
                .borderBottom(width: 0.5, color: Color.white.opacity(0.1))

                VStack(spacing: 12) {
                    SearchBarPolished(text: $searchText)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    if gameManager.isLoading {
                        LoadingView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredGames.isEmpty {
                        EmptyGamesView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 140), spacing: 16)],
                                spacing: 20
                            ) {
                                ForEach(filteredGames) { game in
                                    GameCardOptimized(
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
                            .padding(16)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

struct GameCardOptimized: View {
    let game: GameMetadata
    let onTap: () -> Void
    let onFavoriteTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.1, green: 0.15, blue: 0.3),
                                Color(red: 0.08, green: 0.12, blue: 0.25)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let coverPath = game.coverPath,
                   let uiImage = UIImage(contentsOfFile: coverPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .cornerRadius(12)
                        .clipped()
                } else {
                    VStack {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Color(red: 0.4, green: 0.6, blue: 1.0))
                    }
                }

                VStack {
                    HStack {
                        Spacer()
                        Button(action: onFavoriteTap) {
                            Image(systemName: game.isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(game.isFavorite ? Color(red: 1.0, green: 0.4, blue: 0.4) : .white)
                                .frame(width: 32, height: 32)
                                .background(Color.black.opacity(0.4))
                                .cornerRadius(8)
                        }
                        .padding(8)
                    }
                    Spacer()
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)

            VStack(alignment: .leading, spacing: 8) {
                Text(game.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    Label(game.region, systemImage: "globe")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                    Spacer()
                }

                Button(action: onTap) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Play")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.3, green: 0.6, blue: 1.0),
                                Color(red: 0.2, green: 0.5, blue: 0.95)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            .padding(12)
            .background(Color(red: 0.08, green: 0.10, blue: 0.18))
        }
        .background(Color(red: 0.08, green: 0.10, blue: 0.18))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

struct SearchBarPolished: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))

            TextField("Search games...", text: $text)
                .font(.system(size: 15, weight: .regular))
                .textFieldStyle(.plain)
                .foregroundColor(.white)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                }
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct LoadingView: View {
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 48, weight: .semibold))
                .foregroundColor(Color(red: 0.4, green: 0.6, blue: 1.0))
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

            Text("Loading games...")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

struct EmptyGamesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 56, weight: .regular))
                .foregroundColor(Color(red: 0.4, green: 0.6, blue: 1.0).opacity(0.5))

            VStack(spacing: 8) {
                Text("No Games Found")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                VStack(alignment: .center, spacing: 4) {
                    Text("Add .wua, .wud, .rpx, or .iso files")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))

                    Text("to Documents/Roms/ on your device")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmulatorViewOptimized: View {
    let game: GameMetadata
    @ObservedObject var gameManager: GameManager
    @Binding var isRunning: Bool
    @Binding var controllerSkin: WiiUControllerSkin
    @State private var showControls = true
    @State private var showSkinSelector = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: {
                        gameManager.stopEmulation()
                        isRunning = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(height: 40)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                    }

                    VStack(alignment: .center, spacing: 2) {
                        Text(game.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(controllerSkin.name)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundColor(Color(red: 0.4, green: 0.6, blue: 1.0))
                    }
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 8) {
                        Button(action: { showSkinSelector.toggle() }) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(red: 0.4, green: 0.6, blue: 1.0))
                        }
                        .frame(width: 32, height: 40)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)

                        HStack(spacing: 6) {
                            Image(systemName: "speedometer")
                                .font(.system(size: 12, weight: .semibold))
                            Text("\(gameManager.getFrameRate()) FPS")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(gameManager.getFrameRate() >= 20 ? Color(red: 0.4, green: 0.9, blue: 0.4) : Color(red: 1.0, green: 0.6, blue: 0.4))
                        .frame(height: 40)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.5))
                .borderBottom(width: 0.5, color: Color.white.opacity(0.1))

                if showSkinSelector {
                    OrganizedControllerSkinSelector(selectedSkin: $controllerSkin)
                        .padding(12)
                        .background(Color.black.opacity(0.7))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                #if os(iOS)
                MetalViewIOS(gameManager: gameManager)
                    .ignoresSafeArea()
                #else
                MetalView(gameManager: gameManager)
                    .ignoresSafeArea()
                #endif

                if showControls {
                    OptimizedControlPanel(
                        skin: controllerSkin,
                        onDPadInput: { _ in },
                        onButtonInput: { _ in }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls.toggle()
            }
        }
    }
}

struct BorderBottomModifier: ViewModifier {
    let width: CGFloat
    let color: Color

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            Divider()
                .frame(height: width)
                .background(color)
        }
    }
}

extension View {
    func borderBottom(width: CGFloat, color: Color) -> some View {
        self.modifier(BorderBottomModifier(width: width, color: color))
    }
}

#Preview {
    ContentView()
}
