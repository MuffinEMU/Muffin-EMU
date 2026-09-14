import SwiftUI

/// The "why" that used to sit directly in a footer, now one tap behind an "i" -
/// footers in this screen say the one or two sentences someone needs to decide a
/// setting, and the full explanation (still the same words, none of it trimmed for
/// content) lives here instead of in front of every control whether they asked for
/// it or not.
///
/// A sheet rather than an alert: several of these run to four paragraphs, and
/// UIKit's alert text does not scroll on iOS 15 - a paragraph that runs off the
/// bottom of an alert is simply gone. A sheet with a ScrollView has no such ceiling.
struct InfoButton: View {
    let title: String
    let text: String
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .foregroundColor(MuffinTheme.brownMid)
        .sheet(isPresented: $showing) {
            // NavigationStack needs iOS 16+; this project's deployment target is 15.0.
            NavigationView {
                ScrollView {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(MuffinTheme.brownDarkest)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showing = false }
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
    }
}

extension InfoButton {
    /// A footer row: the short sentence a viewer needs inline, plus the "i" that
    /// opens the full original explanation. Every settings section footer in this
    /// screen that used to run long builds its footer this way, so cutting one down
    /// is a one-line change rather than restyling a bespoke HStack each time.
    static func footer(_ short: String, title: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(short)
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            InfoButton(title: title, text: text)
        }
    }
}
