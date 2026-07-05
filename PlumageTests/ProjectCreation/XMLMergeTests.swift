import Foundation
import Testing

@testable import Plumage

@Suite("XMLMerge")
struct XMLMergeTests {
    private func merge(_ variants: [String]) throws -> String {
        String(decoding: try XMLMerge.merge(variants: variants.map { Data($0.utf8) }), as: UTF8.self)
    }

    @Test("Unambiguous same-named children merge recursively; new children append")
    func childrenMergeAndAppend() throws {
        let merged = try merge([
            "<config><logging><level>info</level></logging></config>",
            "<config><logging><format>json</format></logging><cache>on</cache></config>",
        ])
        #expect(merged.contains("<level>info</level>"))
        #expect(merged.contains("<format>json</format>"))
        #expect(merged.contains("<cache>on</cache>"))
    }

    @Test("A later attribute replaces the base's; others stay")
    func attributesLaterWins() throws {
        let merged = try merge([
            #"<config version="1" keep="yes"/>"#,
            #"<config version="2"/>"#,
        ])
        #expect(merged.contains(#"version="2""#))
        #expect(merged.contains(#"keep="yes""#))
    }

    @Test("A later text-only element replaces the base text")
    func textLaterWins() throws {
        let merged = try merge([
            "<config><name>old</name></config>",
            "<config><name>new</name></config>",
        ])
        #expect(merged.contains("<name>new</name>"))
        #expect(!merged.contains("old"))
    }

    @Test("Repeated same-named elements append without duplicating identical ones")
    func repeatedElementsAppendDedup() throws {
        let merged = try merge([
            "<rules><rule>a</rule><rule>b</rule></rules>",
            "<rules><rule>a</rule><rule>c</rule></rules>",
        ])
        #expect(merged.components(separatedBy: "<rule>a</rule>").count == 2)  // exactly once
        #expect(merged.contains("<rule>b</rule>"))
        #expect(merged.contains("<rule>c</rule>"))
    }

    @Test("Attribute order and indentation don't defeat duplicate detection")
    func attributeOrderInsensitiveDedup() throws {
        let merged = try merge([
            "<rules>\n  <rule name=\"a\" level=\"1\">x</rule>\n  <rule name=\"b\" level=\"2\">y</rule>\n</rules>",
            "<rules><rule level=\"1\" name=\"a\">x</rule></rules>",
        ])
        #expect(merged.components(separatedBy: "name=\"a\"").count == 2)  // exactly once
        #expect(merged.contains("name=\"b\""))
    }

    @Test("Mismatched root names throw")
    func rootMismatchThrows() {
        #expect(throws: XMLMerge.XMLMergeError.rootMismatch(base: "a", overlay: "b")) {
            try XMLMerge.merge(variants: [Data("<a/>".utf8), Data("<b/>".utf8)])
        }
    }

    @Test("Invalid XML throws instead of guessing")
    func invalidXMLThrows() {
        #expect(throws: (any Error).self) {
            try XMLMerge.merge(variants: [Data("<a>".utf8), Data("<a/>".utf8)])
        }
    }
}
