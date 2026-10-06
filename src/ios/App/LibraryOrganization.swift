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

    static let storageKey = "muffin.library.cardStyle"
    static let defaultValue: LibraryCardStyle = .standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Cards"
        case .largeCovers: return "Large covers"
        case .compact: return "Compact grid"
        case .list: return "List"
        }
    }

    var detail: String {
        switch self {
        case .standard: return "Cover, name and a Play button"
        case .largeCovers: return "Bigger covers, tap a cover to play"
        case .compact: return "Many small covers on screen at once"
        case .list: return "One game per row, with details"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: return "square.grid.2x2"
        case .largeCovers: return "square.grid.2x2.fill"
        case .compact: return "square.grid.3x3"
        case .list: return "list.bullet"
        }
    }

    /// Column layout for this style. Adaptive, so an iPhone in portrait gets fewer columns than
    /// an iPad or a phone turned sideways without any size-class checks.
    var columns: [GridItem] {
        switch self {
        case .standard: return [GridItem(.adaptive(minimum: 140), spacing: 16)]
        case .largeCovers: return [GridItem(.adaptive(minimum: 220), spacing: 18)]
        case .compact: return [GridItem(.adaptive(minimum: 96), spacing: 12)]
        case .list: return [GridItem(.adaptive(minimum: 340), spacing: 12)]
        }
    }

    var rowSpacing: CGFloat {
        switch self {
        case .standard: return 20
        case .largeCovers: return 22
        case .compact: return 14
        case .list: return 10
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
        case .favorites: return "Favorites and the rest"
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
        case .favorites: return "Favorites only"
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
                LibrarySection(id: "favorites", title: "Favorites", games: favs),
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
/// nothing on disk is renamed and the title ID is untouched. Keyed by the game's settings key
/// (title ID, falling back to the file name), so it follows the game through a re-import.
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
        _text = State(initialValue: LibraryCustomNames.shared.name(for: game.settingsKey) ?? game.cardName.name)
    }

    private var originalTitle: String { game.displayTitle ?? game.title }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Name", text: $text)
                        .autocapitalization(.words)
                } footer: {
                    Text("Only changes how the game is named in your library. Original title: \(originalTitle)")
                }
                if LibraryCustomNames.shared.name(for: game.settingsKey) != nil {
                    Section {
                        Button("Reset to Original Title") {
                            LibraryCustomNames.shared.set(nil, for: game.settingsKey)
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
                        LibraryCustomNames.shared.set(same ? nil : text, for: game.settingsKey)
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: style.columns, spacing: style.rowSpacing, pinnedViews: [.sectionHeaders]) {
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
            if let path = game.coverPath, let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
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
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
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
    /// The per-game menu behind the "..." button (the same one a long-press opens).
    let options: Options

    init(game: GameMetadata, style: LibraryCardStyle, onTap: @escaping () -> Void,
         onFavoriteTap: @escaping () -> Void, @ViewBuilder options: () -> Options) {
        self.game = game
        self.style = style
        self.onTap = onTap
        self.onFavoriteTap = onFavoriteTap
        self.options = options()
    }

    var body: some View {
        switch style {
        case .standard:
            GameCardOptimized(game: game, onTap: onTap, onFavoriteTap: onFavoriteTap, options: { options })
        case .largeCovers:
            LibraryLargeCoverCard(game: game, onTap: onTap, onFavoriteTap: onFavoriteTap, options: options)
        case .compact:
            LibraryCompactCard(game: game, onTap: onTap, onFavoriteTap: onFavoriteTap, options: options)
        case .list:
            LibraryListRow(game: game, onTap: onTap, onFavoriteTap: onFavoriteTap, options: options)
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
                .accessibilityLabel(game.isFavorite ? "Remove from favorites" : "Add to favorites")
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
