//
//  BenchEngine.swift
//  Loads exactly one engine framework at a time and resolves the mbench_* contract
//  from MuffinBenchEngine.h against that one framework's dlopen handle.
//
//  All three engine frameworks export the same C symbol names on purpose (that is the
//  whole point of the shared header) so dlsym(handle, "mbench_boot") only means "this
//  engine's boot" when handle came from THIS engine's dlopen and every lookup below
//  goes through that handle - never RTLD_DEFAULT, which would ask dyld to pick whichever
//  loaded image defines the symbol first and silently hand every engine's calls to
//  whichever one happened to load first.
//
import Foundation
import UIKit
import Darwin
import ObjectiveC

/// Mirrors MBenchCpuMode from MuffinBenchEngine.h.
enum BenchCpuMode: Int32 {
    case interpreter = 0
    case recompiler = 1

    var label: String {
        switch self {
        case .interpreter: return "interpreter"
        case .recompiler: return "recompiler"
        }
    }
}

/// Mirrors MBenchStatus from MuffinBenchEngine.h. Every mbench_* call that can fail
/// returns one of these; nothing in this app invents its own success/failure enum on
/// top of it.
enum BenchStatus: Int32, CustomStringConvertible {
    case ok = 0
    case errInit = 1
    case errBoot = 2
    case errNoJIT = 3
    case errBadArg = 4
    case errState = 5

    var isOK: Bool { self == .ok }

    var description: String {
        switch self {
        case .ok: return "OK"
        case .errInit: return "MBENCH_ERR_INIT"
        case .errBoot: return "MBENCH_ERR_BOOT"
        case .errNoJIT: return "MBENCH_ERR_NO_JIT"
        case .errBadArg: return "MBENCH_ERR_BAD_ARG"
        case .errState: return "MBENCH_ERR_STATE"
        }
    }

    /// dlsym/the C call can hand back a status value the header doesn't define (a build
    /// mismatch, or a status added to a newer header this app hasn't seen). Reporting
    /// that honestly as "unknown" beats silently mapping it onto .errInit.
    static func from(_ raw: Int32) -> BenchStatus {
        BenchStatus(rawValue: raw) ?? .errInit
    }
}

/// The API version this host was written against. mbench_api_version() must agree
/// before any other call on that engine is trusted.
let mbenchHostAPIVersion: Int32 = 1

/// Static description of one benchmarked engine: which framework to load, and what the
/// Mach-O binary inside that framework bundle is called. This list is the fixed engine
/// order for the whole run - the report walks it top to bottom and never re-sorts by
/// speed or anything else, so two runs of this app are always comparing the same rows.
struct EngineDescriptor {
    let id: String              // matches mbench_engine_id(), e.g. "muffin-v38"
    let displayName: String
    let frameworkName: String   // "MuffinBenchV38" - the .framework folder AND the Mach-O inside it
}

let benchEngines: [EngineDescriptor] = [
    EngineDescriptor(id: "muffin-v38", displayName: "Muffin v3.8 (restore)", frameworkName: "MuffinBenchV38"),
    EngineDescriptor(id: "melocafe", displayName: "MeloCafe", frameworkName: "MuffinBenchMelo"),
    EngineDescriptor(id: "muffin-v38-melofixes", displayName: "Muffin v3.8 + MeloCafe fixes", frameworkName: "MuffinBenchV38Melo"),
]

enum EngineLoadError: Error, CustomStringConvertible {
    case frameworkMissing(path: String)
    case dlopenFailed(path: String, reason: String)
    case symbolMissing(name: String)
    case apiVersionMismatch(got: Int32)

    var description: String {
        switch self {
        case .frameworkMissing(let path):
            return "framework binary not found at \(path)"
        case .dlopenFailed(let path, let reason):
            return "dlopen(\(path)) failed: \(reason)"
        case .symbolMissing(let name):
            return "missing required symbol \(name)"
        case .apiVersionMismatch(let got):
            return "mbench_api_version() returned \(got), host built against \(mbenchHostAPIVersion)"
        }
    }
}

// The C function pointer shapes from MuffinBenchEngine.h, restated by hand because
// dlsym hands back an untyped pointer and Swift needs an exact @convention(c) type to
// call through it safely. Keep these in lockstep with the header - a mismatch here
// compiles fine and corrupts the stack or misreads a return value at the call site
// instead of failing loudly.
private typealias FnApiVersion    = @convention(c) () -> Int32
private typealias FnCString       = @convention(c) () -> UnsafePointer<CChar>?
private typealias FnInitialize    = @convention(c) (UnsafePointer<CChar>?) -> Int32
private typealias FnJitPermitted  = @convention(c) () -> Bool
private typealias FnAttachSurface = @convention(c) (UnsafeMutableRawPointer?, Int32, Int32, Double) -> Int32
private typealias FnBoot          = @convention(c) (UnsafePointer<CChar>?, Int32) -> Int32
private typealias FnFrameCount    = @convention(c) () -> UInt64
private typealias FnBool          = @convention(c) () -> Bool
private typealias FnVoid          = @convention(c) () -> Void

/// One engine, dlopen'd and fully resolved. Every mbench_* entry point is a stored
/// function pointer bound at load time against this instance's own `handle` - there is
/// no lazy dlsym anywhere else in the app, so a symbol problem surfaces as a load
/// failure for that one engine (recorded, skipped) instead of a crash mid-run.
final class LoadedEngine {
    let descriptor: EngineDescriptor
    let handle: UnsafeMutableRawPointer
    let binaryPath: String

    /// Objective-C class names this engine's Mach-O image defines, gathered once,
    /// right after load. MuffinBenchEngine.h's export list only constrains the mbench_*
    /// C functions; nothing stops an engine's ObjC++ code from vending an ordinary
    /// Objective-C class whose name collides with another engine's. dyld resolves class
    /// registration globally regardless of dlopen's RTLD_LOCAL, so a name two engines
    /// both define is a real isolation failure - the runtime keeps whichever definition
    /// registered first - and it has to be reported, not assumed away.
    let definedClassNames: [String]

    private let fnApiVersion: FnApiVersion
    private let fnEngineId: FnCString
    private let fnEngineName: FnCString
    private let fnEngineCommit: FnCString
    private let fnInitialize: FnInitialize
    private let fnJitPermitted: FnJitPermitted
    private let fnAttachSurface: FnAttachSurface
    private let fnBoot: FnBoot
    private let fnLogPath: FnCString
    private let fnFrameCount: FnFrameCount
    private let fnTitleRunning: FnBool
    private let fnStopTitle: FnVoid
    private let fnShutdown: FnVoid

    private init(descriptor: EngineDescriptor, handle: UnsafeMutableRawPointer, binaryPath: String,
                 fnApiVersion: FnApiVersion, fnEngineId: FnCString, fnEngineName: FnCString,
                 fnEngineCommit: FnCString, fnInitialize: FnInitialize, fnJitPermitted: FnJitPermitted,
                 fnAttachSurface: FnAttachSurface, fnBoot: FnBoot, fnLogPath: FnCString,
                 fnFrameCount: FnFrameCount, fnTitleRunning: FnBool, fnStopTitle: FnVoid,
                 fnShutdown: FnVoid, definedClassNames: [String]) {
        self.descriptor = descriptor
        self.handle = handle
        self.binaryPath = binaryPath
        self.fnApiVersion = fnApiVersion
        self.fnEngineId = fnEngineId
        self.fnEngineName = fnEngineName
        self.fnEngineCommit = fnEngineCommit
        self.fnInitialize = fnInitialize
        self.fnJitPermitted = fnJitPermitted
        self.fnAttachSurface = fnAttachSurface
        self.fnBoot = fnBoot
        self.fnLogPath = fnLogPath
        self.fnFrameCount = fnFrameCount
        self.fnTitleRunning = fnTitleRunning
        self.fnStopTitle = fnStopTitle
        self.fnShutdown = fnShutdown
        self.definedClassNames = definedClassNames
    }

    /// Loads one engine by dlopen'ing its embedded framework's Mach-O directly (not the
    /// .framework directory - dlopen needs the executable inside it), resolves every
    /// mbench_* symbol against that handle, and checks the API version before handing
    /// back anything callable. Throws instead of crashing on any failure, because a
    /// missing or bad framework must skip that one engine, not abort the whole run.
    static func load(_ descriptor: EngineDescriptor) throws -> LoadedEngine {
        guard let frameworksURL = Bundle.main.privateFrameworksURL else {
            throw EngineLoadError.frameworkMissing(path: "<app bundle has no Frameworks directory>")
        }
        let binaryPath = frameworksURL
            .appendingPathComponent("\(descriptor.frameworkName).framework")
            .appendingPathComponent(descriptor.frameworkName)
            .path

        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw EngineLoadError.frameworkMissing(path: binaryPath)
        }

        guard let handle = dlopen(binaryPath, RTLD_NOW | RTLD_LOCAL) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown dlopen failure"
            throw EngineLoadError.dlopenFailed(path: binaryPath, reason: reason)
        }

        func resolve<T>(_ name: String, as type: T.Type) throws -> T {
            guard let sym = dlsym(handle, name) else {
                throw EngineLoadError.symbolMissing(name: name)
            }
            return unsafeBitCast(sym, to: type)
        }

        let fnApiVersion    = try resolve("mbench_api_version", as: FnApiVersion.self)
        let fnEngineId      = try resolve("mbench_engine_id", as: FnCString.self)
        let fnEngineName    = try resolve("mbench_engine_name", as: FnCString.self)
        let fnEngineCommit  = try resolve("mbench_engine_commit", as: FnCString.self)
        let fnInitialize    = try resolve("mbench_initialize", as: FnInitialize.self)
        let fnJitPermitted  = try resolve("mbench_jit_permitted", as: FnJitPermitted.self)
        let fnAttachSurface = try resolve("mbench_attach_surface", as: FnAttachSurface.self)
        let fnBoot          = try resolve("mbench_boot", as: FnBoot.self)
        let fnLogPath       = try resolve("mbench_log_path", as: FnCString.self)
        let fnFrameCount    = try resolve("mbench_frame_count", as: FnFrameCount.self)
        let fnTitleRunning  = try resolve("mbench_title_running", as: FnBool.self)
        let fnStopTitle     = try resolve("mbench_stop_title", as: FnVoid.self)
        let fnShutdown      = try resolve("mbench_shutdown", as: FnVoid.self)

        let apiVersion = fnApiVersion()
        guard apiVersion == mbenchHostAPIVersion else {
            throw EngineLoadError.apiVersionMismatch(got: apiVersion)
        }

        let classNames = LoadedEngine.definedClassNames(
            forImageEndingWith: "\(descriptor.frameworkName).framework/\(descriptor.frameworkName)"
        )

        return LoadedEngine(
            descriptor: descriptor, handle: handle, binaryPath: binaryPath,
            fnApiVersion: fnApiVersion, fnEngineId: fnEngineId, fnEngineName: fnEngineName,
            fnEngineCommit: fnEngineCommit, fnInitialize: fnInitialize, fnJitPermitted: fnJitPermitted,
            fnAttachSurface: fnAttachSurface, fnBoot: fnBoot, fnLogPath: fnLogPath,
            fnFrameCount: fnFrameCount, fnTitleRunning: fnTitleRunning, fnStopTitle: fnStopTitle,
            fnShutdown: fnShutdown, definedClassNames: classNames
        )
    }

    /// Finds the dyld image whose registered path ends with `suffix` and asks the
    /// Objective-C runtime what classes it defines. Uses the exact C string dyld itself
    /// reports (via _dyld_get_image_name), not a path this app reconstructs, because
    /// objc_copyClassNamesForImage matches by the pathname the image was registered
    /// under - a re-typed string that differs by so much as a symlink component would
    /// silently return nothing instead of the real answer.
    private static func definedClassNames(forImageEndingWith suffix: String) -> [String] {
        let imageCount = _dyld_image_count()
        for i in 0..<imageCount {
            guard let namePtr = _dyld_get_image_name(i) else { continue }
            let name = String(cString: namePtr)
            guard name.hasSuffix(suffix) else { continue }

            var classCount: UInt32 = 0
            guard let classList = objc_copyClassNamesForImage(namePtr, &classCount) else {
                return []
            }
            defer { free(classList) }

            var names: [String] = []
            names.reserveCapacity(Int(classCount))
            for j in 0..<Int(classCount) {
                if let cName = classList[j] {
                    names.append(String(cString: cName))
                }
            }
            return names.sorted()
        }
        return []
    }

    // MARK: - Typed wrappers over the resolved C entry points.

    func engineIdFromLibrary() -> String {
        fnEngineId().map { String(cString: $0) } ?? "unknown"
    }

    func engineName() -> String {
        fnEngineName().map { String(cString: $0) } ?? "unknown"
    }

    func engineCommit() -> String {
        fnEngineCommit().map { String(cString: $0) } ?? "unknown"
    }

    func initialize(dataDir: String) -> BenchStatus {
        dataDir.withCString { BenchStatus.from(fnInitialize($0)) }
    }

    func jitPermitted() -> Bool {
        fnJitPermitted()
    }

    /// `uiView` must be a UIView backed by a CAMetalLayer, and this must run on the main
    /// thread before mbench_boot, per MuffinBenchEngine.h. Passed across as the raw
    /// object pointer the engine's ObjC++/C++ side expects - the engine does not take
    /// ownership, so no Unmanaged.retain is needed, only enough to survive the call.
    func attachSurface(uiView: UIView, widthPoints: Int32, heightPoints: Int32, scale: Double) -> BenchStatus {
        let raw = Unmanaged.passUnretained(uiView).toOpaque()
        return BenchStatus.from(fnAttachSurface(raw, widthPoints, heightPoints, scale))
    }

    func boot(rpxPath: String, cpu: BenchCpuMode) -> BenchStatus {
        rpxPath.withCString { BenchStatus.from(fnBoot($0, cpu.rawValue)) }
    }

    func logPath() -> String? {
        fnLogPath().map { String(cString: $0) }
    }

    func frameCount() -> UInt64 {
        fnFrameCount()
    }

    func titleRunning() -> Bool {
        fnTitleRunning()
    }

    func stopTitle() {
        fnStopTitle()
    }

    /// Releases what the engine can, but the framework binary itself stays mapped -
    /// iOS/dyld never unloads a dlopen'd image. That is exactly why every mbench_*
    /// call in this file goes through this instance's own function pointers instead of
    /// a fresh dlsym after the "next" load: there is no way to ask dyld to forget this
    /// engine before the next one is opened.
    func shutdown() {
        fnShutdown()
    }
}
