//
//  GameGraphicPacksView.swift
//  MeloCafe
//
//  Created by Stossy11 on 25/4/2026.
//

import SwiftUI
import Combine

struct GameGraphicPacksView: View {
    let titleId: UInt64
    let gameName: String

    @StateObject private var viewModel = GraphicPacksViewModel()
    @State private var searchText = ""

    var gamePacks: [GraphicPack] {
        viewModel.packs.filter { $0.titleIds.contains(titleId) }
    }

    var filteredPacks: [GraphicPack] {
        guard !searchText.isEmpty else { return gamePacks }
        return gamePacks.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.virtualPath.localizedCaseInsensitiveContains(searchText)
        }
    }

    var groupedPacks: [(String, [GraphicPack])] {
        var dict = [String: [GraphicPack]]()
        for pack in filteredPacks {
            dict[pack.group, default: []].append(pack)
        }
        return dict.sorted { $0.key < $1.key }
    }

    var body: some View {
        List {
            Section {
                if viewModel.isDownloading {
                    VStack(spacing: 8) {
                        Text(viewModel.downloadStage)
                            .font(.subheadline)
                        ProgressView(value: viewModel.downloadProgress)
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        viewModel.downloadPacks()
                    } label: {
                        Label("Download latest graphic packs", systemImage: "arrow.down.circle")
                    }
                }

                if let error = viewModel.downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if gamePacks.isEmpty && !viewModel.isDownloading {
                Section {
                    if #available(iOS 17.0, *) {
                        ContentUnavailableView(
                            "No Graphic Packs",
                            systemImage: "photo.stack",
                            description: Text("No graphic packs are available for \(gameName).")
                        )
                    } else {
                        VStack(spacing: 20) {
                            Spacer()

                            Image(systemName: "photo.stack")
                                .font(.system(size: 64))
                                .foregroundColor(.secondary)

                            Text("No Graphic Packs")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("No graphic packs are available for \(gameName).")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                    }
                }
            }

            ForEach(groupedPacks, id: \.0) { group, packs in
                Section(group) {
                    ForEach(packs) { pack in
                        GraphicPackRow(pack: pack, viewModel: viewModel)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search graphic packs")
        .navigationTitle("\(gameName) Graphic Packs")
        .onAppear {
            viewModel.refresh()
        }
    }
}
