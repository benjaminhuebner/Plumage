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
            BodyTabEmptyState(
                symbol: "doc.text.magnifyingglass",
                title: "Noch keine pr.md",
                detail:
                    "Wird von `/plumage-implement` angelegt, sobald das Issue auf `waiting-for-review` wechselt."
            )
        }
    }
}
