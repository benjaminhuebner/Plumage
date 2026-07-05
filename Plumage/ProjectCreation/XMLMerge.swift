import Foundation

// Structural merge for layered XML, later variants winning: attributes replace per
// name, a child whose name is unique on both sides merges recursively, others append
// unless identical. Roots must share a name; output re-serializes pretty-printed.
nonisolated enum XMLMerge {
    enum XMLMergeError: Error, Equatable {
        case missingRoot
        case rootMismatch(base: String, overlay: String)
    }

    static func merge(variants: [Data]) throws -> Data {
        let documents = try variants.map { try XMLDocument(data: $0) }
        guard let first = documents.first, let baseRoot = first.rootElement() else {
            throw XMLMergeError.missingRoot
        }
        for document in documents.dropFirst() {
            guard let overlayRoot = document.rootElement() else {
                throw XMLMergeError.missingRoot
            }
            guard overlayRoot.name == baseRoot.name else {
                throw XMLMergeError.rootMismatch(
                    base: baseRoot.name ?? "", overlay: overlayRoot.name ?? "")
            }
            mergeElement(base: baseRoot, overlay: overlayRoot)
        }
        var data = first.xmlData(options: [.nodePrettyPrint])
        data.append(UInt8(ascii: "\n"))
        return data
    }

    private static func mergeElement(base: XMLElement, overlay: XMLElement) {
        for attribute in overlay.attributes ?? [] {
            guard let name = attribute.name, let copy = attribute.copy() as? XMLNode else { continue }
            base.removeAttribute(forName: name)
            base.addAttribute(copy)
        }
        let overlayChildren = (overlay.children ?? []).compactMap { $0 as? XMLElement }
        guard !overlayChildren.isEmpty else {
            let baseHasElements = (base.children ?? []).contains { $0 is XMLElement }
            let text = overlay.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !baseHasElements, !text.isEmpty { base.stringValue = overlay.stringValue }
            return
        }
        for child in overlayChildren {
            guard let name = child.name else { continue }
            if base.elements(forName: name).count == 1, overlay.elements(forName: name).count == 1,
                let match = base.elements(forName: name).first
            {
                mergeElement(base: match, overlay: child)
            } else if let copy = child.copy() as? XMLNode {
                let form = canonicalForm(of: child)
                let duplicate = (base.children ?? [])
                    .compactMap { $0 as? XMLElement }
                    .contains { canonicalForm(of: $0) == form }
                if !duplicate { base.addChild(copy) }
            }
        }
    }

    // Attribute order and surrounding whitespace are serialization noise, not
    // identity — duplicate detection compares a normalized structural form.
    private static func canonicalForm(of element: XMLElement) -> String {
        let attributes = (element.attributes ?? [])
            .compactMap { attribute in
                attribute.name.map { "\($0)=\(attribute.stringValue ?? "")" }
            }
            .sorted()
        let children = (element.children ?? []).compactMap { $0 as? XMLElement }
        let content =
            children.isEmpty
            ? (element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : children.map(canonicalForm(of:)).joined()
        return "<\(element.name ?? "")|\(attributes.joined(separator: " "))|\(content)>"
    }
}
