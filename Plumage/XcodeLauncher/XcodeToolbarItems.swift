import AppKit
import SwiftUI

struct XcodeToolbarItems: ToolbarContent {
    @Bindable var model: XcodeRunModel
    let onRun: () -> Void
    let onCancel: () -> Void
    let onReload: () -> Void
    @Binding var showLog: Bool

    var body: some ToolbarContent {
        if !model.toolchainAvailable {
            ToolbarItem(placement: .principal) {
                Button {
                    if let url = ToolchainLocator.installXcodeURL {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Install Xcode", systemImage: "arrow.down.app")
                }
                .help("Install Xcode from the App Store")
            }
        } else if model.projectRef != nil {
            ToolbarItem(placement: .principal) {
                SchemePicker(model: model, onReload: onReload)
            }
            ToolbarItem(placement: .principal) {
                DestinationPicker(model: model)
            }
            ToolbarItem(placement: .principal) {
                RunButton(model: model, onRun: onRun, onCancel: onCancel)
            }
            ToolbarItem(placement: .principal) {
                RunStatusPill(model: model) { showLog.toggle() }
                    .popover(isPresented: $showLog) {
                        BuildLogPopover(model: model)
                    }
            }
        }
    }
}

struct RunButton: View {
    @Bindable var model: XcodeRunModel
    let onRun: () -> Void
    let onCancel: () -> Void

    var body: some View {
        if model.runState.isBusy {
            Button {
                onCancel()
            } label: {
                Image(systemName: "stop.fill")
            }
            .help("Cancel running build")
        } else {
            Button {
                onRun()
            } label: {
                Image(systemName: "play.fill")
            }
            .help("Build and run the selected scheme")
            .disabled(model.selectedScheme == nil || model.selectedDestination == nil)
        }
    }
}
