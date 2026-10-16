// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI
import UIKit

/// The game's software keyboard and error viewer, drawn natively.
///
/// The core would draw both with ImGui inside the game's render surface, which has a reduced
/// backing scale and no usable touch or text input. While this view is active it asks the core
/// to publish them instead (cemu_bridge_set_native_dialogs), shows a card with the system
/// keyboard or the dialog's own buttons, and sends the answer back through the same states the
/// ImGui version set. Inactive means the core's own drawing, unchanged.

// MARK: - Model

private enum NativeDialogRequest: Equatable {
    case keyboard(id: UInt64, maxLength: Int, multiline: Bool, text: String, hint: String)
    case error(id: UInt64, title: String, message: String, buttons: [String])

    /// Parses cemu_bridge_native_dialog_request(): fields separated by 0x1F, empty for none.
    static func read() -> NativeDialogRequest? {
        let raw = String(cString: cemu_bridge_native_dialog_request())
        if raw.isEmpty { return nil }
        let f = raw.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 2, let id = UInt64(f[1]) else { return nil }
        switch f[0] {
        case "K" where f.count >= 6:
            return .keyboard(id: id, maxLength: Int(f[2]) ?? 0, multiline: f[3] == "1", text: f[4], hint: f[5])
        case "E" where f.count >= 7:
            var buttons = [f[5]]
            if f[2] == "2" { buttons.append(f[6]) }
            return .error(id: id, title: f[3], message: f[4], buttons: buttons)
        default:
            return nil
        }
    }
}

/// Cuts to `maxLength` UTF-16 units, the unit the core counts in, without splitting a pair.
private func clampedUTF16(_ text: String, _ maxLength: Int) -> String {
    guard maxLength > 0, text.utf16.count > maxLength else { return maxLength > 0 ? text : "" }
    var result = ""
    var count = 0
    for ch in text {
        let n = String(ch).utf16.count
        if count + n > maxLength { break }
        result.append(ch)
        count += n
    }
    return result
}

// MARK: - Cards

private struct DialogCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .muffinGlassBackground(in: RoundedRectangle(cornerRadius: 28, style: .continuous)) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(MuffinGlass.isActive ? 0 : 0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(MuffinGlass.isActive ? 0.2 : 0.35), radius: 18, y: 6)
            .frame(maxWidth: 520)
            .padding(.horizontal, 16)
    }
}

private struct DialogButtonStyle: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: prominent ? .semibold : .regular))
            .foregroundColor(prominent ? .white : (MuffinGlass.isActive ? Color.primary : .accentColor))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .muffinGlassBackground(in: Capsule(), tint: prominent ? Color.accentColor : nil, interactive: true) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color.accentColor.opacity(0.14))
            }
            .opacity(MuffinGlass.isActive ? 1 : (configuration.isPressed ? 0.7 : 1))
    }
}

private struct KeyboardCard: View {
    let id: UInt64
    let maxLength: Int
    let multiline: Bool
    let hint: String
    @State private var text: String
    @FocusState private var focused: Bool

    init(id: UInt64, maxLength: Int, multiline: Bool, text: String, hint: String) {
        self.id = id
        self.maxLength = maxLength
        self.multiline = multiline
        self.hint = hint
        _text = State(initialValue: clampedUTF16(text, maxLength))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter text")
                .font(.system(size: 15, weight: .semibold))
            field
            HStack(spacing: 10) {
                Button("Cancel") { send(2) }
                    .buttonStyle(DialogButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                okButton
            }
        }
        .modifier(DialogCardBackground())
        .onChange(of: text) { value in
            let clamped = clampedUTF16(value, maxLength)
            if clamped != value { text = clamped; return }
            cemu_bridge_native_keyboard_answer(id, clamped, 0)
        }
        .onAppear {
            // After the card is on screen, so the keyboard doesn't race the presentation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
    }

    @ViewBuilder
    private var okButton: some View {
        if multiline {
            // Return inserts a line break here, so the hardware shortcut is Command-Return.
            Button("OK") { send(1) }
                .buttonStyle(DialogButtonStyle(prominent: true))
                .keyboardShortcut(.return, modifiers: .command)
        } else {
            Button("OK") { send(1) }
                .buttonStyle(DialogButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var field: some View {
        if multiline {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .focused($focused)
                    .frame(minHeight: 60, maxHeight: 110)
                    .autocapitalization(.sentences)
                if text.isEmpty && !hint.isEmpty {
                    Text(hint)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.systemBackground)))
        } else {
            TextField(hint, text: $text)
                .focused($focused)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit { send(1) }
                .disableAutocorrection(true)
        }
    }

    private func send(_ answer: Int32) {
        cemu_bridge_native_keyboard_answer(id, clampedUTF16(text, maxLength), answer)
    }
}

private struct ErrorCard: View {
    let id: UInt64
    let title: String
    let message: String
    let buttons: [String]

    var body: some View {
        VStack(spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            ScrollView {
                Text(message)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 220)
            HStack(spacing: 10) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { index, label in
                    // The first button is the default (Return); the last is the way out.
                    Button(label.isEmpty ? "OK" : label) {
                        cemu_bridge_native_error_answer(id, Int32(index))
                    }
                    .buttonStyle(DialogButtonStyle(prominent: index == 0))
                    .modifier(ErrorShortcut(index: index, count: buttons.count))
                }
            }
        }
        .modifier(DialogCardBackground())
    }
}

private struct ErrorShortcut: ViewModifier {
    let index: Int
    let count: Int
    func body(content: Content) -> some View {
        if index == 0 {
            content.keyboardShortcut(.defaultAction)
        } else if index == count - 1 {
            content.keyboardShortcut(.cancelAction)
        } else {
            content
        }
    }
}

// MARK: - Layer

private struct NativeDialogLayer: View {
    private let poll = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var request: NativeDialogRequest?

    var body: some View {
        ZStack(alignment: .top) {
            if let request {
                // Swallows touches meant for the game or its controls while the card is up.
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}
                card(for: request)
                    .id(requestKey(request))
                    // Top of the screen, so the system keyboard never covers it in either
                    // orientation; the window's own insets keep it clear of a notch.
                    .padding(.top, max(WindowSafeArea.insets().top, 8) + 12)
            }
        }
        .onReceive(poll) { _ in
            let next = NativeDialogRequest.read()
            if next != request { request = next }
        }
    }

    @ViewBuilder
    private func card(for request: NativeDialogRequest) -> some View {
        switch request {
        case let .keyboard(id, maxLength, multiline, text, hint):
            KeyboardCard(id: id, maxLength: maxLength, multiline: multiline, text: text, hint: hint)
        case let .error(id, title, message, buttons):
            ErrorCard(id: id, title: title, message: message, buttons: buttons)
        }
    }

    /// A new request restarts the card (fresh text, fresh focus). Keyboard text updates
    /// don't change the request the core hands out, so typing never restarts it.
    private func requestKey(_ request: NativeDialogRequest) -> UInt64 {
        switch request {
        case let .keyboard(id, _, _, _, _): return id
        case let .error(id, _, _, _): return id
        }
    }
}

/// Drop-in layer for the emulator screen. Takes no space and no touches while no dialog is
/// up. `active` false hands both dialogs back to the core's ImGui drawing.
struct NativeDialogView: View {
    let active: Bool

    var body: some View {
        ZStack {
            if active { NativeDialogLayer() }
        }
        .onAppear { cemu_bridge_set_native_dialogs(active) }
        .onChange(of: active) { cemu_bridge_set_native_dialogs($0) }
        .onDisappear { cemu_bridge_set_native_dialogs(false) }
    }
}
