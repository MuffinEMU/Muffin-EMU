import SwiftUI

@main
struct CemuApp: App {
    init() {
        // Earliest Swift-reachable point. If Documents/CemuCrashLog.txt never even
        // gets this line, the crash is happening before Swift's own App.init() runs -
        // i.e. in a C++ global static initializer (see CemuBridge.mm's
        // cemu_bridge_install_early_crash_handler, a high-priority constructor that
        // installs its own log/signal handler even earlier than this).
        cemu_bridge_log_checkpoint("CemuApp.init() reached")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    cemu_bridge_log_checkpoint("ContentView.onAppear reached")
                }
        }
    }
}
