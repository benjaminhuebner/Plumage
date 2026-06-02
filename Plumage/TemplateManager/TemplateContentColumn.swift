import SwiftUI

// Middle column: the file tree of the selected left-column item plus a read-only
// membership section. Built out in the middle-column task; placeholder for now.
struct TemplateContentColumn: View {
    let model: TemplateManagerModel

    var body: some View {
        Text("Select an item")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
