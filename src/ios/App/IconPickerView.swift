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
        if let uiImage = UIImage(named: icon.id == "original" ? "AppIcon" : icon.alternateIconName) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else {
            Rectangle().fill(MuffinTheme.wrapper)
        }
    }
}
