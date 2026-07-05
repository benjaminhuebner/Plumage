import SwiftUI

struct UsageSettingsTab: View {
    @AppStorage(UsageDisplaySettings.showUsageKey) private var showUsage: Bool =
        UsageDisplaySettings.showUsageDefault
    @AppStorage(UsageDisplaySettings.showFiveHourKey) private var showFiveHour: Bool =
        UsageDisplaySettings.showFiveHourDefault
    @AppStorage(UsageDisplaySettings.showSevenDayKey) private var showSevenDay: Bool =
        UsageDisplaySettings.showSevenDayDefault

    var body: some View {
        Form {
            Toggle(isOn: $showUsage) {
                Text("Show usage in the status bar")
                Text("A compact pill by the status indicator; click it for the full breakdown.")
            }
            Section("Windows") {
                Toggle("5-hour window", isOn: $showFiveHour)
                Toggle("7-day window", isOn: $showSevenDay)
            }
            .disabled(!showUsage)
        }
        .formStyle(.grouped)
    }
}
