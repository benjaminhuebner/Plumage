import Foundation

struct SaveAlert: Identifiable {
    let id = UUID()
    let message: String
    let kind: Kind

    enum Kind {
        case pop
        case saveOnly
    }
}
