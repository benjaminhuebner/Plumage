import SwiftUI

struct NewIssueSheet: View {
    let projectURL: URL
    let existingIssues: [DiscoveredIssue]
    let onCreate: (URL) -> Void
    let onCollision: (String) -> Void
    let onDismiss: () -> Void

    @State private var input = NewIssueInput()
    @State private var allocationError: String?
    @State private var isSubmitting: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case title, slug }

    var body: some View {
        @Bindable var input = input
        return VStack(alignment: .leading, spacing: 16) {
            Text("New Issue")
                .font(.title2)

            if let collision = input.collidingFolder(in: existingIssues) {
                collisionBanner(folder: collision)
            }
            if let error = allocationError {
                errorBanner(message: error)
            }

            grid(input: input)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Create") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!input.submitEnabled(existingIssues: existingIssues) || isSubmitting)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: input.title) {
            input.handleTitleChanged()
        }
        .onChange(of: input.slug) {
            // Only treat slug changes as user edits when the slug field has focus —
            // otherwise this fires from handleTitleChanged()'s auto-sync.
            if focusedField == .slug {
                input.slugTouched = true
            }
        }
        .task {
            // `.onAppear` fires before the sheet finishes presenting and the focus
            // assignment is dropped intermittently. A short async hop after the
            // sheet is on screen makes the title field reliably take first focus.
            try? await Task.sleep(for: .milliseconds(50))
            focusedField = .title
        }
    }

    @ViewBuilder
    private func grid(input: NewIssueInput) -> some View {
        @Bindable var input = input
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                fieldLabel("Title")
                bordered(error: false) {
                    TextField("", text: $input.title)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .title)
                }
            }

            GridRow(alignment: .top) {
                fieldLabel("Slug")
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    bordered(error: !input.slug.isEmpty && !input.slugValid) {
                        TextField("", text: $input.slug)
                            .textFieldStyle(.plain)
                            .fontDesign(.monospaced)
                            .focused($focusedField, equals: .slug)
                    }
                    if !input.slug.isEmpty && !input.slugValid {
                        Text(
                            "Lowercase letters, digits, hyphens. Must start with letter or digit."
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
            }

            GridRow {
                fieldLabel("Type")
                Picker("", selection: $input.type) {
                    ForEach(IssueType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 160, alignment: .leading)
            }

            GridRow(alignment: .top) {
                fieldLabel("Labels")
                    .padding(.top, 6)
                LabelTagInput(labels: $input.labels, draft: $input.labelDraft)
            }
        }
    }

    @ViewBuilder
    private func bordered<Content: View>(
        error: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        error ? Color.red : Color.secondary.opacity(0.35),
                        lineWidth: error ? 1 : 0.5
                    )
            )
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
            .frame(minWidth: 60, alignment: .trailing)
    }

    private func collisionBanner(folder: String) -> some View {
        HStack {
            Text("Slug '\(input.slug)' already exists at \(folder)")
                .foregroundStyle(.red)
            Spacer()
            Button("Show in Kanban") {
                onCollision(folder)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }

    private func errorBanner(message: String) -> some View {
        HStack {
            Text("Failed to create issue: \(message)")
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }

    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        allocationError = nil
        switch await input.submit(projectURL: projectURL) {
        case .created(let url):
            onCreate(url)
        case .collision(let folder):
            onCollision(folder)
        case .failed(let reason):
            allocationError = reason
        }
        isSubmitting = false
    }
}

#Preview {
    NewIssueSheet(
        projectURL: URL(filePath: "/tmp/sample"),
        existingIssues: [],
        onCreate: { _ in },
        onCollision: { _ in },
        onDismiss: {}
    )
}
