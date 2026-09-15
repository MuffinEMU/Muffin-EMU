import SwiftUI

@main
struct CemuApp: App {
    // MuffinTheme's tokens are plain static vars, not @Published properties any view's
    // body reads through a property wrapper - the usual SwiftUI mechanism that makes a
    // view redraw when its data changes doesn't apply to them. Observing the store
    // once here and keying the whole tree to its current theme's id does the same job
    // a different way: picking a new theme changes .id(), SwiftUI treats that as a new
    // view identity, and the entire hierarchy underneath is torn down and rebuilt -
    // reading every MuffinTheme.* call site fresh. A full rebuild is the right cost for
    // "the user just changed the theme," not a concern the way it would be per-frame.
    @ObservedObject private var themeStore = MuffinThemeStore.shared

    init() {
        // Earliest Swift-reachable point. If Documents/CemuCrashLog.txt never even
        // gets this line, the crash is happening before Swift's own App.init() runs -
        // i.e. in a C++ global static initializer (see CemuBridge.mm's
        // cemu_bridge_install_early_crash_handler, a high-priority constructor that
        // installs its own log/signal handler even earlier than this).
        cemu_bridge_log_checkpoint("CemuApp.init() reached")

        // A genuinely fresh install (SideStore/AltStore/TrollStore - anything that
        // gives the app its own real container, unlike LiveContainer's own shared
        // sandbox) has a completely empty Documents/ until something writes to it, and
        // every writer in this app (WiiUKeys, GameManager's mlc setup, the Roms
        // importer) only creates its folder lazily, the first time it's actually used.
        // UIFileSharingEnabled/LSSupportsOpeningDocumentsInPlace are both already set
        // (Info-AlternateIcons.plist - confirmed present in a real built IPA via
        // PlistBuddy), but neither one makes Files show an app's "On My iPad" folder
        // for a container whose Documents/ has never held a single file - which is
        // exactly the state a fresh real install is in, and exactly why "drop your
        // keys/ROMs in via Files" was unusable before ever launching a game once:
        // there was nothing yet to make Files list the folder to drop them into.
        // Creating the two folders someone needs to reach before they've done
        // anything else in the app - not `mlc`, which is created lazily right before
        // it is actually needed and never has anything for a user to manually place
        // in it - closes that gap on every launch, idempotently.
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            for folder in ["keys", "Roms"] {
                try? FileManager.default.createDirectory(
                    at: documents.appendingPathComponent(folder),
                    withIntermediateDirectories: true
                )
            }
        }


        // Same class of bug, same cure. MetalRenderer's InitializeLayer() applies this to
        // the CAMetalLayer (MetalRenderer.cpp:382) on the path GameManager reaches at
        // :626, while the only push lived at GameManager:676 - fifty lines and a thread
        // hop too late, so the layer was always configured from the C++ default and the
        // VSync toggle did nothing on the launch you changed it.
        cemu_bridge_set_vsync_enabled(
            UserDefaults.standard.object(forKey: "muffin.render.vsync") as? Bool ?? true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(themeStore.current.id)
                .onAppear {
                    cemu_bridge_log_checkpoint("ContentView.onAppear reached")
                    #if os(iOS)
                    // Arm display detection at launch, not when a game starts, so a TV
                    // that is already connected is known about before the first surface
                    // is registered - and so the log records the display situation even
                    // for a session where nothing is ever booted.
                    DisplayRouter.shared.startObserving()
                    #endif
                }
        }
    }
}
