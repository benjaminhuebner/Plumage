import SwiftUI

struct PromptTabView: View {
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityHint("Describe the idea for this issue")

            if text.isEmpty {
                Text("Describe the idea for this issue …")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    // Matches NSTextView's default textContainerInset on macOS 26.
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}
