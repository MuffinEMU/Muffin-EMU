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

    /// Every card was blank because UIImage(named:) cannot load an app icon.
    ///
    /// Alternate icons declared through ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES are
    /// not left in the asset catalog: Xcode compiles them out to loose files at the bundle
    /// root, named like AltIcon-dark60x60@2x.png. UIImage(named:) looks in the catalog, so
    /// it finds nothing and every preview fell through to the placeholder.
    ///
    /// So the bundle is searched directly. The exact filenames are Xcode's business and
    /// have changed between versions, which is why this matches on prefix and takes the
    /// largest match rather than guessing one name.
    static func previewImage(for icon: AppIconOption) -> UIImage? {
        let assetName = icon.id == "original" ? "AppIcon" : icon.alternateIconName
        if let image = UIImage(named: assetName) {
            return image
        }
        if let cached = previewCache[assetName] {
            return cached
        }
        let prefix = icon.id == "original" ? "AppIcon" : icon.alternateIconName
        let candidates = Bundle.main.paths(forResourcesOfType: "png", inDirectory: nil)
            .filter { ($0 as NSString).lastPathComponent.hasPrefix(prefix) }
        // Largest file is the highest-resolution variant, which is the one worth showing
        // in a grid of cards.
        let best = candidates.max { lhs, rhs in
            let l = (try? FileManager.default.attributesOfItem(atPath: lhs)[.size] as? Int) ?? 0
            let r = (try? FileManager.default.attributesOfItem(atPath: rhs)[.size] as? Int) ?? 0
            return (l ?? 0) < (r ?? 0)
        }
        let image = best.flatMap { UIImage(contentsOfFile: $0) }
        previewCache[assetName] = image
        return image
    }

    /// The bundle listing is a directory walk, and this view redraws it for every card in
    /// a scrolling grid of thirty. Done once per icon instead.
    private static var previewCache: [String: UIImage?] = [:]
}
