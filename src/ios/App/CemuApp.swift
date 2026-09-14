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
