import SwiftUI

struct TypeStepView: View {
    @Bindable var model: NewProjectModel

    var body: some View {
        TemplateGridView(
            catalog: model.catalog,
            selectedTemplateID: $model.selectedTemplateID,
            resolveImage: { model.overrides.existingURL(forRelative: $0) })
    }
}
