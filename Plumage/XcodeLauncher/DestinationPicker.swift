import SwiftUI

struct DestinationPicker: View {
    @Bindable var model: XcodeRunModel

    var body: some View {
        Menu {
            if model.destinationList.macSupported {
                Section("My Mac") {
                    destinationButton(.myMac)
                }
            }
            ForEach(model.destinationList.simulatorGroups, id: \.runtime) { group in
                Section(group.runtime.displayName) {
                    ForEach(group.simulators) { sim in
                        destinationButton(
                            .simulator(
                                udid: sim.udid,
                                name: sim.name,
                                runtimeDisplayName: group.runtime.displayName
                            )
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: destinationIcon)
                Text(model.selectedDestination?.displayName ?? "No destination")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
        }
        .help("Destination")
        .accessibilityLabel("Destination: \(model.selectedDestination?.displayName ?? "None")")
        .disabled(model.destinationList.isEmpty)
    }

    @ViewBuilder
    private func destinationButton(_ destination: XcodeDestination) -> some View {
        Button {
            model.selectDestination(destination)
        } label: {
            if destination == model.selectedDestination {
                Label(destination.displayName, systemImage: "checkmark")
            } else {
                Text(destination.displayName)
            }
        }
    }

    private var destinationIcon: String {
        switch model.selectedDestination {
        case .myMac: return "macbook"
        case .simulator: return "iphone"
        case nil: return "questionmark.square.dashed"
        }
    }
}
