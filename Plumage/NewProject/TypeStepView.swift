import SwiftUI

struct TypeStepView: View {
    @Bindable var model: NewProjectModel

    var body: some View {
        TemplateGridView(selectedKind: $model.kind)
    }
}
