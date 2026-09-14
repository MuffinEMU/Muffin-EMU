import SwiftUI

/// LabeledContent needs iOS 16+; this project's deployment target is 15.0. Shared
/// across several Settings sections now that the Form is split into per-section
/// files, rather than re-declared privately in each one.
struct SettingsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(MuffinTheme.brownMid)
        }
    }
}
