import Foundation
import UniformTypeIdentifiers

/// Bringing a learned-shader or pipeline cache file into one game, from desktop Cemu or from
/// another MuffinEMU.
///
/// The engine reads the file (FileCache, in cemu_bridge_cache_file_import) and merges its entries into
/// the game's own cache file: entries the game already has stay as they are, and the file is never
/// replaced. This type only stages the picked file, asks the engine what it is, and turns the answer
/// into a sentence.
///
/// Which game a file is for comes from the version stamp inside it, not from its name. Which
/// renderer a pipeline cache is for can't be told from the contents, so that comes from the name
/// (`_vkpipeline` / `_mtlpipeline`), and the person is asked when the name doesn't say.
enum ShaderCacheImport {
    enum Kind {
        case shaders
        case pipeline

        var bridgeKind: Int32 {
            switch self {
            case .shaders: return Int32(CEMU_CACHE_FILE_SHADERS.rawValue)
            case .pipeline: return Int32(CEMU_CACHE_FILE_PIPELINE.rawValue)
            }
        }
    }

    struct Outcome {
        let message: String
        let failed: Bool
    }

    /// `.bin` is not a type iOS knows by name everywhere, so any file is allowed in the picker and the
    /// contents are what get checked.
    static var pickerTypes: [UTType] {
        [UTType(filenameExtension: "bin"), .data].compactMap { $0 }
    }

    /// The renderer the next launch uses, the same way the graphic packs screen reads it.
    static var selectedRenderer: RendererAPI {
        RendererAPI(rawValue: UserDefaults.standard.integer(forKey: RendererAPI.storageKey)) ?? RendererAPI.defaultValue
    }

    static func titleId(for game: GameMetadata) -> UInt64? {
        game.titleId ?? GameManager.deriveBaseTitleId(romPath: game.romPath)
    }

    /// true for a Vulkan pipeline cache name, false for a Metal one, nil when the name says neither.
    static func pipelineIsVulkan(fileName: String) -> Bool? {
        let lower = fileName.lowercased()
        if lower.contains("vkpipeline") { return true }
        if lower.contains("mtlpipeline") { return false }
        return nil
    }

    /// Copies the picked file into the app's temporary folder, so the engine reads a plain local file and
    /// whatever it does to the copy (dropping a damaged entry) never touches the original.
    static func stage(_ picked: URL) throws -> URL {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cache-import", isDirectory: true)
        // anything still here is left over from an import that was never finished
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let staged = folder.appendingPathComponent(UUID().uuidString + ".bin")
        try FileManager.default.copyItem(at: picked, to: staged)
        return staged
    }

    /// Reads and merges. Blocking and possibly slow for a large file: call it off the main thread.
    /// `pipelineIsVulkan` is only used for a pipeline cache and must be set for one.
    static func run(kind: Kind, game: GameMetadata, library: [GameMetadata], staged: URL, originalName: String,
                    pipelineIsVulkan: Bool?) -> Outcome {
        defer { try? FileManager.default.removeItem(at: staged) }
        guard let titleId = titleId(for: game) else {
            return Outcome(message: "Couldn't read this game's title ID, so there's no cache to put the file in.", failed: true)
        }
        if cemu_bridge_is_title_running() {
            return Outcome(message: "Close the game first, then import.", failed: true)
        }
        let gameName = game.displayTitle ?? game.title

        var info = CemuCacheFileInfo()
        staged.path.withCString { cemu_bridge_cache_file_inspect(titleId, $0, &info) }

        switch Int(info.status) {
        case Int(CEMU_CACHE_STATUS_NOT_A_CACHE.rawValue):
            return Outcome(message: "\"\(originalName)\" isn't a shader cache file, or it's damaged. Pick a .bin file from a Cemu or MuffinEMU shaderCache folder.", failed: true)
        case Int(CEMU_CACHE_STATUS_OTHER_GAME.rawValue):
            return Outcome(message: otherGameMessage(stamp: info.stamp, originalName: originalName, gameName: gameName, library: library), failed: true)
        case Int(CEMU_CACHE_STATUS_OLD_FORMAT.rawValue):
            return Outcome(message: "\"\(originalName)\" is a learned-shader cache from a desktop Cemu older than 1.16, which keyed shaders differently. It can't be converted. Use a cache from Cemu 1.16 or newer, or from MuffinEMU.", failed: true)
        case Int(CEMU_CACHE_STATUS_NOTHING_USABLE.rawValue):
            return Outcome(message: "\"\(originalName)\" is a cache for \(gameName), but none of its \(info.entryCount) entries can be used.", failed: true)
        default:
            break
        }

        // right file for this game, wrong button
        if Int32(info.kind) != kind.bridgeKind {
            return Outcome(message: kind == .shaders
                ? "\"\(originalName)\" is a pipeline cache, not learned shaders. Use \"Import shader pipeline caches\" for it."
                : "\"\(originalName)\" is a learned-shader cache, not a pipeline cache. Use \"Import learned shaders\" for it.", failed: true)
        }

        let renderer = selectedRenderer
        var added: Int32 = 0
        var already: Int32 = 0
        var skipped: Int32 = 0
        let result = staged.path.withCString {
            cemu_bridge_cache_file_import(titleId, $0, kind.bridgeKind, Int32(renderer.rawValue), pipelineIsVulkan ?? false,
                                          &added, &already, &skipped)
        }
        switch Int(result) {
        case Int(CEMU_CACHE_STATUS_OK.rawValue):
            break
        case Int(CEMU_CACHE_STATUS_TITLE_RUNNING.rawValue):
            return Outcome(message: "Close the game first, then import.", failed: true)
        case -2:
            return Outcome(message: "This game's own cache file was saved by a different version of the cache format, so nothing was changed. Clear this game's shaders in its options, then import again.", failed: true)
        case -1:
            return Outcome(message: "This game's own cache file couldn't be opened or created, so nothing was changed. If storage is full, free some up and try again.", failed: true)
        default:
            return Outcome(message: "Couldn't import \"\(originalName)\" (code \(result)). Nothing was changed.", failed: true)
        }

        return Outcome(message: successMessage(kind: kind, added: Int(added), already: Int(already), skipped: Int(skipped),
                                               renderer: renderer, pipelineIsVulkan: pipelineIsVulkan),
                       failed: false)
    }

    // MARK: Messages

    private static func otherGameMessage(stamp: UInt32, originalName: String, gameName: String, library: [GameMetadata]) -> String {
        // The stamp is derived from the title ID, so trying it against each game in the library names the owner.
        for other in library {
            guard let otherId = titleId(for: other), cemu_bridge_cache_stamp_kind(otherId, stamp) != 0 else { continue }
            let otherName = other.displayTitle ?? other.title
            if otherName != gameName {
                return "\"\(originalName)\" is a cache for \(otherName), not \(gameName). Nothing was imported."
            }
        }
        // Not in the library: the title ID is usually the start of the file name.
        let digits = originalName.prefix(16)
        if digits.count == 16, digits.allSatisfy({ $0.isHexDigit }) {
            return "\"\(originalName)\" is a cache for another game (title ID \(digits.uppercased())), not \(gameName). Nothing was imported."
        }
        return "\"\(originalName)\" is a cache for a different game, not \(gameName). Nothing was imported."
    }

    private static func successMessage(kind: Kind, added: Int, already: Int, skipped: Int,
                                       renderer: RendererAPI, pipelineIsVulkan: Bool?) -> String {
        let noun = kind == .shaders ? "shader" : "pipeline"
        let plural = { (n: Int) in "\(n) \(noun)\(n == 1 ? "" : "s")" }
        var parts: [String] = []
        if added == 0 && skipped == 0 {
            parts.append("Nothing new: this game already had all \(plural(already)) in that file.")
        } else if added == 0 {
            parts.append("Nothing was added.")
        } else {
            var line = "Added \(plural(added))"
            if already > 0 { line += " (\(already) already there)" }
            parts.append(line + ".")
        }
        if skipped > 0 {
            parts.append("\(skipped) \(skipped == 1 ? "entry was" : "entries were") left out: damaged, not in a usable format, or there wasn't room on this device. If storage is low, free some up and import the file again; entries already added are kept.")
        }
        parts.append("The file you picked wasn't changed.")
        switch kind {
        case .shaders:
            parts.append("Added to the \(renderer == .vulkan ? "Vulkan" : "Metal") shader file. Shaders from desktop Cemu are converted the first time you start the game, which is a normal shader load; after that they load as fast as the game's own.")
        case .pipeline:
            let fileIsVulkan = pipelineIsVulkan ?? false
            let fileRenderer: RendererAPI = fileIsVulkan ? .vulkan : .metal
            if fileRenderer != renderer {
                parts.append("This is a \(fileIsVulkan ? "Vulkan" : "Metal") pipeline cache and the renderer is set to \(renderer == .vulkan ? "Vulkan" : "Metal"), so it won't be used until you switch in Settings > Graphics. It's saved under its own name and will be picked up then.")
            } else {
                parts.append("It's used the next time you start the game.")
            }
            parts.append("A pipeline only loads when the shaders it uses are in the game's learned shaders, so import those too.")
        }
        return parts.joined(separator: " ")
    }
}
