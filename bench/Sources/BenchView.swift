//
//  BenchView.swift
//  The whole UI: title, Start, the render surface (visible during a run so a wedged
//  boot is visible as a black/frozen frame rather than invisible), live progress, and
//  once finished, the report with Copy and Share. iOS 15 deployment target means
//  NavigationView (not NavigationStack) and a UIActivityViewController wrapper for
//  sharing (ShareLink didn't exist until iOS 16).
//
import SwiftUI
import UIKit

struct BenchView: View {
    @StateObject private var runner = BenchRunner()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    RenderSurfaceView(runner: runner)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                        .cornerRadius(8)

                    Button(action: startTapped) {
                        Text(runner.isRunning ? "Running..." : "Start")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(runner.isRunning)

                    if !runner.progressLines.isEmpty {
                        progressList
                    }

                    if let report = runner.reportText {
                        Divider()
                        reportSection(report)
                    }

                    Button("Last report") {
                        runner.loadLastReportFromDisk()
                    }
                    .disabled(runner.isRunning)
                }
                .padding()
            }
            .navigationTitle("MuffinEMU Bench")
        }
        .navigationViewStyle(.stack)
    }

    private var progressList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(runner.progressLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.footnote, design: .monospaced))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(6)
    }

    private func reportSection(_ report: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(report)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            .padding(8)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(6)

            HStack(spacing: 12) {
                Button(action: { UIPasteboard.general.string = report }) {
                    Text("Copy report")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                Button(action: { presentShareSheet(text: report) }) {
                    Image(systemName: "square.and.arrow.up")
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func startTapped() {
        Task { await runner.run() }
    }

    /// UIActivityViewController by hand instead of ShareLink, which needs iOS 16 - this
    /// app's deployment target is iOS 15.
    private func presentShareSheet(text: String) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        root.present(activity, animated: true)
    }
}
