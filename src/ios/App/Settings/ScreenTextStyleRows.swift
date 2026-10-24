// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// Where text the engine draws over the game sits and how it looks: the corner (Off hides it), the
/// text colour and the text size. The FPS counter and the notifications share these rows, each with
/// its own keys and bridge calls, so the two read and behave the same. Colour and size are disabled
/// (not hidden) while the position is Off, so they can be chosen before turning it on.
struct ScreenTextStyleRows: View {
    @Binding var positionRaw: Int
    @Binding var textColor: Int
    @Binding var textScale: Int
    /// Colour and size: Advanced mode only (see AdvancedSettings).
    let showsLook: Bool
    let setPosition: (Int32) -> Void
    let setTextColor: (UInt32) -> Void
    let setTextScale: (Int32) -> Void

    private var isOff: Bool { (ScreenPosition(rawValue: positionRaw) ?? .disabled) == .disabled }

    var body: some View {
        positionPicker
        if showsLook {
            textColorField
            textScaleSlider
        }
    }

    private var positionPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Position")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Picker("Position", selection: $positionRaw) {
                ForEach(ScreenPosition.allCases) { position in
                    Text(position.title).tag(position.rawValue)
                }
            }
            .pickerStyle(.menu)
            // The row's own Text is the label; a menu picker in a Form row prints its label as well.
            .labelsHidden()
            .tint(MuffinTheme.accentText)
        }
        .onChange(of: positionRaw) { setPosition(Int32($0)) }
    }

    private var textColorField: some View {
        ColorPicker("Text colour", selection: packedColourBinding($textColor), supportsOpacity: false)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .disabled(isOff)
            .onChange(of: textColor) { setTextColor(UInt32(truncatingIfNeeded: $0)) }
    }

    private var textScaleSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Text size")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(textScale)%")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
            Slider(
                value: Binding(get: { Double(textScale) }, set: { textScale = Int($0) }),
                in: 50...200, step: 25)
        }
        .disabled(isOff)
        .onChange(of: textScale) { setTextScale(Int32($0)) }
    }
}
