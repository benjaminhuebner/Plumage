import Foundation

// Merges missing hook groups into an existing settings.json text-surgically: a
// decode/re-encode round-trip would reorder keys and reformat hand-edited bytes,
// so everything outside the inserted groups stays byte-identical.
nonisolated enum SettingsHookMerge {
    enum Outcome: Equatable {
        case unchanged
        case merged(Data, addedCommands: [String])
        case unparseable
    }

    static func merge(existing: Data, generated: Data) -> Outcome {
        guard
            let existingObj = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any]
        else { return .unparseable }
        // A present `hooks` key that is not an event-keyed object can't take a merge.
        if let hooks = existingObj["hooks"], !(hooks is [String: Any]) { return .unparseable }
        guard
            let generatedObj = (try? JSONSerialization.jsonObject(with: generated)) as? [String: Any],
            let generatedHooks = generatedObj["hooks"] as? [String: [[String: Any]]]
        else { return .unchanged }

        let existingHooks = existingObj["hooks"] as? [String: Any] ?? [:]
        var missingByEvent: [(event: String, groups: [[String: Any]])] = []
        var addedCommands: [String] = []
        for event in generatedHooks.keys.sorted() {
            // Dedup per event: the same command under a different event is a
            // distinct wiring, not a duplicate.
            let existingCommands = commandSet(forEvent: existingHooks[event])
            let missing = (generatedHooks[event] ?? []).filter { group in
                let commands = commands(in: group)
                return !commands.isEmpty && commands.allSatisfy { !existingCommands.contains($0) }
            }
            guard !missing.isEmpty else { continue }
            missingByEvent.append((event, missing))
            addedCommands += missing.flatMap(commands(in:))
        }
        guard !missingByEvent.isEmpty else { return .unchanged }
        guard let merged = insert(missingByEvent, into: existing) else { return .unparseable }
        return .merged(merged, addedCommands: addedCommands)
    }

    private static func commandSet(forEvent value: Any?) -> Set<String> {
        var result: Set<String> = []
        for group in value as? [[String: Any]] ?? [] { result.formUnion(commands(in: group)) }
        return result
    }

    private static func commands(in group: [String: Any]) -> [String] {
        ((group["hooks"] as? [[String: Any]]) ?? []).compactMap { $0["command"] as? String }
    }

    // MARK: - Surgical insertion

    private static let unit = "  "

    private static func insert(
        _ missingByEvent: [(event: String, groups: [[String: Any]])], into existing: Data
    ) -> Data? {
        let bytes = [UInt8](existing)
        var cursor = 0
        skipWhitespace(bytes, &cursor)
        guard cursor < bytes.count, bytes[cursor] == UInt8(ascii: "{") else { return nil }
        // The exact top-level object span — trailing bytes (final newline) stay outside.
        var topEnd = cursor
        skipValue(bytes, &topEnd)
        let topRange = cursor..<topEnd
        guard let topEntries = entries(inObject: topRange, of: bytes) else { return nil }

        var insertions: [(at: Int, text: String)] = []
        if let hooksEntry = topEntries.first(where: { $0.key == "hooks" }) {
            let hookIndent = lineIndent(before: hooksEntry.keyStart, in: bytes)
            let eventIndent = hookIndent + unit
            guard let eventEntries = entries(inObject: hooksEntry.valueRange, of: bytes) else {
                return nil
            }
            var newEvents: [(event: String, groups: [[String: Any]])] = []
            for missing in missingByEvent {
                if let eventEntry = eventEntries.first(where: { $0.key == missing.event }) {
                    guard
                        let insertion = arrayInsertion(
                            groups: missing.groups, arrayRange: eventEntry.valueRange, of: bytes,
                            eventIndent: lineIndent(before: eventEntry.keyStart, in: bytes))
                    else { return nil }
                    insertions.append(insertion)
                } else {
                    newEvents.append(missing)
                }
            }
            if !newEvents.isEmpty {
                guard
                    let insertion = objectInsertion(
                        entryTexts: newEvents.map { entryText($0, indent: eventIndent) },
                        objectRange: hooksEntry.valueRange, of: bytes, entryIndent: eventIndent)
                else { return nil }
                insertions.append(insertion)
            }
        } else {
            let entryBody = missingByEvent.map { entryText($0, indent: unit + unit) }
                .joined(separator: ",\n" + unit + unit)
            let hooksEntryText = "\"hooks\": {\n\(unit + unit)\(entryBody)\n\(unit)}"
            guard
                let insertion = objectInsertion(
                    entryTexts: [hooksEntryText], objectRange: topRange, of: bytes,
                    entryIndent: unit)
            else { return nil }
            insertions.append(insertion)
        }

        var result = existing
        for insertion in insertions.sorted(by: { $0.at > $1.at }) {
            result.insert(contentsOf: Array(insertion.text.utf8), at: insertion.at)
        }
        return result
    }

    // Append serialized groups inside an existing event array, before its `]`.
    private static func arrayInsertion(
        groups: [[String: Any]], arrayRange: Range<Int>, of bytes: [UInt8], eventIndent: String
    ) -> (at: Int, text: String)? {
        let close = arrayRange.upperBound - 1
        guard close >= arrayRange.lowerBound, bytes[close] == UInt8(ascii: "]") else { return nil }
        let groupIndent = eventIndent + unit
        guard let body = renderGroups(groups, indent: groupIndent) else { return nil }
        var last = close - 1
        while last > arrayRange.lowerBound, isWhitespace(bytes[last]) { last -= 1 }
        if bytes[last] == UInt8(ascii: "[") {
            return (close, "\n\(body)\n\(eventIndent)")
        }
        return (last + 1, ",\n\(body)")
    }

    // Append rendered entries inside an object, before its `}`.
    private static func objectInsertion(
        entryTexts: [String], objectRange: Range<Int>, of bytes: [UInt8], entryIndent: String
    ) -> (at: Int, text: String)? {
        let close = objectRange.upperBound - 1
        guard close >= objectRange.lowerBound, bytes[close] == UInt8(ascii: "}") else { return nil }
        let joined = entryTexts.joined(separator: ",\n" + entryIndent)
        var last = close - 1
        while last > objectRange.lowerBound, isWhitespace(bytes[last]) { last -= 1 }
        if bytes[last] == UInt8(ascii: "{") {
            let outerIndent = String(entryIndent.dropLast(unit.count))
            return (close, "\n\(entryIndent)\(joined)\n\(outerIndent)")
        }
        return (last + 1, ",\n\(entryIndent)\(joined)")
    }

    private static func entryText(
        _ missing: (event: String, groups: [[String: Any]]), indent: String
    ) -> String {
        let body = renderGroups(missing.groups, indent: indent + unit) ?? ""
        return "\"\(missing.event)\": [\n\(body)\n\(indent)]"
    }

    private static func renderGroups(_ groups: [[String: Any]], indent: String) -> String? {
        let rendered = groups.compactMap { group -> String? in
            guard
                let data = try? JSONSerialization.data(
                    withJSONObject: group, options: [.prettyPrinted, .sortedKeys])
            else { return nil }
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .map { indent + $0 }
                .joined(separator: "\n")
        }
        guard rendered.count == groups.count else { return nil }
        return rendered.joined(separator: ",\n")
    }

    // MARK: - Minimal JSON scanner

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func skipWhitespace(_ bytes: [UInt8], _ cursor: inout Int) {
        while cursor < bytes.count, isWhitespace(bytes[cursor]) { cursor += 1 }
    }

    // `cursor` at the opening quote; leaves `cursor` past the closing quote.
    private static func skipString(_ bytes: [UInt8], _ cursor: inout Int) {
        cursor += 1
        while cursor < bytes.count {
            if bytes[cursor] == UInt8(ascii: "\\") {
                cursor += 2
                continue
            }
            if bytes[cursor] == UInt8(ascii: "\"") {
                cursor += 1
                return
            }
            cursor += 1
        }
    }

    // `cursor` at a value start; leaves `cursor` past the value end.
    private static func skipValue(_ bytes: [UInt8], _ cursor: inout Int) {
        skipWhitespace(bytes, &cursor)
        guard cursor < bytes.count else { return }
        switch bytes[cursor] {
        case UInt8(ascii: "\""):
            skipString(bytes, &cursor)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            while cursor < bytes.count {
                switch bytes[cursor] {
                case UInt8(ascii: "\""):
                    skipString(bytes, &cursor)
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 {
                        cursor += 1
                        return
                    }
                default:
                    break
                }
                cursor += 1
            }
        default:
            while cursor < bytes.count, bytes[cursor] != UInt8(ascii: ","),
                bytes[cursor] != UInt8(ascii: "}"), bytes[cursor] != UInt8(ascii: "]"),
                !isWhitespace(bytes[cursor])
            { cursor += 1 }
        }
    }

    // The key/value entries of the object spanning `range` (whose first non-ws byte
    // must be `{`), or nil on any structural surprise.
    private static func entries(
        inObject range: Range<Int>, of bytes: [UInt8]
    ) -> [(key: String, keyStart: Int, valueRange: Range<Int>)]? {
        var cursor = range.lowerBound
        skipWhitespace(bytes, &cursor)
        guard cursor < range.upperBound, bytes[cursor] == UInt8(ascii: "{") else { return nil }
        cursor += 1
        var result: [(key: String, keyStart: Int, valueRange: Range<Int>)] = []
        while true {
            skipWhitespace(bytes, &cursor)
            guard cursor < range.upperBound else { return nil }
            if bytes[cursor] == UInt8(ascii: "}") { return result }
            guard bytes[cursor] == UInt8(ascii: "\"") else { return nil }
            let keyStart = cursor
            var keyEnd = cursor
            skipString(bytes, &keyEnd)
            let key = String(decoding: bytes[(keyStart + 1)..<(keyEnd - 1)], as: UTF8.self)
            cursor = keyEnd
            skipWhitespace(bytes, &cursor)
            guard cursor < range.upperBound, bytes[cursor] == UInt8(ascii: ":") else { return nil }
            cursor += 1
            skipWhitespace(bytes, &cursor)
            let valueStart = cursor
            skipValue(bytes, &cursor)
            result.append((key, keyStart, valueStart..<cursor))
            skipWhitespace(bytes, &cursor)
            if cursor < range.upperBound, bytes[cursor] == UInt8(ascii: ",") { cursor += 1 }
        }
    }

    private static func lineIndent(before index: Int, in bytes: [UInt8]) -> String {
        var start = index
        while start > 0, bytes[start - 1] != 0x0A { start -= 1 }
        let ws = bytes[start..<index].prefix { $0 == 0x20 || $0 == 0x09 }
        return String(decoding: ws, as: UTF8.self)
    }
}
