import SwiftUI

// Right column: a read-only code view of the file selected in the middle column.
// Built out in the right-column task; placeholder for now.
struct TemplateCodeColumn: View {
    let model: TemplateManagerModel

    var body: some View {
        Text("Select a file")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
