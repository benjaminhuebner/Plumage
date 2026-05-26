import CodeEditorView
import LanguageSupport
import SwiftUI

struct PromptTabView: View {
    @Binding var text: String
    @Binding var position: CodeEditor.Position
    @Binding var messages: Set<TextLocated<Message>>
    let language: LanguageConfiguration
    let layout: CodeEditor.LayoutConfiguration

    var body: some View {
        ZStack(alignment: .topLeading) {
            CodeEditor(
                text: $text,
                position: $position,
                messages: $messages,
                language: language
            )
            .environment(\.codeEditorLayoutConfiguration, layout)
            .frame(minHeight: 240)

            if text.isEmpty {
                Text("Describe the idea for this issue …")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 16)
                    .allowsHitTesting(false)
            }
        }
    }
}
