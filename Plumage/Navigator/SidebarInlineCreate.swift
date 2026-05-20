import AppKit
import SwiftUI

// Inline TextField row for create-new-row interactions (set via
// `NavigatorModel.beginPendingCreate`).
struct InlineCreateRow: View {
    let projectURL: URL
    let icon: String
    @Environment(NavigatorModel.self) private var navigator
    @FocusState private var focused: Bool
    @State private var didAutoFocus = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            TextField(
                "",
                text: nameBinding,
                prompt: Text(navigator.pendingCreate?.section.defaultName ?? "")
            )
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit {
                Task { @MainActor in
                    _ = await navigator.commitPendingCreate(projectURL: projectURL)
                }
            }
            .onExitCommand {
                navigator.cancelPendingCreate()
            }
            .onChange(of: focused) { _, isFocused in
                guard didAutoFocus, !isFocused else { return }
                Task { @MainActor in
                    _ = await navigator.commitPendingCreate(projectURL: projectURL)
                }
            }
        }
        // Small delay so the row's TextField is part of the responder chain
        // before we ask for focus.
        .task(id: navigator.pendingCreate?.id) {
            try? await Task.sleep(for: .milliseconds(50))
            focused = true
            didAutoFocus = true
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { navigator.pendingCreate?.name ?? "" },
            set: { newValue in
                guard navigator.pendingCreate != nil else { return }
                navigator.pendingCreate?.name = newValue
            }
        )
    }
}

// Inline TextField row for renaming an existing file/folder row. Lives in
// the same row position as the source label so the rename swap-in is
// in-place (no list reorder).
struct InlineRenameRow: View {
    let projectURL: URL
    let icon: String
    @Environment(NavigatorModel.self) private var navigator
    @FocusState private var focused: Bool
    @State private var didAutoFocus = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            TextField(
                "",
                text: nameBinding,
                prompt: Text(navigator.renaming?.url.lastPathComponent ?? "")
            )
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit {
                Task { @MainActor in
                    _ = await navigator.commitRename(projectURL: projectURL)
                }
            }
            .onExitCommand {
                navigator.cancelRename()
            }
            .onChange(of: focused) { _, isFocused in
                guard didAutoFocus, !isFocused else { return }
                Task { @MainActor in
                    _ = await navigator.commitRename(projectURL: projectURL)
                }
            }
        }
        .task(id: navigator.renaming?.id) {
            try? await Task.sleep(for: .milliseconds(50))
            focused = true
            didAutoFocus = true
            // Auto-select the stem (everything before the file extension)
            // so the user can type-to-replace, matching Finder rename UX.
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
                let raw = navigator.renaming?.name
            {
                editor.setSelectedRange(stemRange(in: raw))
            }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { navigator.renaming?.name ?? "" },
            set: { newValue in
                guard navigator.renaming != nil else { return }
                navigator.renaming?.name = newValue
            }
        )
    }

    private func stemRange(in name: String) -> NSRange {
        let ns = name as NSString
        let dot = ns.range(of: ".", options: .backwards)
        if dot.location == NSNotFound || dot.location == 0 {
            return NSRange(location: 0, length: ns.length)
        }
        return NSRange(location: 0, length: dot.location)
    }
}
