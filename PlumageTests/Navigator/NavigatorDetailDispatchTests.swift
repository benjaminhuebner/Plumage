import Foundation
import Testing

@testable import Plumage

@Suite("NavigatorDetailDispatch")
struct NavigatorDetailDispatchTests {
    @Test(
        "Markdown files route to DocEditor",
        arguments: [
            ".claude/docs/PROJECT.md",
            ".claude/CLAUDE.md",
            ".claude/agents/team/lead.md",
            ".plumage/notes.md",
        ]
    )
    func markdownRoutesToDoc(path: String) {
        #expect(NavigatorDetailDispatch.detailViewKind(for: path) == .doc)
    }

    @Test(
        "Editable JSON basenames route to DocEditor",
        arguments: [
            ".claude/settings.json",
            ".claude/settings.local.json",
        ]
    )
    func editableJSONRoutesToDoc(path: String) {
        #expect(NavigatorDetailDispatch.detailViewKind(for: path) == .doc)
    }

    @Test("Generic JSON files route to FileInfo (not DocEditor)")
    func genericJSONRoutesToInfo() {
        #expect(NavigatorDetailDispatch.detailViewKind(for: ".mcp.json") == .info)
        #expect(NavigatorDetailDispatch.detailViewKind(for: ".plumage/config.json") == .info)
    }

    @Test(
        "Code and Xcode bundles route to FileInfo",
        arguments: [
            ".claude/skills/foo/script.swift",
            "Some.xcodeproj",
            "App.xcworkspace",
        ]
    )
    func codeRoutesToInfo(path: String) {
        #expect(NavigatorDetailDispatch.detailViewKind(for: path) == .info)
    }

    @Test(
        "Image extensions route to ImagePreview",
        arguments: [
            ".claude/assets/icon.png",
            ".claude/screenshots/cover.JPG",
            ".plumage/preview.HEIC",
            ".claude/diagram.svg.gif",
        ]
    )
    func imagesRouteToImage(path: String) {
        #expect(NavigatorDetailDispatch.detailViewKind(for: path) == .image)
    }

    @Test("Unknown binaries fall through to FileInfo")
    func binariesRouteToInfo() {
        #expect(NavigatorDetailDispatch.detailViewKind(for: ".claude/hooks/lint") == .info)
        #expect(NavigatorDetailDispatch.detailViewKind(for: ".plumage/cache.bin") == .info)
    }

    @Test("Case-insensitive extension matching")
    func caseInsensitive() {
        #expect(NavigatorDetailDispatch.detailViewKind(for: "README.MD") == .doc)
        #expect(NavigatorDetailDispatch.detailViewKind(for: "diagram.PNG") == .image)
    }
}
