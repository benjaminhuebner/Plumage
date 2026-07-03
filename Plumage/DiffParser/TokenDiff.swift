nonisolated public struct TokenChanges: Sendable, Equatable {
    public let removed: [Range<String.Index>]
    public let inserted: [Range<String.Index>]

    public init(removed: [Range<String.Index>], inserted: [Range<String.Index>]) {
        self.removed = removed
        self.inserted = inserted
    }
}

nonisolated public enum TokenDiff {
    public static let defaultLengthCap = 2000
    public static let defaultTokenCap = 256

    public static func changes(
        old: String,
        new: String,
        lengthCap: Int = defaultLengthCap,
        tokenCap: Int = defaultTokenCap
    ) -> TokenChanges? {
        guard old.count <= lengthCap, new.count <= lengthCap else { return nil }
        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)
        guard oldTokens.count <= tokenCap, newTokens.count <= tokenCap else { return nil }

        let kept = longestCommonSubsequence(oldTokens, newTokens)
        return TokenChanges(
            removed: mergedRanges(of: oldTokens, excluding: kept.old),
            inserted: mergedRanges(of: newTokens, excluding: kept.new)
        )
    }

    private struct Token {
        let text: Substring
        let range: Range<String.Index>
    }

    private static func tokenize(_ content: String) -> [Token] {
        var tokens: [Token] = []
        var index = content.startIndex
        while index < content.endIndex {
            let character = content[index]
            let start = index
            if character.isWhitespace {
                while index < content.endIndex, content[index].isWhitespace {
                    index = content.index(after: index)
                }
            } else if isWordCharacter(character) {
                while index < content.endIndex, isWordCharacter(content[index]) {
                    index = content.index(after: index)
                }
            } else {
                index = content.index(after: index)
            }
            tokens.append(Token(text: content[start..<index], range: start..<index))
        }
        return tokens
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func longestCommonSubsequence(
        _ old: [Token],
        _ new: [Token]
    ) -> (old: Set<Int>, new: Set<Int>) {
        let oldCount = old.count
        let newCount = new.count
        var table = Array(repeating: Array(repeating: 0, count: newCount + 1), count: oldCount + 1)
        for oldIndex in stride(from: oldCount - 1, through: 0, by: -1) {
            for newIndex in stride(from: newCount - 1, through: 0, by: -1) {
                if old[oldIndex].text == new[newIndex].text {
                    table[oldIndex][newIndex] = table[oldIndex + 1][newIndex + 1] + 1
                } else {
                    table[oldIndex][newIndex] = max(
                        table[oldIndex + 1][newIndex],
                        table[oldIndex][newIndex + 1]
                    )
                }
            }
        }

        var keptOld = Set<Int>()
        var keptNew = Set<Int>()
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldCount, newIndex < newCount {
            if old[oldIndex].text == new[newIndex].text {
                keptOld.insert(oldIndex)
                keptNew.insert(newIndex)
                oldIndex += 1
                newIndex += 1
            } else if table[oldIndex + 1][newIndex] >= table[oldIndex][newIndex + 1] {
                oldIndex += 1
            } else {
                newIndex += 1
            }
        }
        return (keptOld, keptNew)
    }

    private static func mergedRanges(
        of tokens: [Token],
        excluding kept: Set<Int>
    ) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        for (index, token) in tokens.enumerated() where !kept.contains(index) {
            if let last = result.last, last.upperBound == token.range.lowerBound {
                result[result.count - 1] = last.lowerBound..<token.range.upperBound
            } else {
                result.append(token.range)
            }
        }
        return result
    }
}
