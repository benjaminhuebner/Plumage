import CodeEditorView
import LanguageSupport
import SwiftUI

struct SpecTabView: View {
    @Binding var text: String
    @Binding var position: CodeEditor.Position
    @Binding var messages: Set<TextLocated<Message>>
    let language: LanguageConfiguration
    let layout: CodeEditor.LayoutConfiguration

    var body: some View {
        CodeEditor(
            text: $text,
            position: $position,
            messages: $messages,
            language: language
        )
        .environment(\.codeEditorLayoutConfiguration, layout)
        .frame(minHeight: 240)
    }
}
