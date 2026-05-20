import SwiftUI

struct XcodeToolbarItems: ToolbarContent {
    @Bindable var model: XcodeRunModel
    let onReload: () -> Void

    var body: some ToolbarContent {
        if model.projectRef != nil && model.toolchainAvailable {
            ToolbarItem(placement: .principal) {
                SchemePicker(model: model, onReload: onReload)
            }
            ToolbarItem(placement: .principal) {
                DestinationPicker(model: model)
            }
        }
    }
}
