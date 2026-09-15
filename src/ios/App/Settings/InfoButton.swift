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
                .font(.system(size: 15, weight: .semibold))
                // pixelBlue, not brownMid. This is the only tappable thing in a footer
                // otherwise made entirely of grey explanatory text, and at brownMid it
                // was indistinguishable from that text - people were reading the short
                // sentence and never discovering the long one behind it.
                .foregroundColor(MuffinTheme.pixelBlue)
                // A footer glyph is ~15pt of ink. The frame + contentShape is what makes
                // the target something a thumb can actually land on rather than a pixel
                // hunt, without moving the glyph itself.
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("About \(title)")
        .sheet(isPresented: $showing) {
            // NavigationStack needs iOS 16+; this project's deployment target is 15.0.
            NavigationView {
                // The brand gradient behind the text, the same way every other sheet in
                // the app is built - an InfoButton sheet used to be the one modal that
                // opened onto flat system white and broke the illusion that these
                // explanations are part of MuffinEMU rather than part of iOS.
                ZStack {
                    MuffinTheme.backgroundGradient
                        .ignoresSafeArea()

                    ScrollView {
                        Text(text)
                            .font(.system(size: 15))
                            .lineSpacing(3)
                            .foregroundColor(MuffinTheme.brownDarkest)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                    }
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
            footerText(short)
            Spacer(minLength: 4)
            InfoButton(title: title, text: text)
                // Pulls the 30pt tap target back into the text's own optical column, so
                // the enlarged hit area costs no visible trailing margin.
                .padding(.trailing, -7)
        }
        .padding(.top, 2)
    }

    /// The same footer typography for a section whose explanation is already short
    /// enough that there is nothing to put behind an "i" (Shader Cache, This Device,
    /// Premium, About). These used to be bare `Text` and so set their own line height,
    /// which is why footer rhythm drifted between sections that had an info button and
    /// sections that didn't.
    static func footer(_ short: String) -> some View {
        footerText(short)
            .padding(.top, 2)
    }

    /// Footers in this screen are long by design - the app explains itself rather than
    /// assuming emulator fluency. `lineSpacing` is what keeps four explanatory lines
    /// reading as calm supporting text instead of as a wall, and `fixedSize` stops
    /// SwiftUI truncating them to one line inside a Form footer.
    private static func footerText(_ short: String) -> some View {
        Text(short)
            .font(.footnote)
            .foregroundColor(.secondary)
            .lineSpacing(2.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}
