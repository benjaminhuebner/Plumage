import SwiftUI

@Observable
final class NewIssueInput {
    var title: String = ""
    var slug: String = ""
    var slugTouched: Bool = false
    var type: IssueType = .feature
    var labels: [String] = []
    var labelDraft: String = ""

    func onTitleChange(_ new: String) {
        title = new
        if !slugTouched {
            slug = NextIssueAllocator.slugify(new)
        }
    }

    func onSlugEdit(_ new: String) {
        slug = new
        slugTouched = true
    }

    var slugValid: Bool {
        NextIssueAllocator.isValidSlug(slug)
    }

    var titleValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func collidingFolder(in existingIssues: [DiscoveredIssue]) -> String? {
        guard !slug.isEmpty else { return nil }
        let suffix = "-\(slug)"
        for issue in existingIssues where issue.id.hasSuffix(suffix) {
            return issue.id
        }
        return nil
    }

    func submitEnabled(existingIssues: [DiscoveredIssue]) -> Bool {
        guard titleValid, slugValid else { return false }
        return collidingFolder(in: existingIssues) == nil
    }
}

struct NewIssueSheet: View {
    let projectURL: URL
    let existingIssues: [DiscoveredIssue]
    let onCreate: (URL) -> Void
    let onCollision: (String) -> Void
    let onDismiss: () -> Void

    @State private var input = NewIssueInput()
    @State private var allocationError: String?
    @State private var isSubmitting: Bool = false
    @FocusState private var focusTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Issue")
                .font(.title2)

            if let collision = input.collidingFolder(in: existingIssues) {
                collisionBanner(folder: collision)
            }
            if let error = allocationError {
                errorBanner(message: error)
            }

            grid

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Create") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!input.submitEnabled(existingIssues: existingIssues) || isSubmitting)
            }
        }
        .padding(24)
        .frame(width: 520)
        .task {
            // `.onAppear` fires before the sheet finishes presenting and the focus
            // assignment is dropped intermittently. A short async hop after the
            // sheet is on screen makes the title field reliably take first focus.
            try? await Task.sleep(for: .milliseconds(50))
            focusTitle = true
        }
    }

    private var grid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                fieldLabel("Title")
                bordered(error: false) {
                    TextField(
                        "",
                        text: Binding(
                            get: { input.title }, set: { input.onTitleChange($0) })
                    )
                    .textFieldStyle(.plain)
                    .focused($focusTitle)
                }
            }

            GridRow(alignment: .top) {
                fieldLabel("Slug")
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    bordered(error: !input.slug.isEmpty && !input.slugValid) {
                        TextField(
                            "",
                            text: Binding(
                                get: { input.slug }, set: { input.onSlugEdit($0) })
                        )
                        .textFieldStyle(.plain)
                        .fontDesign(.monospaced)
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

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        allocationError = nil
        Task {
            let allocator = NextIssueAllocator(projectURL: projectURL)
            do {
                let url = try allocator.allocate(
                    slug: input.slug,
                    title: input.title.trimmingCharacters(in: .whitespaces),
                    type: input.type,
                    labels: input.labels
                )
                onCreate(url)
            } catch let NextIssueAllocatorError.slugCollision(folder) {
                onCollision(folder)
            } catch let NextIssueAllocatorError.templateMissing(url) {
                allocationError = "Template missing at \(url.path)"
            } catch {
                allocationError = "\(error)"
            }
            isSubmitting = false
        }
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
