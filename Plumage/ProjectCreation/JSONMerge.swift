import Foundation

// Deep merge for layered JSON, later variants winning: objects merge key-wise,
// arrays append missing elements, scalars and type conflicts take the later value.
// Output re-serializes (pretty, sorted keys) — merged files are generated artifacts.
nonisolated enum JSONMerge {
    static func merge(variants: [Data]) throws -> Data {
        let values = try variants.map {
            try JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed])
        }
        guard let first = values.first else { return Data() }
        let merged = values.dropFirst().reduce(first, mergeValue)
        var data = try JSONSerialization.data(
            withJSONObject: merged,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        data.append(UInt8(ascii: "\n"))
        return data
    }

    static func mergeValue(_ base: Any, _ overlay: Any) -> Any {
        if let baseObject = base as? [String: Any], let overlayObject = overlay as? [String: Any] {
            var result = baseObject
            for (key, value) in overlayObject {
                result[key] = result[key].map { mergeValue($0, value) } ?? value
            }
            return result
        }
        if let baseArray = base as? [Any], let overlayArray = overlay as? [Any] {
            var result = baseArray
            for element in overlayArray where !result.contains(where: { jsonEqual($0, element) }) {
                result.append(element)
            }
            return result
        }
        return overlay
    }

    // NSNumber.isEqual conflates booleans with numbers (true == 1), so equality
    // checks the CFBoolean bridge first and recurses through containers itself.
    private static func jsonEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if let lhsNumber = lhs as? NSNumber, let rhsNumber = rhs as? NSNumber {
            return isBoolean(lhsNumber) == isBoolean(rhsNumber) && lhsNumber.isEqual(rhsNumber)
        }
        if let lhsString = lhs as? String, let rhsString = rhs as? String {
            return lhsString == rhsString
        }
        if let lhsObject = lhs as? [String: Any], let rhsObject = rhs as? [String: Any] {
            return lhsObject.count == rhsObject.count
                && lhsObject.allSatisfy { key, value in
                    rhsObject[key].map { jsonEqual(value, $0) } ?? false
                }
        }
        if let lhsArray = lhs as? [Any], let rhsArray = rhs as? [Any] {
            return lhsArray.count == rhsArray.count
                && zip(lhsArray, rhsArray).allSatisfy { jsonEqual($0, $1) }
        }
        return lhs is NSNull && rhs is NSNull
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
