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
        for issue in existingIssues {
            let folder = issue.id
            if folder.hasSuffix("-\(slug)") || folder == slug {
                return folder
            }
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
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let collision = input.collidingFolder(in: existingIssues) {
                collisionBanner(folder: collision)
            }
            if let error = allocationError {
                errorBanner(message: error)
            }
            form
            Divider()
            footer
        }
        .frame(minWidth: 480, idealWidth: 520)
        .onAppear { focusTitle = true }
    }

    private var header: some View {
        HStack {
            Text("New Issue")
                .font(.title2)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Spacer()
        }
    }

    private var form: some View {
        Form {
            TextField(
                "Title",
                text: Binding(
                    get: { input.title }, set: { input.onTitleChange($0) })
            )
            .font(.headline)
            .focused($focusTitle)

            VStack(alignment: .leading, spacing: 4) {
                TextField(
                    "Slug",
                    text: Binding(
                        get: { input.slug }, set: { input.onSlugEdit($0) })
                )
                .font(.body.monospaced())
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            input.slug.isEmpty || input.slugValid ? Color.clear : Color.red,
                            lineWidth: 0.5)
                )
                if !input.slug.isEmpty && !input.slugValid {
                    Text("Lowercase letters, digits, hyphens. Must start with letter or digit.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Picker("Type", selection: $input.type) {
                ForEach(IssueType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)

            LabelTagInput(labels: $input.labels, draft: $input.labelDraft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

    private var footer: some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
