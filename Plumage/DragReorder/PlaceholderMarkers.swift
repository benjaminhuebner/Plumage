import Foundation

nonisolated func placeholderIndex(for position: RowDropPosition?, rowIDs: [String]) -> Int? {
    guard let position else { return nil }
    switch position {
    case .empty:
        return rowIDs.count
    case .before(let id):
        return rowIDs.firstIndex(of: id)
    case .after(let id):
        guard let index = rowIDs.firstIndex(of: id) else { return nil }
        return index + 1
    }
}

// Id-based markers so a ForEach can iterate its items directly without an
// `enumerated()` allocation on every drag frame. `beforeID` names the row
// the placeholder appears above; `atEnd` covers index == items.count.
nonisolated struct PlaceholderMarkers: Equatable {
    let beforeID: String?
    let atEnd: Bool

    init<Items: RandomAccessCollection>(
        placeholderIndex: Int?, items: Items, id: (Items.Element) -> String
    ) {
        guard let placeholderIndex else {
            beforeID = nil
            atEnd = false
            return
        }
        if placeholderIndex < items.count {
            let index = items.index(items.startIndex, offsetBy: placeholderIndex)
            beforeID = id(items[index])
            atEnd = false
        } else {
            beforeID = nil
            atEnd = placeholderIndex == items.count
        }
    }
}
