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
    case moveControls
    case quit
    // case wiiUMenu   // see EXTENSION POINT above

    var id: String { rawValue }

    /// Whether the real Wii U Menu can be offered from here. Always false until the switch is built.
    static func canOfferWiiUMenu() -> Bool { false }

    /// The rows shown, in order.
    static var visible: [HomeMenuDestination] {
        // if canOfferWiiUMenu() { insert .wiiUMenu before .quit }
        allCases
    }

    var title: String {
        switch self {
        case .resume: return "Resume"
        case .saveStates: return "Save States"
        case .screenLayout: return "Screen layout"
        case .moveControls: return "Move controls"
        case .quit: return "Quit game"
        }
    }

    var symbol: String {
        switch self {
        case .resume: return "play.fill"
        case .saveStates: return "bookmark.fill"
        case .screenLayout: return "rectangle.split.2x1"
        case .moveControls: return "arrow.up.and.down.and.arrow.left.and.right"
        case .quit: return "xmark.circle"
        }
    }

    var hint: String {
        switch self {
        case .resume: return "Closes the menu and carries on with the game."
        case .saveStates: return "Opens the save state slots."
        case .screenLayout: return "Opens the screen layout choices."
        case .moveControls: return "Closes the menu and lets you drag the on-screen controls."
        case .quit: return "Asks before leaving the game."
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

/// What the menu asks the emulator view to do. The view owns the pause, the save-state sheet, edit
/// mode and the quit confirmation; the menu only asks.
struct HomeMenuActions {
    let resume: () -> Void
    let saveStates: () -> Void
    let moveControls: () -> Void
    let quit: () -> Void
    let swapScreens: () -> Void
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

    private enum Page { case root, layout }
    @State private var page = Page.root
    @State private var focus = 0
    /// The highlight is for controller players: shown from the start when one is connected, and once
    /// a controller button is used otherwise, so a touch player is not handed a row that looks chosen.
    @State private var usingController = ControllerPresence.isConnected()

    var body: some View {
        ZStack {
            scrim
            card
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

    private var card: some View {
        MuffinCard(cornerRadius: MuffinTheme.Radius.card) {
            VStack(spacing: 8) {
                header
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HomeMenuRowView(row: row, isFocused: usingController && index == focus)
                }
            }
            .padding(14)
        }
        .muffinElevation(.floating)
        .frame(maxWidth: 340)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(page == .root ? "HOME menu" : "Screen layout")
                .font(MuffinTheme.Font.sectionTitle)
                .foregroundColor(MuffinTheme.brownDarkest)
                .accessibilityAddTraits(.isHeader)
            if page == .root {
                Text(gameName)
                    .font(MuffinTheme.Font.caption)
                    .foregroundColor(MuffinTheme.brownMid)
                    .lineLimit(1)
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: Rows

    private var rows: [HomeMenuRow] {
        page == .root ? rootRows : layoutRows
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
        case .moveControls: return make(actions.moveControls)
        case .quit:
            // Dropped, not disabled, while a save is being written: quitting tears the title down under it.
            return canQuit ? make(destructive: true, actions.quit) : nil
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
            result.append(HomeMenuRow(id: "swap", title: "Swap TV and GamePad", symbol: "rectangle.2.swap",
                                      hint: "Switches which Wii U screen is shown.", action: actions.swapScreens))
        }
        result.append(HomeMenuRow(id: "back", title: "Back", symbol: "chevron.left",
                                  hint: "Returns to the HOME menu.", showsChevron: false, action: { show(.root) }))
        return result
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
        page = next
        // Coming back lands on the row that opened the page; going in lands on the layout in use.
        if next == .root {
            focus = HomeMenuDestination.visible.firstIndex(of: .screenLayout) ?? 0
        } else {
            focus = layoutRows.firstIndex(where: { $0.isSelected }) ?? 0
        }
    }

    private func goBack() {
        if page == .layout { show(.root) } else { actions.resume() }
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
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
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
