import SwiftUI

struct CardFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ColumnFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [IssueColumn: CGRect] = [:]
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func reportCardFrame(folderName: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CardFramesPreferenceKey.self,
                    value: [folderName: proxy.frame(in: .named(KanbanCoordinateSpace.name))]
                )
            }
        )
    }

    func reportColumnFrame(column: IssueColumn) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ColumnFramesPreferenceKey.self,
                    value: [column: proxy.frame(in: .named(KanbanCoordinateSpace.name))]
                )
            }
        )
    }
}

enum KanbanCoordinateSpace {
    static let name = "kanban"
}
