import Foundation

nonisolated enum SupportedClaudeVersion {
    static let supportedMajors: ClosedRange<Int> = 1...1

    static func inSupportedRange(_ version: SemanticVersion) -> Bool {
        supportedMajors.contains(version.major)
    }

    static var supportedRangeDescription: String {
        let lower = supportedMajors.lowerBound
        let upper = supportedMajors.upperBound
        return lower == upper ? "\(lower).x" : "\(lower).x – \(upper).x"
    }
}
