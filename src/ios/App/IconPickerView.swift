// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentIconName: String? = UIApplication.shared.alternateIconName
    @State private var errorMessage: String?
    /// Why a tap did nothing. A locked Pro icon used to `return` out of `select()` in
    /// silence, which is indistinguishable from a button that doesn't work - the lock
    /// badge says the icon IS locked, but nothing said that's why the tap was ignored.
    @State private var lockedMessage: String?
    @State private var style: IconStyle = IconStyle.current

    var body: some View {
        // NavigationStack needs iOS 16+; this project's deployment target is 15.0.
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    if let banner = errorMessage ?? lockedMessage {
                        MuffinCard {
                            ScreenStatusCallout(tone: .warning, message: banner)
                                .padding(12)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .transition(.opacity)
                    }

                    // Revamped icons or the originals. Switching also swaps the icon in use for its
                    // other version, so the home screen follows the choice.
                    Picker("Icon style", selection: $style) {
                        ForEach(IconStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .onChange(of: style) { newStyle in
                        IconStyle.current = newStyle
                        applyStyleToCurrentIcon(newStyle)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                        ForEach(IconManifest.all) { icon in
                            IconOptionCard(
                                icon: icon,
                                style: style,
                                isSelected: isSelected(icon),
                                isLocked: icon.isPro && !Entitlements.hasProPlan,
                                onSelect: { select(icon) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("App Icon")
            .muffinOpaqueNavigationBar()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Plain, like every other sheet's Done in this app (SaveStateSheet,
                    // EmulatedDevicesView, CoverArtPickerView's Cancel). A cream pill
                    // inside the navigation bar was the odd one out here and in
                    // ThemePickerView, and a filled capsule fights the bar's own material
                    // rather than sitting in it.
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func isSelected(_ icon: AppIconOption) -> Bool {
        icon.id == "original" ? currentIconName == nil : IconManifest.id(forAlternateIconName: currentIconName) == icon.id
    }

    /// After a style switch, move the icon in use to its version in the new style, if it has one.
    private func applyStyleToCurrentIcon(_ newStyle: IconStyle) {
        guard let id = IconManifest.id(forAlternateIconName: currentIconName),
              let icon = IconManifest.all.first(where: { $0.id == id }),
              icon.classic != nil,
              !(icon.isPro && !Entitlements.hasProPlan) else { return }
        let name = icon.alternateIconName(newStyle)
        guard name != currentIconName else { return }
        UIApplication.shared.setAlternateIconName(name) { error in
            if let error {
                errorMessage = String(format: "Couldn't switch icon: %@".localized, error.localizedDescription)
                return
            }
            currentIconName = name
        }
    }

    private func select(_ icon: AppIconOption) {
        guard !(icon.isPro && !Entitlements.hasProPlan) else {
            ScreenHaptics.rejected()
            withAnimation(.easeOut(duration: 0.18)) {
                lockedMessage = String(format: "%@ is a pro icon. Enter an unlock code under Settings > Premium to use it.".localized, icon.name)
            }
            return
        }
        let name = icon.id == "original" ? nil : icon.alternateIconName(style)
        guard name != currentIconName else { return }
        withAnimation(.easeOut(duration: 0.18)) { lockedMessage = nil }
        ScreenHaptics.selectionChanged()
        UIApplication.shared.setAlternateIconName(name) { error in
            if let error {
                errorMessage = String(format: "Couldn't switch icon: %@".localized, error.localizedDescription)
                return
            }
            errorMessage = nil
            currentIconName = name
        }
    }
}

private struct IconOptionCard: View {
    let icon: AppIconOption
    let style: IconStyle
    let isSelected: Bool
    let isLocked: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            MuffinCard {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        // A locked Pro icon is shown blurred under a lock: enough to tell what it is,
                        // not enough to be the icon.
                        iconThumbnail
                            .frame(width: 64, height: 64)
                            .blur(radius: isLocked ? 3 : 0)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                if isLocked {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.94, blue: 0.72), Color(red: 0.73, green: 0.51, blue: 0.16)],
                                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(isSelected ? MuffinTheme.pixelBlue : MuffinTheme.wrapper, lineWidth: isSelected ? 3 : 1)
                            )

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(MuffinTheme.accentText)
                                .background(MuffinTheme.sparkleCream, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }

                    Text(icon.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(MuffinTheme.brownDarkest)
                        .lineLimit(1)

                    Text(icon.tagline(style))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(MuffinTheme.brownMid)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Same selected-card lift as ThemePickerView's grid, for the same reason:
            // thirty tiles is too many to find a 16pt checkmark in.
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .shadow(color: MuffinTheme.pixelBlue.opacity(isSelected ? 0.28 : 0), radius: 10, x: 0, y: 4)
            .animation(.easeOut(duration: 0.16), value: isSelected)
        }
        .buttonStyle(ScreenCardButtonStyle())
        .accessibilityLabel(isLocked ? String(format: "%@, locked, Pro only".localized, icon.name) : icon.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var iconThumbnail: some View {
        if let uiImage = IconOptionCard.previewImage(for: icon, style: style) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else {
            // Still possible, and still better than an empty card: name the icon rather
            // than showing a blank tile that looks like a loading failure.
            ZStack {
                Rectangle().fill(MuffinTheme.wrapper)
                Text(String(icon.name.prefix(2)).uppercased())
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(MuffinTheme.brownDarkest.opacity(0.55))
            }
        }
    }

    /// Every card was blank because UIImage(named:) cannot load an App-Icon-type asset
    /// catalog entry - on any iOS version, regardless of whether it's declared through
    /// ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES or a plain CFBundleIconName/
    /// CFBundleAlternateIcons reference. App Icon sets compile into a special icon-only
    /// area of Assets.car that only the system's own icon-rendering (springboard,
    /// UIApplication.icon on 26+) can read - general image lookup, UIImage(named:)
    /// included, simply doesn't see them. A previous version of this function tried to
    /// work around that by searching the bundle for loose PNG files, on the theory that
    /// Xcode compiles alternate icons out to the bundle root - it doesn't for this
    /// project's icons, which are genuine .appiconset entries in Assets.xcassets (single
    /// 1024x1024 source image each, confirmed by reading their Contents.json), so that
    /// search always found nothing and every single card silently fell back to the
    /// placeholder initials tile.
    ///
    /// Real fix: a companion plain .imageset - "<name>-preview", one per .appiconset,
    /// same source PNG - since a normal (non-app-icon) image set has none of the
    /// App-Icon-type restriction and loads via UIImage(named:) exactly like any other
    /// image asset. AppIcon itself gets one too (AppIcon-preview), since the "original"
    /// card hit the exact same restriction.
    static func previewImage(for icon: AppIconOption, style: IconStyle) -> UIImage? {
        let assetName = icon.id == "original" ? "AppIcon" : icon.alternateIconName(style)
        if let cached = previewCache[assetName] {
            return cached
        }
        let image = UIImage(named: "\(assetName)-preview")
        previewCache[assetName] = image
        return image
    }

    /// UIImage(named:) already caches internally, but this view redraws its whole grid
    /// (thirty-plus cards) on every selection change, and the dictionary lookup avoids
    /// even that repeated named-lookup cost.
    private static var previewCache: [String: UIImage?] = [:]
}
