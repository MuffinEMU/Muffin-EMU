import SwiftUI

/// Browses and toggles graphic packs from Documents/mlc/graphicPacks/. See
/// cemu_bridge_graphic_packs_list in CemuBridge.h for the wire format.
struct GraphicPacksView: View {
    private struct Pack: Identifiable {
        let index: Int
        var id: Int { index }
        let name: String
        let description: String
        var isEnabled: Bool
        let titleIdCount: Int
    }

    @State private var packs: [Pack] = []

    var body: some View {
        List {
            if packs.isEmpty {
                Section {
                    ScreenEmptyState(
                        systemImage: "square.stack.3d.up",
                        headline: "No graphic packs yet",
                        message: "Put pack folders in Documents/mlc/graphicPacks. Each pack needs a rules.txt, same as desktop Cemu."
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach($packs) { $pack in
                        Toggle(isOn: Binding(
                            get: { pack.isEnabled },
                            set: { newValue in
                                pack.isEnabled = newValue
                                cemu_bridge_graphic_pack_set_enabled(Int32(pack.index), newValue)
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pack.name)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                if !pack.description.isEmpty {
                                    Text(pack.description)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                // Metadata chip, kept visually separate from the description.
                                if pack.titleIdCount > 0 {
                                    ScreenChip(text: pack.titleIdCount == 1 ? "1 game" : "\(pack.titleIdCount) games")
                                        .padding(.top, 1)
                                }
                            }
                        }
                        .tint(MuffinTheme.pixelBlue)
                    }
                } footer: {
                    Text("Packs that need geometry shaders or post-processing may not render correctly on this device.")
                }
            }
        }
        .navigationTitle("Graphic Packs")
        .onAppear(perform: reload)
        .refreshable { reload() }
    }

    private func reload() {
        cemu_bridge_graphic_packs_refresh()
        let raw = String(cString: cemu_bridge_graphic_packs_list())
        guard !raw.isEmpty else {
            packs = []
            return
        }
        packs = raw.split(separator: "\u{1E}").compactMap { record in
            let fields = record.split(separator: "\u{1F}", omittingEmptySubsequences: false)
            guard fields.count >= 5, let index = Int(fields[0]) else { return nil }
            let titleIdCount = fields[4].isEmpty ? 0 : fields[4].split(separator: ",").count
            return Pack(
                index: index,
                name: String(fields[1]),
                description: String(fields[2]),
                isEnabled: fields[3] == "1",
                titleIdCount: titleIdCount
            )
        }
    }
}
