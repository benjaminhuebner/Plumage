import CodeEditorView
import LanguageSupport
import SwiftUI

struct SpecEditorView: View {
    let projectURL: URL
    let folderName: String

    @State private var buffer: String = ""
    @State private var editorPosition = CodeEditor.Position()
    @State private var editorMessages: Set<TextLocated<Message>> = []

    var body: some View {
        CodeEditor(
            text: $buffer,
            position: $editorPosition,
            messages: $editorMessages,
            language: .markdown()
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SpecEditorView(
        projectURL: URL(filePath: "/tmp/sample"),
        folderName: "00001-walking-skeleton"
    )
    .frame(width: 800, height: 600)
}
