import SwiftUI
import UIKit

// How the library is laid out and organised: card style, grouping, a quick filter, and the
// light local play history the "last played" and "most played" sorts read. Every choice is
// kept in UserDefaults under a "muffin.library." key, same as the sort order, so it is still
// there after a relaunch and a settings reset puts it back.

// MARK: - Card style

enum LibraryCardStyle: String, CaseIterable, Hashable, Identifiable {
    case standard
    case largeCovers
    case compact
    case list
    case box3d

    static let storageKey = "muffin.library.cardStyle"
    static let defaultValue: LibraryCardStyle = .standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Cards"
        case .largeCovers: return "Large covers"
        case .compact: return "Compact grid"
        case .list: return "List"
        case .box3d: return "3D boxes"
        }
    }

    var detail: String {
        switch self {
        case .standard: return "Cover, name and a Play button"
        case .largeCovers: return "Bigger covers, tap a cover to play"
        case .compact: return "Many small covers on screen at once"
        case .list: return "One game per row, with details"
        case .box3d: return "Box art standing free, 3D when a pack has it"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: return "square.grid.2x2"
        case .largeCovers: return "square.grid.2x2.fill"
        case .compact: return "square.grid.3x3"
        case .list: return "list.bullet"
        case .box3d: return "cube"
        }
    }

    /// Where the Card size slider is stored (Settings > Library). 1.0 is the default size.
    static let sizeStorageKey = "muffin.library.cardSize"
    static let sizeRange: ClosedRange<Double> = 0.7...1.6

    /// Column layout for this style. Adaptive, so an iPhone in portrait gets fewer columns than
    /// an iPad or a phone turned sideways without any size-class checks.
    var columns: [GridItem] { columns(scale: 1) }

    /// The same layout with the card size slider applied. Every card's minimum width scales,
    /// capped at 340 pt so one card still fits across the narrowest supported screen.
    func columns(scale: Double) -> [GridItem] {
        let s = CGFloat(min(max(scale, Self.sizeRange.lowerBound), Self.sizeRange.upperBound))
        func item(_ base: CGFloat, _ spacing: CGFloat) -> [GridItem] {
            [GridItem(.adaptive(minimum: min(base * s, 340)), spacing: spacing)]
        }
        switch self {
        case .standard: return item(140, 16)
        case .largeCovers: return item(220, 18)
        case .compact: return item(96, 12)
        case .list: return item(340, 12)
        case .box3d: return item(150, 14)
        }
    }

    var rowSpacing: CGFloat {
        switch self {
        case .standard: return 20
        case .largeCovers: return 22
        case .compact: return 14
        case .list: return 10
        case .box3d: return 18
        }
    }

    static var current: LibraryCardStyle {
        LibraryCardStyle(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? defaultValue
    }
}

// MARK: - Grouping and filter

/// Section headers in the library. Niche, so the choice lives in Advanced settings mode.
enum LibraryGrouping: String, CaseIterable, Hashable, Identifiable {
    case none
    case favorites
    case recentlyPlayed
    case alphabet

    static let storageKey = "muffin.library.grouping"
    static let defaultValue: LibraryGrouping = .none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No groups"
        case .favorites: return "Favourites and the rest"
        case .recentlyPlayed: return "Recently played"
        case .alphabet: return "A to Z"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "rectangle.grid.1x2"
        case .favorites: return "heart"
        case .recentlyPlayed: return "clock.arrow.circlepath"
        case .alphabet: return "textformat.abc"
        }
    }
}

/// A quick filter on top of search. Favorites has its own switch elsewhere in the app; this adds
/// the ones that need play history.
enum LibraryFilter: String, CaseIterable, Hashable, Identifiable {
    case all
    case favorites
    case played
    case neverPlayed

    static let storageKey = "muffin.library.filter"
    static let defaultValue: LibraryFilter = .all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All games"
        case .favorites: return "Favourites only"
        case .played: return "Played before"
        case .neverPlayed: return "Never played"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "heart"
        case .played: return "checkmark.circle"
        case .neverPlayed: return "sparkles"
        }
    }

    func apply(_ games: [GameMetadata], stats: LibraryPlayStats) -> [GameMetadata] {
        switch self {
        case .all: return games
        case .favorites: return games.filter { $0.isFavorite }
        case .played: return games.filter { stats.entry(for: $0.id) != nil }
        case .neverPlayed: return games.filter { stats.entry(for: $0.id) == nil }
        }
    }
}

struct LibrarySection: Identifiable {
    let id: String
    let title: String?
    let games: [GameMetadata]
}

extension LibraryGrouping {
    /// Splits an already filtered and sorted list into sections. Empty sections are left out, and
    /// each section keeps the order it was given.
    func sections(for games: [GameMetadata], stats: LibraryPlayStats) -> [LibrarySection] {
        switch self {
        case .none:
            return [LibrarySection(id: "all", title: nil, games: games)]
        case .favorites:
            let favs = games.filter { $0.isFavorite }
            let rest = games.filter { !$0.isFavorite }
            return [
                LibrarySection(id: "favorites", title: "Favourites", games: favs),
                LibrarySection(id: "rest", title: favs.isEmpty ? nil : "Other games", games: rest),
            ].filter { !$0.games.isEmpty }
        case .recentlyPlayed:
            let recentIDs = Set(stats.recentIDs(limit: 8))
            let recent = games.filter { recentIDs.contains($0.id) }
                .sorted { (stats.entry(for: $0.id)?.last ?? .distantPast) > (stats.entry(for: $1.id)?.last ?? .distantPast) }
            let rest = games.filter { !recentIDs.contains($0.id) }
            return [
                LibrarySection(id: "recent", title: "Recently played", games: recent),
                LibrarySection(id: "rest", title: recent.isEmpty ? nil : "Everything else", games: rest),
            ].filter { !$0.games.isEmpty }
        case .alphabet:
            var order: [String] = []
            var buckets: [String: [GameMetadata]] = [:]
            for game in games {
                let letter = Self.letter(for: game)
                if buckets[letter] == nil { order.append(letter) }
                buckets[letter, default: []].append(game)
            }
            let sortedLetters = order.sorted { a, b in
                if a == "#" { return false }
                if b == "#" { return true }
                return a < b
            }
            return sortedLetters.map { LibrarySection(id: "az-\($0)", title: $0, games: buckets[$0] ?? []) }
        }
    }

    /// Same field the Title sort uses, so the letters line up with the order of the games.
    private static func letter(for game: GameMetadata) -> String {
        let folded = game.sortTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard let first = folded.unicodeScalars.first,
              CharacterSet.letters.contains(first) else { return "#" }
        return String(first).uppercased()
    }
}

// MARK: - Custom names

/// A name the player gave a game, shown in the library instead of its own title. Display only:
/// nothing on disk is renamed and the title ID is untouched. Keyed by `GameMetadata.installKey` (the install's file
/// or folder name in Roms), so two installs of one title keep separate names. Names saved before that were keyed by
/// the title ID, and `migrateLegacyKeys` moves them over.
final class LibraryCustomNames: ObservableObject {
    static let shared = LibraryCustomNames()
    private static let defaultsKey = "muffin.library.customNames"

    @Published private(set) var names: [String: String]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            names = decoded
        } else {
            names = [:]
        }
    }

    func name(for key: String) -> String? { names[key] }

    /// Moves a name saved under an old title-ID key to the install it belongs to. One matching install gets it. When
    /// several installs share the key there is no telling which one was meant, so the name is dropped. A key with no
    /// installed match stays, in case the game comes back.
    func migrateLegacyKeys(games: [GameMetadata]) {
        let legacy = names.keys.filter { !$0.hasPrefix("install:") }
        guard !legacy.isEmpty, !games.isEmpty else { return }
        var changed = false
        for key in legacy {
            let matches = games.filter { $0.settingsKey == key }
            if matches.isEmpty { continue }
            if matches.count == 1, let value = names[key], names[matches[0].installKey] == nil {
                names[matches[0].installKey] = value
            }
            names.removeValue(forKey: key)
            changed = true
        }
        if changed, let data = try? JSONEncoder().encode(names) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// nil, or a name that is empty after trimming, goes back to the original title.
    func set(_ name: String?, for key: String) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { names.removeValue(forKey: key) } else { names[key] = trimmed }
        if let data = try? JSONEncoder().encode(names) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

struct LibraryRenameSheet: View {
    let game: GameMetadata
    @Environment(\.presentationMode) private var presentationMode
    @State private var text: String

    init(game: GameMetadata) {
        self.game = game
        _text = State(initialValue: LibraryCustomNames.shared.name(for: game.installKey) ?? game.cardName.name)
    }

    private var originalTitle: String { game.displayTitle ?? game.title }
    private var installDescription: String { game.installLabel ?? "" }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Name", text: $text)
                        .autocapitalization(.words)
                } footer: {
                    Text("Only changes how the game is named in your library. Original title: \(originalTitle)"
                         + (installDescription.isEmpty ? "" : "\nInstall: \(installDescription)"))
                }
                if LibraryCustomNames.shared.name(for: game.installKey) != nil {
                    Section {
                        Button("Reset to Original Title") {
                            LibraryCustomNames.shared.set(nil, for: game.installKey)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // A name left the same as the original is no override at all.
                        let same = text.trimmingCharacters(in: .whitespacesAndNewlines) == originalTitle
                        LibraryCustomNames.shared.set(same ? nil : text, for: game.installKey)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Play history

/// Last played date and launch count per game, kept on this device only. The app had no play
/// history before; this is the smallest thing the play-based sorts, filters and groups need.
final class LibraryPlayStats: ObservableObject {
    static let shared = LibraryPlayStats()
    private static let defaultsKey = "muffin.library.playStats"

    struct Entry: Codable {
        var last: Date
        var count: Int
    }

    @Published private(set) var entries: [String: Entry]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func entry(for gameID: String) -> Entry? { entries[gameID] }

    func recordLaunch(of gameID: String) {
        var entry = entries[gameID] ?? Entry(last: Date(), count: 0)
        entry.last = Date()
        entry.count += 1
        entries[gameID] = entry
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    func recentIDs(limit: Int) -> [String] {
        entries.sorted { $0.value.last > $1.value.last }.prefix(limit).map { $0.key }
    }
}

// MARK: - Layout

/// The scrolling collection: sections with optional pinned headers, laid out for the chosen card
/// style. The caller supplies the card so taps, favorites and the long-press menu stay where they
/// already were.
struct LibraryGameCollection<Card: View, Lead: View>: View {
    let sections: [LibrarySection]
    let style: LibraryCardStyle
    @ViewBuilder let lead: () -> Lead
    @ViewBuilder let card: (GameMetadata) -> Card
    @AppStorage(LibraryCardStyle.sizeStorageKey) private var cardSize = 1.0

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: style.columns(scale: cardSize), spacing: style.rowSpacing, pinnedViews: [.sectionHeaders]) {
                Section { lead() }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.games) { game in
                            card(game)
                        }
                    } header: {
                        if let title = section.title {
                            LibrarySectionHeader(title: title, count: section.games.count)
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

struct LibrarySectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(MuffinTheme.brownDarkest)
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(MuffinTheme.brownMid)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(MuffinTheme.cream)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Cards

/// The cover on the theme's own muffin-top gradient, or the controller glyph when there is no art.
struct LibraryCoverWell: View {
    let game: GameMetadata
    var radius: CGFloat = 14
    var glyphSize: CGFloat = 24

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(MuffinTheme.muffinTopGradient)
            if let path = game.coverPath {
                CoverImage(path: path, padding: 8)
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: glyphSize))
                    .foregroundColor(MuffinTheme.onMuffinTop)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

private struct LibraryHeartButton: View {
    let isFavorite: Bool
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundColor(isFavorite ? MuffinTheme.alertOnDark : MuffinTheme.sparkleCream)
                .frame(width: size, height: size)
                .background(Color.black.opacity(0.4))
                .cornerRadius(10)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(isFavorite ? "Remove from favourites" : "Add to favourites")
    }
}

/// The "..." button: the same per-game menu a long-press opens.
private struct LibraryOptionsButton<Options: View>: View {
    let name: String
    let size: CGFloat
    let options: Options

    var body: some View {
        Menu {
            options
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundColor(MuffinTheme.sparkleCream)
                .frame(width: size, height: size)
                .background(Color.black.opacity(0.4))
                .cornerRadius(10)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options for \(name)")
    }
}

private func libraryCardChrome<V: View>(_ view: V, radius: CGFloat = 16) -> some View {
    view
        .background(MuffinTheme.cream)
        .cornerRadius(radius)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(MuffinTheme.wrapper, lineWidth: 1)
        )
        .shadow(color: MuffinTheme.shadow.opacity(0.15), radius: 8, x: 0, y: 4)
}

/// Picks the view for the chosen style. The standard style is the existing GameCardOptimized.
struct LibraryCard<Options: View>: View {
    let game: GameMetadata
    let style: LibraryCardStyle
    let onTap: () -> Void
    let onFavoriteTap: () -> Void
    /// What the standard card's Play button does; nil means the same as a tap on the card.
    var onPlay: (() -> Void)?
    /// The per-game menu behind the "..." button (the same one a long-press opens).
    let options: Options

    init(game: GameMetadata, style: LibraryCardStyle, onTap: @escaping () -> Void,
         onFavoriteTap: @escaping () -> Void, onPlay: (() -> Void)? = nil,
         @ViewBuilder options: () -> Options) {
        self.game = game
        self.style = style
        self.onTap = onTap
        self.onFavoriteTap = onFavoriteTap
        self.onPlay = onPlay
        self.options = options()
    }

    var body: some View {
        switch style {
        case .standard:
            GameCardOptimized(game: game, onTap: onTap, onFavoriteTap: onFavoriteTap, onPlay: onPlay, options: { options })
        case .largeCovers:
            LibraryLargeCoverCard(game: game, onTap: onTap, onFavoriteTap: onFavoriteTap, options: options)
        case .compact:
            LibraryCompactCard(game: game, onTap: onTap, onFavoriteTap: onFavoriteTap, options: options)
        case .list:
            LibraryListRow(game: game, onTap: onTap, onFavoriteTap: onFavoriteTap, options: options)
        case .box3d:
            LibraryBox3DCard(game: game, onTap: onTap, onFavoriteTap: onFavoriteTap, options: options)
        }
    }
}

struct LibraryLargeCoverCard<Options: View>: View {
    let game: GameMetadata
    let onTap: () -> Void
    let onFavoriteTap: () -> Void
    let options: Options

    var body: some View {
        let name = game.cardName
        libraryCardChrome(
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    Button(action: onTap) {
                        LibraryCoverWell(game: game, radius: 0, glyphSize: 44)
                            .aspectRatio(3 / 4, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(name.name)")
                    LibraryHeartButton(isFavorite: game.isFavorite, size: 34, action: onFavoriteTap)
                        .padding(4)
                }
                .overlay(alignment: .topLeading) {
                    LibraryOptionsButton(name: name.name, size: 34, options: options)
                        .padding(4)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(name.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .foregroundColor(MuffinTheme.brownDarkest)
                    if let region = game.region {
                        Label(region, systemImage: "globe")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(MuffinTheme.brownMid)
                    }
                    if let label = game.installLabel { LibraryInstallLine(text: label, size: 12) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        )
        // The whole card starts the game; the heart and "..." keep their own taps.
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onTap)
    }
}

struct LibraryCompactCard<Options: View>: View {
    let game: GameMetadata
    let onTap: () -> Void
    let onFavoriteTap: () -> Void
    let options: Options

    var body: some View {
        let name = game.cardName
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Button(action: onTap) {
                    LibraryCoverWell(game: game, radius: 12, glyphSize: 22)
                        .aspectRatio(3 / 4, contentMode: .fit)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(name.name)")
                LibraryHeartButton(isFavorite: game.isFavorite, size: 26, action: onFavoriteTap)
                    .padding(.top, -6)
                    .padding(.trailing, -6)
            }
            .overlay(alignment: .topLeading) {
                LibraryOptionsButton(name: name.name, size: 26, options: options)
                    .padding(.top, -6)
                    .padding(.leading, -6)
            }
            Text(name.name)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(MuffinTheme.brownDarkest)
                .frame(maxWidth: .infinity)
            if let label = game.installLabel { LibraryInstallLine(text: label, size: 10, centered: true) }
        }
        .shadow(color: MuffinTheme.shadow.opacity(0.12), radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct LibraryListRow<Options: View>: View {
    let game: GameMetadata
    let onTap: () -> Void
    let onFavoriteTap: () -> Void
    let options: Options
    @ObservedObject private var stats = LibraryPlayStats.shared

    private var detailLine: String {
        var parts: [String] = []
        if let region = game.region { parts.append(region) }
        if let entry = stats.entry(for: game.id) {
            let relative = RelativeDateTimeFormatter()
            relative.unitsStyle = .short
            parts.append("Played " + relative.localizedString(for: entry.last, relativeTo: Date()))
            if entry.count > 1 { parts.append("\(entry.count) launches") }
        } else {
            parts.append("Not played yet")
        }
        return parts.joined(separator: "  \u{2022}  ")
    }

    var body: some View {
        let name = game.cardName
        libraryCardChrome(
            HStack(spacing: 12) {
                Button(action: onTap) {
                    HStack(spacing: 12) {
                        LibraryCoverWell(game: game, radius: 10, glyphSize: 18)
                            .frame(width: 56, height: 74)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name.name)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .foregroundColor(MuffinTheme.brownDarkest)
                            if let label = game.installLabel { LibraryInstallLine(text: label, size: 12) }
                            Text(detailLine)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .foregroundColor(MuffinTheme.brownMid)
                            if let idText = name.titleIdText {
                                Text(idText)
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .foregroundColor(MuffinTheme.brownMid)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(name.name)")

                Menu {
                    options
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(MuffinTheme.brownMid)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More options for \(name.name)")

                Button(action: onFavoriteTap) {
                    Image(systemName: game.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(game.isFavorite ? MuffinTheme.alertText : MuffinTheme.brownMid)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(game.isFavorite ? "Remove from favourites" : "Add to favourites")
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 8),
            radius: 14
        )
    }
}

// MARK: - Controls

/// The sort button's sibling in the search row: card style for everyone, grouping and the quick
/// filter when Settings mode is Advanced.
struct LibraryViewMenu: View {
    @AppStorage(LibraryCardStyle.storageKey) private var styleRaw = LibraryCardStyle.defaultValue.rawValue
    @AppStorage(LibraryGrouping.storageKey) private var groupingRaw = LibraryGrouping.defaultValue.rawValue
    @AppStorage(LibraryFilter.storageKey) private var filterRaw = LibraryFilter.defaultValue.rawValue
    @AppStorage(SettingsMode.storageKey) private var modeRaw = SettingsMode.defaultValue.rawValue

    var body: some View {
        Menu {
            Section("Show games as") {
                ForEach(LibraryCardStyle.allCases) { style in
                    Button { styleRaw = style.rawValue } label: {
                        Label(style.title, systemImage: styleRaw == style.rawValue ? "checkmark" : style.systemImage)
                    }
                }
            }
            if SettingsMode.isAdvanced(raw: modeRaw) {
                Section("Group by") {
                    ForEach(LibraryGrouping.allCases) { grouping in
                        Button { groupingRaw = grouping.rawValue } label: {
                            Label(grouping.title, systemImage: groupingRaw == grouping.rawValue ? "checkmark" : grouping.systemImage)
                        }
                    }
                }
                Section("Show") {
                    ForEach(LibraryFilter.allCases) { filter in
                        Button { filterRaw = filter.rawValue } label: {
                            Label(filter.title, systemImage: filterRaw == filter.rawValue ? "checkmark" : filter.systemImage)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: (LibraryCardStyle(rawValue: styleRaw) ?? .standard).systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(MuffinTheme.brownMid)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Library layout")
    }
}

// MARK: - Duplicate installs

/// The small line under a game's name that says which install it is, shown only when the library holds more than one
/// install of the same game.
struct LibraryInstallLine: View {
    let text: String
    let size: CGFloat
    var centered = false

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: .rounded))
            .foregroundColor(MuffinTheme.brownMid)
            .lineLimit(2)
            .multilineTextAlignment(centered ? .center : .leading)
            .frame(maxWidth: centered ? .infinity : nil, alignment: centered ? .center : .leading)
    }
}

/// Works out, for each install that has a twin (same title ID or same name), a short line from what differs between
/// them: region, then format, then the file name. The file name is also added whenever the rest would still read the
/// same. Rebuilt whenever the game list changes.
final class DuplicateInstalls {
    static let shared = DuplicateInstalls()
    private var labels: [String: String] = [:]

    func label(for id: String) -> String? { labels[id] }

    private static func format(of game: GameMetadata) -> String {
        let ext = (game.romPath as NSString).pathExtension.lowercased()
        switch ext {
        case "wua": return "WUA"
        case "wud": return "WUD"
        case "wux": return "WUX"
        case "rpx", "tmd": return "Folder"
        default: return ext.isEmpty ? "Folder" : ext.uppercased()
        }
    }

    private static func fileName(of game: GameMetadata) -> String {
        String(game.installKey.dropFirst("install:".count))
    }

    func update(_ games: [GameMetadata]) {
        var byTitle: [UInt64: [GameMetadata]] = [:]
        var byName: [String: [GameMetadata]] = [:]
        for game in games {
            if let t = game.titleId { byTitle[t, default: []].append(game) }
            let name = (game.displayTitle ?? game.title).lowercased()
            byName[name, default: []].append(game)
        }
        var result: [String: String] = [:]
        for game in games {
            var group: [String: GameMetadata] = [game.id: game]
            if let t = game.titleId { byTitle[t]?.forEach { group[$0.id] = $0 } }
            byName[(game.displayTitle ?? game.title).lowercased()]?.forEach { group[$0.id] = $0 }
            guard group.count > 1 else { continue }
            let peers = Array(group.values)
            var parts: [String] = []
            if Set(peers.map { $0.region ?? "" }).count > 1, let region = game.region { parts.append(region) }
            if Set(peers.map(Self.format(of:))).count > 1 { parts.append(Self.format(of: game)) }
            let line = parts.joined(separator: ", ")
            result[game.id] = line.isEmpty ? Self.fileName(of: game) : line
        }
        // Two installs that still read the same get their file names added.
        var counts: [String: Int] = [:]
        for (id, line) in result { counts[(games.first { $0.id == id }?.titleId.map(String.init) ?? "") + "|" + line, default: 0] += 1 }
        for game in games {
            guard let line = result[game.id] else { continue }
            let key = (game.titleId.map(String.init) ?? "") + "|" + line
            if (counts[key] ?? 0) > 1, line != Self.fileName(of: game) {
                result[game.id] = line + ", " + Self.fileName(of: game)
            }
        }
        labels = result
    }
}

// MARK: - 3D boxes card

/// The "3D boxes" card style: the box art stands free on the library background with a soft shadow,
/// using 3D pack art when an installed pack has this game and the ordinary cover otherwise. The 2D
/// cover is framed with a slight turn and a spine edge so it still reads as a box. No tilt tracking
/// and no per-frame work: the turn is a fixed transform.
struct LibraryBox3DCard<Options: View>: View {
    let game: GameMetadata
    let onTap: () -> Void
    let onFavoriteTap: () -> Void
    let options: Options
    @ObservedObject private var data = GameDataStore.shared

    var body: some View {
        let name = game.cardName
        let boxPath = ArtPackMatching.cachedBox3DPath(for: game, revision: data.revision)
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Button(action: onTap) {
                    ZStack {
                        if let boxPath {
                            CoverImage(path: boxPath)
                                .shadow(color: .black.opacity(0.35), radius: 8, x: 4, y: 6)
                        } else if let path = game.coverPath {
                            framed2D(path)
                        } else {
                            framedGlyph
                        }
                    }
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(name.name)")
                LibraryHeartButton(isFavorite: game.isFavorite, size: 30, action: onFavoriteTap)
                    .padding(.top, -4)
                    .padding(.trailing, -4)
            }
            .overlay(alignment: .topLeading) {
                LibraryOptionsButton(name: name.name, size: 30, options: options)
                    .padding(.top, -4)
                    .padding(.leading, -4)
            }
            Text(name.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(MuffinTheme.brownDarkest)
                .frame(maxWidth: .infinity)
            if let label = game.installLabel { LibraryInstallLine(text: label, size: 10, centered: true) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    /// No art at all: the controller glyph on the card gradient, framed and turned like the 2D cover.
    private var framedGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(MuffinTheme.muffinTopGradient)
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 36))
                .foregroundColor(MuffinTheme.onMuffinTop)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            LinearGradient(colors: [Color.black.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 10)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .rotation3DEffect(.degrees(-8), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .shadow(color: .black.opacity(0.35), radius: 8, x: 5, y: 6)
        .padding(8)
    }

    private func framed2D(_ path: String) -> some View {
        CoverImage(path: path)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                LinearGradient(colors: [Color.black.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .rotation3DEffect(.degrees(-8), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .shadow(color: .black.opacity(0.35), radius: 8, x: 5, y: 6)
            .padding(8)
    }
}
