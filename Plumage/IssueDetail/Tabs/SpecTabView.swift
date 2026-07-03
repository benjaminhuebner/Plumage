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
        // Fill the available height instead of sizing to content: the editor's
        // own scroll view absorbs document growth, so a keystroke that adds a
        // line no longer re-solves the whole detail view's layout (a typing stutter).
        .frame(minHeight: 240, maxHeight: .infinity)
    }
}
