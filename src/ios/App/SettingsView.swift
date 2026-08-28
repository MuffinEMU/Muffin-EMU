import SwiftUI
import UniformTypeIdentifiers

private extension Bundle {
    var appVersionString: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

struct SettingsView: View {
    @ObservedObject var gameManager: GameManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingIconPicker = false
    @State private var showingKeysImporter = false
    @State private var showingKeysRemovalConfirmation = false
    @State private var keyCount = WiiUKeys.installedKeyCount()
    @State private var keysErrorMessage: String?
    /// Shared with EmulatorViewOptimized by key, not by binding - the emulator view is
    /// not in this sheet's hierarchy, and AppStorage is what makes the setting outlive
    /// the sheet anyway.
    @AppStorage(LaunchLogSettings.showKey) private var showLaunchLog = false
    /// Read by DisplayRouter through `RenderScale.current` at surface-registration time,
    /// not observed by it - hence AppStorage here and a plain UserDefaults read there.
    @AppStorage(RenderScale.storageKey) private var renderScaleRaw = RenderScale.balanced.rawValue

    private var renderScale: RenderScale {
        RenderScale(rawValue: renderScaleRaw) ?? .balanced
    }

    /// Defaulted from `TimebaseScale.current` rather than from a fixed case, because the
    /// engine picks this one itself at launch from the CPU mode it actually got (real
    /// time under the recompiler, an eighth under the interpreter). A hardcoded default
    /// here would show a value that is not the one in effect, on the single screen whose
    /// job is to say what is in effect.
    @AppStorage(TimebaseScale.storageKey) private var timebaseRaw = TimebaseScale.current.rawValue

    private var timebase: TimebaseScale {
        TimebaseScale(rawValue: timebaseRaw) ?? .realTime
    }

    var body: some View {
        // NavigationStack needs iOS 16+; this project's deployment target is 15.0.
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient
                    .ignoresSafeArea()

                Form {
                    Section("Appearance") {
                        Button(action: { showingIconPicker = true }) {
                            Label("App Icon", systemImage: "app.badge")
                        }
                        .foregroundColor(MuffinTheme.brownDarkest)
                    }

                    // The two things that decide how fast this runs, in the order they
                    // matter. CPU mode first because it is worth more than everything
                    // else combined and it is not a setting - it is decided by HOW the
                    // app was launched, which is exactly why it needs saying here.
                    Section {
                        CPUModeRow()

                        Picker("Resolution", selection: $renderScaleRaw) {
                            ForEach(RenderScale.allCases) { scale in
                                Text(scale.title).tag(scale.rawValue)
                            }
                        }
                        .foregroundColor(MuffinTheme.brownDarkest)
                    } header: {
                        Text("Performance")
                    } footer: {
                        // Says "next launch" because it is true: the scale is baked into
                        // the surface at registration, and a running title's swapchain is
                        // not rebuilt underneath it.
                        Text("\(renderScale.summary)\n\nResolution changes the size of the picture Muffin draws, not the resolution the game runs at - nothing about the emulation changes with it. Takes effect the next time you launch a game.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    // Its own section rather than a third row under Performance, because
                    // it is not a performance setting and calling it one would be the
                    // wrong idea to give: it makes nothing faster. It is the setting that
                    // decides whether a game that is already running slowly can advance
                    // at all, which is a different question and the one that has actually
                    // been blocking this port.
                    Section {
                        Picker("Speed", selection: $timebaseRaw) {
                            ForEach(TimebaseScale.allCases) { scale in
                                Text(scale.title).tag(scale.rawValue)
                            }
                        }
                        .foregroundColor(MuffinTheme.brownDarkest)
                        // Applied immediately, unlike Resolution: the shift is read per
                        // call inside PPCTimer, so changing it mid-title is safe and the
                        // guest's clock still only ever moves forward. Someone watching a
                        // game sit on one frame can walk down this list and see which
                        // value frees it, without relaunching between each try.
                        .onChange(of: timebaseRaw) { raw in
                            guard let scale = TimebaseScale(rawValue: raw) else { return }
                            TimebaseScale.apply(scale)
                        }
                    } header: {
                        Text("Emulated clock")
                    } footer: {
                        Text("\(timebase.summary)\n\nUntil you pick a value here, Muffin finds one itself: if a game has not reached its graphics handover after twelve seconds it steps its own clock down a notch, as far as 1/64, and the log says which value freed it. Choosing anything on this list stops that search for good and keeps your choice.\n\nThis changes how fast the game believes time is passing, not how fast Muffin runs. Without the recompiler the emulated CPU is far slower than the console's, while the game's own clock keeps up with real time - so every deadline it sets itself is already overdue, and it can spend all its time on overdue work and never draw. Slowing its clock puts those deadlines back in reach. Nothing about the emulation is made less accurate by it, and it takes effect straight away.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    // Off by default: the log is a diagnostic, not a feature, and a
                    // wall of monospaced text over the boot is not what someone who
                    // just wants to play a game should meet. Collection is always on
                    // regardless (see IOSLiveLog.h) - gating that too would mean the
                    // toggle could only ever show the boot AFTER the one that failed.
                    Section {
                        Toggle(isOn: $showLaunchLog) {
                            Label("Show launch log", systemImage: "text.alignleft")
                        }
                        .tint(MuffinTheme.pixelBlue)
                    } header: {
                        Text("Diagnostics")
                    } footer: {
                        Text("Shows what the emulator is doing, with timestamps, while a game boots. Useful when a game starts but the screen stays black.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    // Real Wii U games are encrypted and Muffin ships no keys. This is
                    // where the user supplies their own, dumped from their own console.
                    // Optional by design: without it, everything that worked before -
                    // homebrew, .rpx, anything already decrypted - still works.
                    Section {
                        Button(action: { showingKeysImporter = true }) {
                            Label(WiiUKeys.keysFileExists() ? "Replace keys.txt" : "Import keys.txt",
                                  systemImage: "key")
                        }
                        .foregroundColor(MuffinTheme.brownDarkest)

                        if WiiUKeys.keysFileExists() {
                            SettingsRow(label: "Keys loaded", value: "\(keyCount)")
                            Button(role: .destructive, action: { showingKeysRemovalConfirmation = true }) {
                                Label("Remove keys.txt", systemImage: "trash")
                            }
                        }
                    } header: {
                        Text("Wii U keys")
                    } footer: {
                        Text("Optional. Encrypted games (.wux, .wud, .iso, .wua) need the AES keys dumped from your own Wii U, in a plain text file called keys.txt - one key per line. Muffin ships no keys and can't obtain them. Homebrew and already-decrypted dumps need none of this.\n\nYou can also skip this button entirely: open Muffin in the Files app and drop keys.txt straight into the \"keys\" folder. It's picked up on the next launch, no restart needed.")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    Section("Library") {
                        SettingsRow(label: "Games", value: "\(gameManager.games.count)")
                        SettingsRow(label: "Favorites", value: "\(gameManager.favorites.count)")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    Section("About") {
                        SettingsRow(label: "Version", value: Bundle.main.appVersionString)
                        Link(destination: URL(string: "https://github.com/bward-dev1/cemu-ios-muffin")!) {
                            Label("View on GitHub", systemImage: "arrow.up.right.square")
                        }
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView()
            }
            // .item for the same reason the ROM picker uses it: a keys.txt exported by
            // some other tool may carry no useful type at all, and a type filter would
            // grey out the one file this button exists to select. WiiUKeys.importKeys
            // decides what it actually is, by reading it.
            .fileImporter(
                isPresented: $showingKeysImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleKeysImport(result)
            }
            .alert("Couldn't import keys", isPresented: .constant(keysErrorMessage != nil), presenting: keysErrorMessage) { _ in
                Button("OK") { keysErrorMessage = nil }
            } message: { message in
                Text(message)
            }
            .alert("Remove keys.txt?", isPresented: $showingKeysRemovalConfirmation) {
                Button("Remove", role: .destructive) {
                    try? WiiUKeys.removeKeys()
                    keyCount = WiiUKeys.installedKeyCount()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Encrypted games won't run until you import a keys.txt again. Homebrew is unaffected.")
            }
        }
        .navigationViewStyle(.stack)
    }

    private func handleKeysImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                keyCount = try WiiUKeys.importKeys(from: url)
            } catch {
                keysErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            keysErrorMessage = error.localizedDescription
        }
    }
}

/// Reports whether this launch got the PPC recompiler or the interpreter, and why.
///
/// This exists because the answer was previously only obtainable by pulling
/// CemuCrashLog.txt off the device and reading a cs_flags hex value out of it - an absurd
/// thing to ask of someone whose actual question is "did launching through StikJIT do
/// anything". The bridge decides this once at engine init, so a plain `let` read in
/// `init` is correct; there is no path that changes it while this sheet is open.
private struct CPUModeRow: View {
    private let mode = cemu_bridge_cpu_mode()
    private let detail = String(cString: cemu_bridge_cpu_mode_detail())

    private var title: String {
        switch mode {
        case 2:  return "Recompiler (JIT)"
        case 1:  return "Interpreter (3 cores)"
        default: return "Not decided yet"
        }
    }

    private var tint: Color {
        // Amber rather than red for the interpreter: it is slow, but it is a working,
        // correct emulator, and it is the state every launch has been in so far. Red
        // would be claiming something is broken when nothing is.
        switch mode {
        case 2:  return MuffinTheme.pixelBlue
        case 1:  return .orange
        default: return MuffinTheme.brownMid
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CPU")
                Spacer()
                Text(title)
                    .foregroundColor(tint)
            }
            Text(detail)
                .font(.footnote)
                .foregroundColor(MuffinTheme.brownMid)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// LabeledContent needs iOS 16+; this project's deployment target is 15.0.
private struct SettingsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(MuffinTheme.brownMid)
        }
    }
}
