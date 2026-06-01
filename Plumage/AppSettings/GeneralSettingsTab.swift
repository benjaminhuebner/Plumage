import SwiftUI

struct GeneralSettingsTab: View {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    var body: some View {
        Form {
            Picker(selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Label(option.displayName, systemImage: option.systemImage)
                        .tag(option)
                }
            } label: {
                Text("Appearance")
            }
        }
        .formStyle(.grouped)
    }
}
