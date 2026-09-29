import SwiftUI

@main
struct CemuApp: App {
    // Theme tokens are plain statics, so views do not redraw on their own.
    // Keying the tree to the current theme id rebuilds it when the theme changes.
    @ObservedObject private var themeStore = MuffinThemeStore.shared

    init() {
        // Earliest Swift-side checkpoint; if it is missing from the crash log, the
        // crash happened in native static initialisation.
        cemu_bridge_log_checkpoint("CemuApp.init() reached")

        // Create the folders players drop keys and games into, so Files lists
        // Documents on a fresh install. Idempotent.
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            for folder in ["keys", "Roms"] {
                try? FileManager.default.createDirectory(
                    at: documents.appendingPathComponent(folder),
                    withIntermediateDirectories: true
                )
            }
        }


        // Push the saved VSync setting before the renderer creates its layer, so the
        // toggle takes effect on the first launch after changing it.
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
