import SwiftUI

struct XcodeToolbarItems: ToolbarContent {
    @Bindable var model: XcodeRunModel
    let onRun: () -> Void
    let onCancel: () -> Void
    let onReload: () -> Void
    let onInstallXcode: () -> Void
    @Binding var showLog: Bool

    var body: some ToolbarContent {
        if !model.toolchainAvailable {
            ToolbarItem(placement: .principal) {
                Button(action: onInstallXcode) {
                    Label("Install Xcode", systemImage: "arrow.down.app")
                }
                .help("Install Xcode from the App Store")
            }
        } else if model.projectRef != nil {
            ToolbarItem(placement: .principal) {
                RunButton(model: model, onRun: onRun, onCancel: onCancel)
            }
            ToolbarItem(placement: .principal) {
                BuildLogButton(model: model, isOpen: $showLog)
                    .popover(isPresented: $showLog) {
                        BuildLogPopover(model: model, isOpen: $showLog)
                    }
            }
            ToolbarItem(placement: .principal) {
                SchemePicker(model: model, onReload: onReload)
            }
            ToolbarItem(placement: .principal) {
                DestinationPicker(model: model)
            }
        }
    }
}

struct RunButton: View {
    @Bindable var model: XcodeRunModel
    let onRun: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Button {
            if model.runState.isBusy {
                onCancel()
            } else {
                onRun()
            }
        } label: {
            ZStack {
                Image(systemName: iconName)
                    .symbolRenderingMode(.hierarchical)
                if case .building = model.runState {
                    ProgressView()
                        .controlSize(.mini)
                        .offset(x: 10, y: -8)
                }
            }
        }
        .tint(tint)
        .help(helpText)
        .disabled(!model.runState.isBusy && (model.selectedScheme == nil || model.selectedDestination == nil))
    }

    private var iconName: String {
        model.runState.isBusy ? "stop.fill" : "play.fill"
    }

    private var tint: Color? {
        if case .failed = model.runState { return .red }
        if case .running = model.runState { return .green }
        return nil
    }

    private var helpText: String {
        switch model.runState {
        case .idle: return "Build and run the selected scheme"
        case .building: return "Cancel running build"
        case .running: return "Stop the running app"
        case .failed(let message): return "Last run failed — \(message)"
        }
    }
}

struct BuildLogButton: View {
    @Bindable var model: XcodeRunModel
    @Binding var isOpen: Bool

    var body: some View {
        if shouldShow {
            Button {
                isOpen.toggle()
            } label: {
                Image(systemName: iconName)
                    .symbolRenderingMode(.hierarchical)
            }
            .tint(tint)
            .help(helpText)
        }
    }

    private var shouldShow: Bool {
        if case .failed = model.runState { return true }
        return !model.logBuffer.isEmpty
    }

    private var iconName: String {
        if case .failed = model.runState { return "exclamationmark.bubble" }
        return "text.alignleft"
    }

    private var tint: Color? {
        if case .failed = model.runState { return .red }
        return nil
    }

    private var helpText: String {
        if case .failed(let message) = model.runState { return message }
        return "Build output"
    }
}
