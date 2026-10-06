import Foundation
#if canImport(Metal)
import Metal
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - A pack as the list shows it

/// One graphic pack, parsed from a `muffin_gp_list()` record (see IOSGraphicPackBridge.h).
struct GraphicPack: Identifiable, Hashable {
    /// The core's normalized path for the pack's rules.txt. Stable across rescans.
    let path: String
    let name: String
    let virtualPath: String
    var enabled: Bool
    let defaultEnabled: Bool
    let universal: Bool
    let version: Int
    let titleIds: Set<String>
    let rendererFilter: String
    let vendorFilter: String
    let hasGLSLShaders: Bool
    let hasMetalShaders: Bool
    let hasGLSLOutputShaders: Bool
    let presetCount: Int
    let brief: String

    var id: String { path }

    /// Packs a player added from Files live apart from the community download.
    var isImported: Bool { path.contains("/imported/") }

    /// "Game/Category/Pack" -> the game, or "All games" for packs that aren't tied to one.
    var game: String {
        let parts = virtualPath.split(separator: "/").map(String.init)
        if universal && parts.count < 2 { return GraphicPack.allGames }
        return parts.count >= 2 ? parts[0] : GraphicPack.otherGame
    }

    /// One of Graphics, Enhancements, Mods, Workarounds, or the pack's own folder name.
    var category: String {
        let parts = virtualPath.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return "Other" }
        return GraphicPack.normalizedCategory(parts[1])
    }

    /// The name to show inside a game's category section: a pack whose name is just its
    /// own path ("Game/Mods/Thing") is shown as "Thing".
    var displayName: String {
        if name == virtualPath {
            let parts = virtualPath.split(separator: "/").map(String.init)
            if parts.count >= 3 { return parts[2...].joined(separator: " / ") }
            if let last = parts.last { return last }
        }
        return name
    }

    static let allGames = "All games"
    static let otherGame = "Other"

    /// Display order of categories inside a game.
    static let categoryOrder = ["Graphics", "Enhancements", "Mods", "Workarounds"]

    static func normalizedCategory(_ raw: String) -> String {
        switch raw.lowercased() {
        case "graphics", "graphic", "resolution", "resolutions": return "Graphics"
        case "enhancements", "enhancement": return "Enhancements"
        case "mods", "mod", "cheats", "cheat": return "Mods"
        case "workarounds", "workaround", "fixes", "!override", "override": return "Workarounds"
        default:
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "!"))
            return trimmed.isEmpty ? "Other" : trimmed
        }
    }

    static func categoryRank(_ category: String) -> Int {
        categoryOrder.firstIndex(of: category) ?? categoryOrder.count
    }

    func appliesTo(titleId: UInt64?) -> Bool {
        if universal { return true }
        guard let titleId else { return false }
        return titleIds.contains(String(format: "%016llx", titleId))
    }

    // MARK: Parsing

    /// Records separated by 0x1E, fields by 0x1F. Records with the wrong shape are dropped.
    static func parseList(_ raw: String) -> [GraphicPack] {
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: "\u{1E}", omittingEmptySubsequences: true).compactMap { record in
            let f = record.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 15, !f[0].isEmpty else { return nil }
            return GraphicPack(
                path: f[0],
                name: f[1],
                virtualPath: f[2],
                enabled: f[3] == "1",
                defaultEnabled: f[4] == "1",
                universal: f[5] == "1",
                version: Int(f[6]) ?? 0,
                titleIds: Set(f[7].split(separator: ",").map { $0.lowercased() }),
                rendererFilter: f[8],
                vendorFilter: f[9],
                hasGLSLShaders: f[10] == "1",
                hasMetalShaders: f[11] == "1",
                hasGLSLOutputShaders: f[12] == "1",
                presetCount: Int(f[13]) ?? 0,
                brief: f[14]
            )
        }
    }

    // MARK: Renderer support

    /// How well a pack can be expected to work with one renderer. The core silently skips
    /// shader replacements written for the other API, so this says so up front.
    enum Support: Equatable {
        case full
        /// Activates, but part of what it does is skipped.
        case partial(String)
        /// The core won't activate it with this renderer at all.
        case inactive(String)

        var isFull: Bool { if case .full = self { return true } else { return false } }
    }

    func support(on api: RendererAPI) -> Support {
        if !vendorFilter.isEmpty && vendorFilter != "apple" {
            return .inactive("Made for a different kind of graphics chip, so it never turns on here.")
        }
        switch rendererFilter {
        case "metal" where api != .metal:
            return .inactive("Only works with the Metal renderer. Switch the renderer in Settings > Graphics.")
        case "vulkan" where api != .vulkan:
            return .inactive("Only works with the Vulkan renderer. Switch the renderer in Settings > Graphics.")
        case "opengl":
            return .inactive("Made for OpenGL, which MuffinEMU doesn't use.")
        default:
            break
        }
        switch api {
        case .metal:
            if hasGLSLShaders && !hasMetalShaders {
                return .partial("Replaces shaders that are written for OpenGL and Vulkan. Metal can't use them, so those changes are skipped and the picture can look wrong. The pack's other changes still apply.")
            }
            if hasGLSLOutputShaders && !hasMetalShaders {
                return .partial("Adds an output or scaling shader written for OpenGL and Vulkan. Metal can't use it, so that part is skipped.")
            }
            return .full
        case .vulkan:
            if hasMetalShaders && !hasGLSLShaders {
                return .partial("Its shaders are written for Metal only, so the Vulkan renderer skips them.")
            }
            if hasGLSLShaders && version <= 3 {
                return .partial("Its shaders predate Vulkan support, so the Vulkan renderer skips them.")
            }
            return .full
        }
    }

    // MARK: Hints

    /// Packs that raise the cost of drawing a frame: Graphics packs hold the resolution, shadow
    /// and anti-aliasing options.
    var canCostSpeed: Bool { category == "Graphics" }

    /// Frame-rate patches ask for more frames than the game normally makes.
    var raisesFrameRate: Bool {
        let n = (name + " " + virtualPath).lowercased()
        return n.contains("fps") || n.contains("frame rate") || n.contains("framerate")
    }

    /// Fixes for known glitches. They change behaviour, not how much is drawn.
    var isWorkaround: Bool { category == "Workarounds" }
}

// MARK: - Presets

struct GraphicPackPreset: Hashable {
    let category: String
    let name: String
    let active: Bool
    let visible: Bool
    let isDefault: Bool

    /// The picture height a preset name asks for ("1920x1080", "1080p"), or nil for presets that
    /// aren't a resolution.
    var height: Int? { GraphicPackPreset.height(fromName: name) }

    static func height(fromName name: String) -> Int? {
        let ns = name as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let re = try? NSRegularExpression(pattern: #"(\d{3,4})\s*[xX×]\s*(\d{3,4})"#),
           let m = re.firstMatch(in: name, range: full),
           let a = Int(ns.substring(with: m.range(at: 1))), let b = Int(ns.substring(with: m.range(at: 2))) {
            let h = min(a, b)
            return (360...4320).contains(h) ? h : nil
        }
        if let re = try? NSRegularExpression(pattern: #"(?<![\d])(\d{3,4})\s*[pP](?![a-zA-Z])"#),
           let m = re.firstMatch(in: name, range: full),
           let h = Int(ns.substring(with: m.range(at: 1))) {
            return (360...4320).contains(h) ? h : nil
        }
        return nil
    }
}

struct GraphicPackDetails {
    var description: String
    var presets: [GraphicPackPreset]

    /// Preset categories in the order the pack declares them.
    var categories: [String] {
        var seen = Set<String>()
        var order: [String] = []
        for p in presets where !seen.contains(p.category) {
            seen.insert(p.category)
            order.append(p.category)
        }
        return order
    }

    func presets(in category: String) -> [GraphicPackPreset] { presets.filter { $0.category == category } }

    /// Only a category with at least two choices is worth a picker.
    func visiblePresets(in category: String) -> [GraphicPackPreset] {
        presets(in: category).filter(\.visible)
    }

    /// A category is a resolution choice when at least two of its presets name a picture height.
    func isResolutionCategory(_ category: String) -> Bool {
        presets(in: category).filter { $0.height != nil }.count >= 2
    }

    /// 0x1D between the description and the preset records; 0x1E between records, 0x1F between fields.
    static func parse(_ raw: String) -> GraphicPackDetails {
        let halves = raw.split(separator: "\u{1D}", maxSplits: 1, omittingEmptySubsequences: false)
        let description = halves.first.map(String.init) ?? ""
        var presets: [GraphicPackPreset] = []
        if halves.count > 1 {
            for record in halves[1].split(separator: "\u{1E}", omittingEmptySubsequences: true) {
                let f = record.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
                guard f.count >= 5 else { continue }
                presets.append(GraphicPackPreset(category: f[0], name: f[1], active: f[2] == "1",
                                                 visible: f[3] == "1", isDefault: f[4] == "1"))
            }
        }
        return GraphicPackDetails(description: description, presets: presets)
    }
}

// MARK: - What this device can reasonably be asked to draw

/// Suggests how high a resolution preset is worth trying on the device the app is running on.
///
/// Nothing here measures speed, and nothing is ever applied automatically: it is a starting point
/// drawn from the GPU family, the memory, the screen and the power mode, so a small iPhone, a base
/// iPad and an M-series iPad Pro each get their own answer. Every device is scored by the same rule.
struct GraphicPackDeviceProfile: Equatable {
    /// 1 (Apple GPU family 5 or older) ... 5 (family 9 or newer).
    var gpuFamily: Int
    var memoryGB: Double
    /// The shorter side of the screen in pixels.
    var screenShortSidePixels: Int
    var lowPowerMode: Bool
    var isPad: Bool

    static let steps = [720, 1080, 1440, 2160]

    /// GPU family and memory each add to one score.
    var score: Int {
        let memory: Int
        switch memoryGB {
        case ..<3.5: memory = 0
        case ..<5: memory = 1
        case ..<7: memory = 2
        case ..<11: memory = 3
        default: memory = 4
        }
        return gpuFamily + memory
    }

    /// The tallest picture (in lines) that is worth trying: never beyond what the screen can show,
    /// never below the Wii U's own 720, and one step lower in Low Power Mode.
    var suggestedMaxHeight: Int {
        var index: Int
        switch score {
        case ..<4: index = 0
        case 4...5: index = 1
        default: index = 2
        }
        let screenCap = GraphicPackDeviceProfile.steps.lastIndex { $0 <= max(720, screenShortSidePixels) } ?? 0
        index = min(index, screenCap)
        if lowPowerMode { index = max(0, index - 1) }
        return GraphicPackDeviceProfile.steps[index]
    }

    var summary: String {
        let tall = suggestedMaxHeight
        let label = tall == 720 ? "the Wii U's own 720p" : "\(tall)p"
        var text = "For this \(isPad ? "iPad" : "iPhone") we suggest staying at \(label) or lower."
        if lowPowerMode { text += " Low Power Mode is on, so the suggestion is one step lower." }
        text += " This comes from the graphics chip, memory and screen, not a speed test, so treat it as a starting point."
        return text
    }

    /// What never changes while the app runs, read once.
    private static let hardware: (family: Int, gigabytes: Double, short: Int, pad: Bool) = {
        var family = 1
        #if canImport(Metal)
        if let device = MTLCreateSystemDefaultDevice() {
            if #available(iOS 17.0, macOS 14.0, *), device.supportsFamily(.apple9) {
                family = 5
            } else if #available(iOS 16.0, macOS 13.0, *), device.supportsFamily(.apple8) {
                family = 4
            } else if device.supportsFamily(.apple7) {
                family = 3
            } else if device.supportsFamily(.apple6) {
                family = 2
            }
        }
        #endif
        let gigabytes = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        #if canImport(UIKit) && !os(tvOS)
        let bounds = UIScreen.main.nativeBounds
        return (family, gigabytes, Int(min(bounds.width, bounds.height)), UIDevice.current.userInterfaceIdiom == .pad)
        #else
        return (family, gigabytes, 1440, true)
        #endif
    }()

    /// This device. Low Power Mode is read fresh, because it can change while the app is open.
    static var current: GraphicPackDeviceProfile {
        GraphicPackDeviceProfile(gpuFamily: hardware.family, memoryGB: hardware.gigabytes,
                                 screenShortSidePixels: hardware.short,
                                 lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, isPad: hardware.pad)
    }

    /// The resolution preset to suggest among `choices`: the tallest at or under the suggested
    /// height, or the lowest one when they are all above it.
    func suggestedPreset(in choices: [GraphicPackPreset]) -> GraphicPackPreset? {
        let withHeight = choices.compactMap { p in p.height.map { (p, $0) } }
        guard !withHeight.isEmpty else { return nil }
        let within = withHeight.filter { $0.1 <= suggestedMaxHeight }
        if let best = within.max(by: { $0.1 < $1.1 }) { return best.0 }
        return withHeight.min(by: { $0.1 < $1.1 })?.0
    }
}

// MARK: - Storage

enum GraphicPackStorage {
    /// Bytes the player's device can still give the app, counting space iOS will clear on demand.
    static func freeBytes() -> Int64? {
        let url = GraphicPackPaths.documents
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
            return important
        }
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let plain = values.volumeAvailableCapacity {
            return Int64(plain)
        }
        return nil
    }

    static func describe(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Throws a readable error when `needed` bytes (plus a margin) aren't free. An unreadable free
    /// space figure doesn't block anything: the write itself will fail and say so.
    static func require(_ needed: Int64, what: String) throws {
        let margin: Int64 = 20 * 1024 * 1024
        guard let free = freeBytes() else { return }
        if free < needed + margin {
            throw StorageError.notEnough(needed: needed + margin, free: free, what: what)
        }
    }

    enum StorageError: LocalizedError {
        case notEnough(needed: Int64, free: Int64, what: String)

        var errorDescription: String? {
            switch self {
            case .notEnough(let needed, let free, let what):
                return "Not enough free storage to \(what). It needs about \(GraphicPackStorage.describe(needed)) and this device has \(GraphicPackStorage.describe(free)) free. Free some space and try again."
            }
        }
    }
}
