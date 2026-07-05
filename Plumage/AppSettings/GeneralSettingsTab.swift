import SwiftUI

struct GeneralSettingsTab: View {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(ChatButtonPlacement.storageKey) private var chatButtonPlacement: ChatButtonPlacement = .floating
    @AppStorage(KeepMacAwakeSetting.storageKey) private var keepMacAwake: Bool =
        KeepMacAwakeSetting.defaultValue

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
            Toggle(isOn: $keepMacAwake) {
                Text("Keep Mac awake while a Claude session is running")
                Text("Only the system stays awake — the display can still sleep.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { _, newValue in
            AppearanceApplier.apply(newValue)
        }
    }
}
