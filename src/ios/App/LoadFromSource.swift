// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import LoadKit

/// "Load from Folder" and "Load from File": pick, check what was picked, check the storage it sits on, then either play it
/// where it is (ExternalLibrary, read-only bookmark) or copy it in (GameManager.importROM, staged then promoted).
@MainActor
final class LoadCoordinator: ObservableObject {
    enum Mode { case folder, file }

    struct Plan: Identifiable {
        let id = UUID()
        let url: URL
        let finding: SourceFinding
        let verdict: StorageVerdict
        var canCopy: Bool { verdict.canCopy && finding.gameCount == 1 }
    }

    @Published var plan: Plan?
    @Published var checking: String?
    @Published var message: String?
    private var scopedURL: URL?

    func begin(_ mode: Mode) {
        DocumentImport.present(contentTypes: mode == .folder ? [.folder] : [.item]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await self.inspect(url) }
            case .failure(let error):
                self.message = error.localizedDescription
            }
        }
    }

    private func inspect(_ url: URL) async {
        finish()
        let scoped = url.startAccessingSecurityScopedResource()
        if scoped { scopedURL = url }
        checking = url.lastPathComponent
        let outcome: (Result<SourceFinding, SourceIssue>, StorageVerdict?) = await Task.detached {
            let disk = DiskInspector()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return (.failure(.unreadable(url.lastPathComponent)), nil)
            }
            let result = isDirectory.boolValue
                ? GameSourceValidator.validateFolder(url.path, using: disk)
                : GameSourceValidator.validateFile(url.path, using: disk)
            guard case .success = result else { return (result, nil) }
            return (result, StorageAssessment.evaluate(StorageProbe.collect(path: url.path, using: disk)))
        }.value
        checking = nil
        switch outcome {
        case (.success(let finding), let verdict?):
            plan = Plan(url: url, finding: finding, verdict: verdict)
        case (.failure(let issue), _):
            finish()
            message = issue.errorDescription
        default:
            finish()
        }
    }

    func finish() {
        if let url = scopedURL { url.stopAccessingSecurityScopedResource() }
        scopedURL = nil
        plan = nil
    }

    func playInPlace(_ plan: Plan, gameManager: GameManager) {
        Task {
            do { try await gameManager.linkLocation(plan.url) } catch { message = error.localizedDescription }
            finish()
        }
    }

    func copyIn(_ plan: Plan, gameManager: GameManager) {
        Task {
            do { try await gameManager.importROM(from: plan.url) } catch { message = error.localizedDescription }
            finish()
        }
    }

    static func describe(_ plan: Plan) -> String {
        var lines: [String] = []
        switch plan.finding.kind {
        case .dumpFolder: lines.append("Decrypted game folder (code, content, meta).")
        case .nusFolder: lines.append("Wii U title folder (title.tmd and .app files).")
        case .gameCollection(let count): lines.append("A folder holding \(count) games.")
        case .file(let ext): lines.append("A .\(ext) game file.")
        }
        lines.append(contentsOf: plan.finding.warnings)
        lines.append(plan.verdict.summary)
        lines.append(contentsOf: plan.verdict.reasons)
        lines.append(contentsOf: plan.verdict.notes)
        if plan.verdict.level != .good, plan.canCopy {
            lines.append("Copying it into MuffinEMU is the dependable option. The original is never changed.")
        } else {
            lines.append("The original is never changed.")
        }
        return lines.joined(separator: "\n\n")
    }
}

struct LoadPrompts: ViewModifier {
    @ObservedObject var coordinator: LoadCoordinator
    let gameManager: GameManager

    func body(content: Content) -> some View {
        content
            .overlay(Group {
                if let name = coordinator.checking {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Checking \(name)\u{2026}").font(.footnote)
                    }
                    .padding(16)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                }
            })
            .background(Color.clear.confirmationDialog(
                coordinator.plan.map { "Load \"\($0.finding.displayName)\"" } ?? "",
                isPresented: Binding(get: { coordinator.plan != nil }, set: { if !$0 { coordinator.finish() } }),
                titleVisibility: .visible,
                presenting: coordinator.plan
            ) { plan in
                if plan.canCopy {
                    Button("Copy into MuffinEMU") { coordinator.copyIn(plan, gameManager: gameManager) }
                }
                if plan.verdict.level == .unsuitable {
                    if plan.verdict.canPlayAnyway {
                        Button("Play anyway (not recommended)", role: .destructive) {
                            coordinator.playInPlace(plan, gameManager: gameManager)
                        }
                    }
                } else {
                    Button("Play from here") { coordinator.playInPlace(plan, gameManager: gameManager) }
                }
                Button("Cancel", role: .cancel) { coordinator.finish() }
            } message: { plan in
                Text(LoadCoordinator.describe(plan))
            })
            .background(Color.clear.alert(
                "Can't load that",
                isPresented: Binding(get: { coordinator.message != nil }, set: { if !$0 { coordinator.message = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(coordinator.message ?? "")
            })
    }
}

extension View {
    func loadPrompts(_ coordinator: LoadCoordinator, gameManager: GameManager) -> some View {
        modifier(LoadPrompts(coordinator: coordinator, gameManager: gameManager))
    }
}
