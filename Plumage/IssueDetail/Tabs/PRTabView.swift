import CodeEditorView
import LanguageSupport
import SwiftUI

struct PRTabView: View {
    let content: String?
    @Binding var position: CodeEditor.Position
    @Binding var messages: Set<TextLocated<Message>>
    let language: LanguageConfiguration
    let layout: CodeEditor.LayoutConfiguration

    var body: some View {
        if let content {
            CodeEditor(
                text: .constant(content),
                position: $position,
                messages: $messages,
                language: language
            )
            .environment(\.codeEditorLayoutConfiguration, layout)
            .frame(minHeight: 240)
            .disabled(true)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("Noch keine pr.md")
                    .font(.headline)
                Text("Wird von `/plumage-implement` angelegt, sobald das Issue auf `waiting-for-review` wechselt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
        }
    }
}
