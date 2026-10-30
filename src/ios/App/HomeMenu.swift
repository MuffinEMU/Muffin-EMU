// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI
import Combine

// The in-game HOME menu: HOME pauses the game and opens a compact menu over it (Resume, Save
// States, Screen layout, Move controls, Quit game).
//
// The core's GamePad mapping has no HOME bit, so HOME used to do nothing on every pad. It is
// now intercepted on the Swift side, before it can reach the bridge, and every source ends up
// in HomeMenuRouter:
//   - MuffinEMU's pad and the preview pad: ContentView's sendPadButton("HOME").
//   - TouchLab's pads: CemuBridgePadOutput.setButton(.home) in TouchLabPads.swift.
//   - Melo-Controller: MeloControllerBridge.send, its "guide" button.
//   - A physical controller: GCExtendedGamepad.buttonHome, seen only inside the bridge
//     (CemuBridge.mm), which reports it through cemu_bridge_set_menu_input_callback.
// ContentView owns the open and close (it owns the pause plumbing); this file is the menu itself.

// MARK: - Destinations

/// What a row of the HOME menu does. A switch over this enum has no `default`, so adding a case
/// is a compile error everywhere a row has to be built or handled.
///
/// EXTENSION POINT: the real Wii U Menu. Not built; the case below stays commented out until it
/// is. The intended behaviour: when the Wii U Menu title is installed (WiiUMenu.status().menuInstalled,
/// WiiUMenu.swift), HOME also offers "Wii U Menu", as the console's HOME button does. Choosing it
/// switches the running session to the Menu title through the title-switch machinery the Menu
/// already uses to hand over to a game in the other direction (IOSBridge_TitleSwitching and
/// cemu_bridge_set_title_switch_callback in CemuBridge.h; TitleSwitchSettings in GameManager.swift
/// applies the per-game settings on a switch), after asking whether to save first, since leaving
/// the game ends this session's save states. Until then `canOfferWiiUMenu()` is false.
enum HomeMenuDestination: String, CaseIterable, Identifiable {
    case resume
    case saveStates
    case screenLayout
    case externalDisplay
    case moveControls
    case recordAudio
    case recordScreen
    case scanAmiibo
    case consoleClock
    case recentreAim
    case quit
    // case wiiUMenu   // see EXTENSION POINT above

    var id: String { rawValue }

    /// Whether the real Wii U Menu can be offered from here. Always false until the switch is built.
    static func canOfferWiiUMenu() -> Bool { false }

    /// The rows shown, in order.
    static var visible: [HomeMenuDestination] {
        // if canOfferWiiUMenu() { insert .wiiUMenu before .quit }
        // Recentre aim only means something while motion aiming is on (Settings > Motion & Aiming).
        let motionOn = UserDefaults.standard.object(forKey: MotionSettings.enabledKey) as? Bool
            ?? MotionSettings.defaultEnabled
        return allCases.filter { $0 != .recentreAim || motionOn }
    }

    var title: String {
        switch self {
        case .resume: return "Resume".localized
        case .saveStates: return "Save States".localized
        case .screenLayout: return "Screen layout".localized
        case .externalDisplay: return "External display".localized
        case .moveControls: return "Move controls".localized
        case .recordAudio: return "Record audio".localized
        case .recordScreen: return "Record screen".localized
        case .scanAmiibo: return "Scan amiibo".localized
        case .consoleClock: return "Console clock".localized
        case .recentreAim: return "Recentre aim".localized
        case .quit: return "Quit game".localized
        }
    }

    var symbol: String {
        switch self {
        case .resume: return "play.fill"
        case .saveStates: return "bookmark.fill"
        case .screenLayout: return "rectangle.split.2x1"
        case .externalDisplay: return "tv"
        case .moveControls: return "arrow.up.and.down.and.arrow.left.and.right"
        case .recordAudio: return "record.circle"
        case .recordScreen: return "video.circle"
        case .scanAmiibo: return "wave.3.right"
        case .consoleClock: return "clock.arrow.circlepath"
        case .recentreAim: return "scope"
        case .quit: return "xmark.circle"
        }
    }

    var hint: String {
        switch self {
        case .resume: return "Closes the menu and carries on with the game.".localized
        case .saveStates: return "Opens the save state slots.".localized
        case .screenLayout: return "Opens the screen layout choices.".localized
        case .externalDisplay: return "Opens the external display settings, the same ones as in Settings > External Display.".localized
        case .moveControls: return "Closes the menu and lets you drag the on-screen controls.".localized
        case .recordAudio: return "Records the game's sound to an M4A file in the Recordings folder in Files. Choose it again to stop.".localized
        case .recordScreen: return "Records the screen the game is showing, at the game's own resolution and with its sound, to a video in the Recordings folder in Files. Choose it again to stop.".localized
        case .scanAmiibo: return "Opens a list of amiibo files to scan. The game has to be asking for an amiibo.".localized
        case .consoleClock: return "Moves the game's date and time forward.".localized
        case .recentreAim: return "Takes the way you are holding the device now as straight ahead, then goes back to the game.".localized
        case .quit: return "Asks before leaving the game.".localized
        }
    }
}

// MARK: - Input

enum HomeMenuEvent {
    case homeButton
    case up
    case down
    case confirm
    case back
}

/// Where every HOME press ends up, whatever it came from, and the menu navigation a physical
/// controller sends while the menu has it.
///
/// Not main-actor isolated, so a pad's input callback can call it from wherever it runs. Events are
/// posted to the main queue and never delivered inside the caller: the pad callbacks run in the
/// middle of a touch, and opening the menu changes state the pad is drawn from.
final class HomeMenuRouter {
    static let shared = HomeMenuRouter()

    let events = PassthroughSubject<HomeMenuEvent, Never>()

    /// A pad's HOME button. Only the press counts: HOME is a "go to the menu" button, not a held one.
    func padHome(pressed: Bool) {
        if pressed { post(.homeButton) }
    }

    func post(_ event: HomeMenuEvent) {
        DispatchQueue.main.async { self.events.send(event) }
    }

    /// Starts listening to the physical controller (see CemuBridge.h). Safe to call again.
    func connectToBridge() {
        cemu_bridge_set_menu_input_callback { event in
            if event == CEMU_BRIDGE_MENU_HOME {
                HomeMenuRouter.shared.post(.homeButton)
            } else if event == CEMU_BRIDGE_MENU_UP {
                HomeMenuRouter.shared.post(.up)
            } else if event == CEMU_BRIDGE_MENU_DOWN {
                HomeMenuRouter.shared.post(.down)
            } else if event == CEMU_BRIDGE_MENU_CONFIRM {
                HomeMenuRouter.shared.post(.confirm)
            } else if event == CEMU_BRIDGE_MENU_BACK {
                HomeMenuRouter.shared.post(.back)
            }
        }
    }
}

/// Wires the router into the emulator view in one modifier, so the view's own body does not grow
/// another stack of them: delivers events, connects the bridge, and hands the physical
/// controller to the menu for exactly as long as it is open.
struct HomeMenuEventsModifier: ViewModifier {
    let isOpen: Bool
    let onEvent: (HomeMenuEvent) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { HomeMenuRouter.shared.connectToBridge() }
            .onReceive(HomeMenuRouter.shared.events) { onEvent($0) }
            .onChange(of: isOpen) { open in cemu_bridge_set_menu_capture(open) }
            .onDisappear { cemu_bridge_set_menu_capture(false) }
    }
}

// MARK: - Menu

/// What the menu asks the emulator view to do. The view owns the pause, the save-state sheet and edit
/// mode; the menu only asks. `quit` is the confirmed quit: the menu asks "Quit game?" itself, on a page,
/// so a controller can answer it.
struct HomeMenuActions {
    let resume: () -> Void
    let saveStates: () -> Void
    let moveControls: () -> Void
    let quit: () -> Void
    let swapScreens: () -> Void
    let toggleRecording: () -> Void
    let toggleScreenRecording: () -> Void
    let scanAmiibo: () -> Void
}

private struct HomeMenuRow: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var hint: String = ""
    var isSelected = false
    var isPrimary = false
    var isDestructive = false
    var showsChevron = false
    let action: () -> Void
}

/// Height of the rows inside the card, so the card can cap it and let the rows scroll on a short screen.
private struct HomeRowsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The menu: a dimmed layer over the game and a compact card. Touch works as usual. With a
/// controller, up and down move a highlight, A chooses and B goes back (or resumes, from the
/// first page); HOME is handled by the emulator view, which closes the menu.
struct HomeMenuOverlay: View {
    let gameName: String
    /// False while a sheet or the quit confirmation is over the menu, so a controller press is not
    /// also a press on a row underneath it.
    let isActive: Bool
    @Binding var screenLayout: ScreenLayout
    let isDualScreen: Bool
    let canQuit: Bool
    let actions: HomeMenuActions

    private enum Page { case root, layout, external, confirmQuit, clock, clockCustom }
    @ObservedObject private var recorder = AudioRecorder.shared
    @ObservedObject private var screenRecorder = ScreenRecorder.shared
    @State private var page = Page.root
    @State private var focus = 0
    @State private var rowsHeight: CGFloat = 280
    /// The console clock as of the last jump, and what that jump did, for the clock page's header.
    @State private var clockNow = ConsoleClock.now
    @State private var clockResult: String?
    /// The custom jump, kept while the menu is open so a second jump can reuse it.
    @State private var customDays = 1
    @State private var customHours = 0
    /// The highlight is for controller players: shown from the start when one is connected, and once
    /// a controller button is used otherwise, so a touch player is not handed a row that looks chosen.
    @State private var usingController = ControllerPresence.isConnected()

    // The same settings as Settings > External Display, so a change in either place shows in the other.
    @AppStorage(ExternalDisplaySystemSettings.enabledKey)
    private var externalDisplayEnabled = ExternalDisplaySystemSettings.defaultEnabled
    @AppStorage(DisplayLayoutSettings.swapKey)
    private var externalSwap = DisplayLayoutSettings.defaultSwap
    @AppStorage(DisplayLayoutSettings.deviceShowsKey)
    private var deviceShows = DisplayLayoutSettings.defaultDeviceShows
    @AppStorage(DisplayLayoutSettings.showSwapButtonKey)
    private var showExternalSwapButton = DisplayLayoutSettings.defaultShowSwapButton

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                scrim
                card(availableHeight: proxy.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { goBack() }
        .onReceive(HomeMenuRouter.shared.events) { handle($0) }
        .onAppear { UIAccessibility.post(notification: .screenChanged, argument: nil) }
    }

    private var scrim: some View {
        MuffinTheme.scrim
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { actions.resume() }
            .accessibilityHidden(true)
    }

    private func card(availableHeight: CGFloat) -> some View {
        MuffinCard(cornerRadius: MuffinTheme.Radius.card) {
            VStack(spacing: 8) {
                header
                // Scrolls when the card is taller than the screen (an iPhone in landscape), and follows the
                // controller's highlight.
                ScrollViewReader { reader in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                HomeMenuRowView(row: row, isFocused: usingController && index == focus)
                                    .id(row.id)
                            }
                        }
                        // Room for the focus ring, which is drawn just outside the row.
                        .padding(4)
                        .background(
                            GeometryReader { inner in
                                Color.clear.preference(key: HomeRowsHeightKey.self, value: inner.size.height)
                            }
                        )
                    }
                    .frame(height: rowsHeight > 0 ? min(rowsHeight, max(96, availableHeight - 130)) : nil)
                    .onPreferenceChange(HomeRowsHeightKey.self) { rowsHeight = $0 }
                    .onChange(of: focus) { _ in
                        let current = rows
                        if current.indices.contains(focus) {
                            withAnimation(.easeInOut(duration: 0.15)) { reader.scrollTo(current[focus].id) }
                        }
                    }
                }
            }
            .padding(14)
        }
        .muffinElevation(.floating)
        .frame(maxWidth: 340)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var headerTitle: String {
        switch page {
        case .root: return "HOME menu".localized
        case .layout: return "Screen layout".localized
        case .external: return "External display".localized
        case .confirmQuit: return "Quit game?".localized
        case .clock: return "Console clock".localized
        case .clockCustom: return "Custom amount".localized
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(headerTitle)
                .font(MuffinTheme.Font.sectionTitle)
                .foregroundColor(MuffinTheme.brownDarkest)
                .accessibilityAddTraits(.isHeader)
            switch page {
            case .root:
                Text(gameName)
                    .font(MuffinTheme.Font.caption)
                    .foregroundColor(MuffinTheme.brownMid)
                    .lineLimit(1)
            case .confirmQuit:
                Text("Save states can't be loaded after you quit. Use the game's own save.")
                    .font(MuffinTheme.Font.caption)
                    .foregroundColor(MuffinTheme.brownMid)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            case .layout:
                EmptyView()
            case .clock:
                Text(ConsoleClockFormat.string(clockNow))
                    .font(MuffinTheme.Font.caption)
                    .foregroundColor(MuffinTheme.brownMid)
                if let result = clockResult {
                    Text(result)
                        .font(MuffinTheme.Font.caption)
                        .foregroundColor(MuffinTheme.brownMid)
                }
            case .clockCustom:
                Text(customSeconds > 0 ? ConsoleClockFormat.duration(days: customDays, hours: customHours)
                                        : "Add at least an hour.".localized)
                    .font(MuffinTheme.Font.caption)
                    .foregroundColor(MuffinTheme.brownMid)
            case .external:
                Text(externalDisplayEnabled
                     ? "Changes apply right away. AirPlay mirroring doesn't count as an external display.".localized
                     : "Experimental. Turn it on, then connect a second screen.".localized)
                    .font(MuffinTheme.Font.caption)
                    .foregroundColor(MuffinTheme.brownMid)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: Rows

    private var rows: [HomeMenuRow] {
        switch page {
        case .root: return rootRows
        case .layout: return layoutRows
        case .external: return externalRows
        case .confirmQuit: return confirmQuitRows
        case .clock: return clockRows
        case .clockCustom: return clockCustomRows
        }
    }

    /// "Keep playing" is the first row, so it is the one highlighted: a stray A press does not quit.
    private var confirmQuitRows: [HomeMenuRow] {
        [
            HomeMenuRow(id: "keep", title: "Keep playing".localized, symbol: "play.fill",
                        hint: "Goes back to the HOME menu without quitting.".localized, isPrimary: true, action: { show(.root) }),
            HomeMenuRow(id: "quitNow", title: "Quit game".localized, symbol: "xmark.circle",
                        hint: "Leaves the game now.".localized, isDestructive: true, action: actions.quit)
        ]
    }

    private var rootRows: [HomeMenuRow] {
        HomeMenuDestination.visible.compactMap { rootRow(for: $0) }
    }

    private func rootRow(for destination: HomeMenuDestination) -> HomeMenuRow? {
        func make(primary: Bool = false, chevron: Bool = false, destructive: Bool = false,
                  _ action: @escaping () -> Void) -> HomeMenuRow {
            HomeMenuRow(id: destination.id, title: destination.title, symbol: destination.symbol,
                        hint: destination.hint, isPrimary: primary, isDestructive: destructive,
                        showsChevron: chevron, action: action)
        }
        switch destination {
        case .resume: return make(primary: true, actions.resume)
        case .saveStates: return make(actions.saveStates)
        case .screenLayout: return make(chevron: true, { show(.layout) })
        case .externalDisplay: return make(chevron: true, { show(.external) })
        case .moveControls: return make(actions.moveControls)
        case .recordAudio:
            // Stays open, so the checkmark shows it took; Resume carries on with the game.
            var row = make(actions.toggleRecording)
            row.isSelected = recorder.isRecording
            return row
        case .recordScreen:
            var row = make(actions.toggleScreenRecording)
            row.isSelected = screenRecorder.isRecording
            return row
        case .scanAmiibo: return make(actions.scanAmiibo)
        case .consoleClock:
            return make(chevron: true, {
                clockNow = ConsoleClock.now
                clockResult = nil
                show(.clock)
            })
        case .recentreAim:
            // Same call as Settings > Motion & Aiming > Recentre aim. The pose at the tap is the new
            // straight ahead, so the player is already holding the device the way they play.
            return make {
                cemu_bridge_motion_recenter()
                actions.resume()
            }
        case .quit:
            // Dropped, not disabled, while a save is being written: quitting tears the title down under it.
            return canQuit ? make(destructive: true, { show(.confirmQuit) }) : nil
        }
    }

    private var layoutRows: [HomeMenuRow] {
        var result: [HomeMenuRow] = []
        // The layouts apply to this device's own screen; with an external display connected the
        // TV is on that display and only the swap means anything.
        if !isDualScreen {
            for layout in ScreenLayout.allCases {
                result.append(HomeMenuRow(id: layout.rawValue, title: layout.string, symbol: Self.symbol(for: layout),
                                          hint: layout.description, isSelected: screenLayout == layout,
                                          action: { screenLayout = layout }))
            }
        }
        if isDualScreen || screenLayout == .singleScreen {
            result.append(HomeMenuRow(id: "swap", title: "Swap TV and GamePad".localized, symbol: "rectangle.2.swap",
                                      hint: "Switches which Wii U screen is shown.".localized, action: actions.swapScreens))
        }
        result.append(HomeMenuRow(id: "back", title: "Back".localized, symbol: "chevron.left",
                                  hint: "Returns to the HOME menu.".localized, showsChevron: false, action: { show(.root) }))
        return result
    }

    /// Settings > External Display's rows, as menu rows: switches show a checkmark when on, and
    /// "This device shows" is one row per choice. Each change re-routes at once, as it does in Settings.
    private var externalRows: [HomeMenuRow] {
        var result: [HomeMenuRow] = [
            HomeMenuRow(id: "externalOn", title: "Use an external display".localized, symbol: "tv",
                        hint: "Experimental. Sends a Wii U screen to a connected second display.".localized,
                        isSelected: externalDisplayEnabled, action: {
                            externalDisplayEnabled.toggle()
                            DisplayRouter.shared.reapplyForExternalDisplaySystemToggle()
                        })
        ]
        if externalDisplayEnabled {
            result.append(HomeMenuRow(id: "externalSwap", title: "GamePad on the external display".localized, symbol: "rectangle.2.swap",
                                      hint: externalSwap
                                        ? "On: the external display shows the GamePad screen.".localized
                                        : "Off: the external display shows the TV screen.".localized,
                                      isSelected: externalSwap, action: {
                                          externalSwap.toggle()
                                          DisplayRouter.shared.rerouteForScreenLayoutChange()
                                      }))
            for mode in DeviceScreenMode.allCases {
                result.append(HomeMenuRow(id: "deviceShows." + mode.rawValue, title: Self.deviceShowsTitle(for: mode),
                                          symbol: Self.symbol(for: mode),
                                          hint: "What this device shows (\"here\") while the external display is connected.".localized,
                                          isSelected: deviceShows == mode, action: {
                                              deviceShows = mode
                                              DisplayRouter.shared.rerouteForScreenLayoutChange()
                                          }))
            }
            result.append(HomeMenuRow(id: "externalSwapButton", title: "Show swap button".localized, symbol: "hand.tap",
                                      hint: "A small button over the game while an external display is connected.".localized,
                                      isSelected: showExternalSwapButton, action: { showExternalSwapButton.toggle() }))
        }
        result.append(HomeMenuRow(id: "back", title: "Back".localized, symbol: "chevron.left",
                                  hint: "Returns to the HOME menu.".localized, showsChevron: false, action: { show(.root) }))
        return result
    }

    /// The preset jumps, then the custom one. The menu stays open after a jump, so the new time shows
    /// in the header and another press moves it again.
    private var clockRows: [HomeMenuRow] {
        var result = ConsoleClockStep.allCases.map { step in
            HomeMenuRow(id: "clock.\(step.rawValue)", title: step.title, symbol: "forward.fill",
                        hint: "Moves the game's clock forward. Some games only check the date when they start.".localized,
                        action: { jumpClock(by: step.rawValue) })
        }
        result.append(HomeMenuRow(id: "clock.custom", title: "Custom amount".localized, symbol: "slider.horizontal.3",
                                  hint: "Choose a number of days and hours.".localized, showsChevron: true,
                                  action: { show(.clockCustom) }))
        result.append(HomeMenuRow(id: "back", title: "Back".localized, symbol: "chevron.left",
                                  hint: "Returns to the HOME menu.".localized, showsChevron: false, action: { show(.root) }))
        return result
    }

    private var customSeconds: Int { customDays * 86_400 + customHours * 3_600 }

    /// Buttons rather than a picker, so a controller can set the amount too.
    private var clockCustomRows: [HomeMenuRow] {
        [
            HomeMenuRow(id: "custom.dayUp", title: "Add a day".localized, symbol: "plus.circle",
                        hint: "Up to 365 days.".localized, action: { customDays = min(customDays + 1, 365) }),
            HomeMenuRow(id: "custom.dayDown", title: "Remove a day".localized, symbol: "minus.circle",
                        hint: "Down to none.".localized, action: { customDays = max(customDays - 1, 0) }),
            HomeMenuRow(id: "custom.hourUp", title: "Add an hour".localized, symbol: "plus.circle",
                        hint: "Up to 23 hours.".localized, action: { customHours = min(customHours + 1, 23) }),
            HomeMenuRow(id: "custom.hourDown", title: "Remove an hour".localized, symbol: "minus.circle",
                        hint: "Down to none.".localized, action: { customHours = max(customHours - 1, 0) }),
            HomeMenuRow(id: "custom.go",
                        title: customSeconds > 0
                            ? String(format: "Move forward by %@".localized, ConsoleClockFormat.duration(days: customDays, hours: customHours))
                            : "Move forward".localized,
                        symbol: "forward.fill",
                        hint: "Moves the game's clock forward by this amount, then shows the new time.".localized,
                        isPrimary: true, action: {
                            guard customSeconds > 0 else { return }
                            jumpClock(by: customSeconds)
                            show(.clock)
                        }),
            HomeMenuRow(id: "back", title: "Back".localized, symbol: "chevron.left",
                        hint: "Returns to the console clock.".localized, showsChevron: false, action: { show(.clock) })
        ]
    }

    private func jumpClock(by seconds: Int) {
        clockResult = ConsoleClock.advance(by: seconds)
            ? "Moved forward.".localized
            : "Couldn't move the clock.".localized
        clockNow = ConsoleClock.now
    }

    /// Shorter than DeviceScreenMode.string, which is written to follow a label in Settings; menu rows are one line.
    private static func deviceShowsTitle(for mode: DeviceScreenMode) -> String {
        switch mode {
        case .otherScreen: return "Here: the other screen".localized
        case .sameScreen: return "Here: the same screen".localized
        case .nothing: return "Here: controls only".localized
        }
    }

    private static func symbol(for mode: DeviceScreenMode) -> String {
        switch mode {
        case .otherScreen: return "rectangle.on.rectangle"
        case .sameScreen: return "rectangle.fill.on.rectangle.fill"
        case .nothing: return "gamecontroller"
        }
    }

    private static func symbol(for layout: ScreenLayout) -> String {
        switch layout {
        case .singleScreen: return "rectangle"
        case .bothScreens: return "rectangle.split.1x2"
        case .smallGamePadTopRight: return "rectangle.inset.topright.filled"
        }
    }

    // MARK: Navigation

    private func show(_ next: Page) {
        let previous = page
        page = next
        // Coming back lands on the row that opened the page; going in lands on the layout in use, or on
        // "Keep playing" when asked to confirm a quit.
        switch next {
        case .root:
            let opener: HomeMenuDestination
            switch previous {
            case .confirmQuit: opener = .quit
            case .external: opener = .externalDisplay
            case .clock, .clockCustom: opener = .consoleClock
            default: opener = .screenLayout
            }
            focus = HomeMenuDestination.visible.firstIndex(of: opener) ?? 0
        case .layout:
            focus = layoutRows.firstIndex(where: { $0.isSelected }) ?? 0
        case .external:
            focus = 0
        case .confirmQuit:
            focus = 0
        case .clock:
            focus = previous == .clockCustom ? (clockRows.firstIndex(where: { $0.id == "clock.custom" }) ?? 0) : 0
        case .clockCustom:
            focus = 0
        }
    }

    private func goBack() {
        switch page {
        case .root: actions.resume()
        case .clockCustom: show(.clock)
        default: show(.root)
        }
    }

    private func handle(_ event: HomeMenuEvent) {
        guard isActive else { return }
        let count = rows.count
        switch event {
        case .up:
            usingController = true
            focus = (min(focus, count - 1) + count - 1) % count
        case .down:
            usingController = true
            focus = (min(focus, count - 1) + 1) % count
        case .confirm:
            usingController = true
            let current = rows
            if current.indices.contains(focus) { current[focus].action() }
        case .back:
            goBack()
        case .homeButton:
            break
        }
    }
}

private struct HomeMenuRowView: View {
    let row: HomeMenuRow
    let isFocused: Bool

    var body: some View {
        styledButton
            .overlay(focusRing)
            .accessibilityLabel(row.title)
            .accessibilityHint(row.hint)
            .accessibilityAddTraits(row.isSelected ? .isSelected : [])
    }

    @ViewBuilder private var styledButton: some View {
        if row.isPrimary {
            Button(action: row.action) { label }
                .buttonStyle(MuffinPrimaryButtonStyle())
        } else {
            Button(action: row.action) { label }
                .buttonStyle(MuffinSecondaryButtonStyle())
        }
    }

    private var label: some View {
        HStack(spacing: 10) {
            Image(systemName: row.symbol)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(row.title)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing
        }
        // 22 plus the button style's 8 points above and below: a 44 point row.
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .foregroundColor(row.isDestructive ? MuffinTheme.alertText : nil)
    }

    @ViewBuilder private var trailing: some View {
        if row.isSelected {
            Image(systemName: "checkmark")
                .accessibilityHidden(true)
        } else if row.showsChevron {
            Image(systemName: "chevron.right")
                .accessibilityHidden(true)
        }
    }

    private var focusRing: some View {
        RoundedRectangle(cornerRadius: MuffinTheme.Radius.chip + 2, style: .continuous)
            .strokeBorder(MuffinTheme.pixelBlue, lineWidth: 3)
            .padding(-2)
            .opacity(isFocused ? 1 : 0)
            .allowsHitTesting(false)
    }
}
