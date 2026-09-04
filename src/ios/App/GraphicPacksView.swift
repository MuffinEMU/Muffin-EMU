import SwiftUI

/// Browses and toggles graphic packs from Documents/mlc/graphicPacks/ - GraphicPack2
/// (Cafe/GraphicPack/) is a complete, already-working engine feature that simply had no
/// iOS surface before this. See cemu_bridge_graphic_packs_list in CemuBridge.h for the
/// wire format and IOSGraphicPacks.cpp for what's deliberately out of scope (presets).
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
                    Text("No graphic packs found. Add them to Documents/mlc/graphicPacks - each pack is a folder with its own rules.txt inside, the same layout desktop Cemu uses.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pack.name)
                                    .font(.system(size: 15, weight: .semibold))
                                if !pack.description.isEmpty {
                                    Text(pack.description)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                if pack.titleIdCount > 0 {
                                    Text(pack.titleIdCount == 1 ? "1 game" : "\(pack.titleIdCount) games")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } footer: {
                    // A real, current hardware limitation, not a hedge - see
                    // MetalRenderer.cpp's mesh-shader gate. Telling people up front beats
                    // a pack silently doing nothing and looking broken.
                    Text("This device has no mesh shader support, so packs that rely on geometry shaders or post-processing (RECTS) draws won't render correctly yet. Everything else works normally.")
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
