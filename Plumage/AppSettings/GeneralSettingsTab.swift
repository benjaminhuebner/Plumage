import SwiftUI

struct GeneralSettingsTab: View {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(ChatButtonPlacement.storageKey) private var chatButtonPlacement: ChatButtonPlacement = .floating

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
            Picker(selection: $chatButtonPlacement) {
                ForEach(ChatButtonPlacement.allCases) { option in
                    Label(option.displayName, systemImage: option.systemImage)
                        .tag(option)
                }
            } label: {
                Text("Chat Button")
                Text("Status Bar tucks the chat toggle into the bar at the bottom of the window.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { _, newValue in
            AppearanceApplier.apply(newValue)
        }
    }
}
