import SwiftUI

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentIconName: String? = UIApplication.shared.alternateIconName
    @State private var errorMessage: String?

    var body: some View {
        // NavigationStack needs iOS 16+; this project's deployment target is 15.0.
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(MuffinTheme.brownDarkest)
                            .padding(10)
                            .background(MuffinTheme.blushPink)
                            .cornerRadius(10)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                        ForEach(IconManifest.all) { icon in
                            IconOptionCard(
                                icon: icon,
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(MuffinSecondaryButtonStyle())
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func isSelected(_ icon: AppIconOption) -> Bool {
        icon.id == "original" ? currentIconName == nil : currentIconName == icon.alternateIconName
    }

    private func select(_ icon: AppIconOption) {
        guard !(icon.isPro && !Entitlements.hasProPlan) else { return }
        let name = icon.id == "original" ? nil : icon.alternateIconName
        guard name != currentIconName else { return }
        UIApplication.shared.setAlternateIconName(name) { error in
            if let error {
                errorMessage = "Couldn't switch icon: \(error.localizedDescription)"
                return
            }
            errorMessage = nil
            currentIconName = name
        }
    }
}

private struct IconOptionCard: View {
    let icon: AppIconOption
    let isSelected: Bool
    let isLocked: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            MuffinCard {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        iconThumbnail
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(isSelected ? MuffinTheme.pixelBlue : MuffinTheme.wrapper, lineWidth: isSelected ? 3 : 1)
                            )
                            .opacity(isLocked ? 0.5 : 1.0)

                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(MuffinTheme.sparkleCream)
                                .padding(5)
                                .background(MuffinTheme.blueberryNavy)
                                .clipShape(Circle())
                                .offset(x: 6, y: -6)
                        } else if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(MuffinTheme.pixelBlue)
                                .background(MuffinTheme.sparkleCream, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }

                    Text(icon.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(MuffinTheme.brownDarkest)
                        .lineLimit(1)

                    Text(icon.tagline)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(MuffinTheme.brownMid)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconThumbnail: some View {
        if let uiImage = IconOptionCard.previewImage(for: icon) {
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
    static func previewImage(for icon: AppIconOption) -> UIImage? {
        let assetName = icon.id == "original" ? "AppIcon" : icon.alternateIconName
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
