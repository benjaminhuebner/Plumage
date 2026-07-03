import Foundation
import Testing

@testable import Plumage

@Suite("SemanticVersion.parse")
struct SemanticVersionParseTests {
    @Test("plain semver")
    func plain() {
        let parsed = SemanticVersion.parse("1.2.3")
        #expect(parsed == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test("trailing whitespace / newline")
    func trailing() {
        let parsed = SemanticVersion.parse("1.2.3\n")
        #expect(parsed == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test("with parenthetical suffix")
    func withParenSuffix() {
        let parsed = SemanticVersion.parse("1.2.3 (Claude Code)")
        #expect(parsed == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test("inside npm-style identifier")
    func npmIdentifier() {
        let parsed = SemanticVersion.parse("@anthropic-ai/claude-code/1.2.3 darwin-arm64")
        #expect(parsed == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test("returns nil on garbage")
    func garbage() {
        #expect(SemanticVersion.parse("hello world") == nil)
        #expect(SemanticVersion.parse("") == nil)
        #expect(SemanticVersion.parse("1.2") == nil)
    }

    @Test("description matches dot form")
    func description() {
        let version = SemanticVersion(major: 1, minor: 0, patch: 5)
        #expect(version.description == "1.0.5")
    }
}

@Suite("SupportedClaudeVersion.inSupportedRange")
struct SupportedClaudeVersionTests {
    @Test("majors 1 and 2 are supported")
    func currentMajorsSupported() {
        #expect(SupportedClaudeVersion.inSupportedRange(.init(major: 1, minor: 0, patch: 0)))
        #expect(SupportedClaudeVersion.inSupportedRange(.init(major: 1, minor: 99, patch: 99)))
        #expect(SupportedClaudeVersion.inSupportedRange(.init(major: 2, minor: 0, patch: 0)))
        #expect(SupportedClaudeVersion.inSupportedRange(.init(major: 2, minor: 1, patch: 142)))
    }

    @Test("major 0 unsupported")
    func majorZeroUnsupported() {
        #expect(!SupportedClaudeVersion.inSupportedRange(.init(major: 0, minor: 9, patch: 0)))
    }

    @Test("major 3 unsupported until bumped")
    func nextMajorUnsupported() {
        #expect(!SupportedClaudeVersion.inSupportedRange(.init(major: 3, minor: 0, patch: 0)))
    }
}

@Suite("StatusIndicatorModel.detect")
@MainActor
struct StatusIndicatorModelTests {
    @Test("ok state when in supported range")
    func okState() async {
        let model = StatusIndicatorModel()
        let check = VersionCheck(
            version: SemanticVersion(major: 1, minor: 2, patch: 3),
            binaryURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            inSupportedRange: true
        )
        let mock = MockProcessRunner(detectOutcome: .success(check))
        await model.detect(using: mock)
        #expect(model.state == .ok(check))
    }

    @Test("unsupported state when out of range")
    func unsupportedState() async {
        let model = StatusIndicatorModel()
        let check = VersionCheck(
            version: SemanticVersion(major: 0, minor: 9, patch: 0),
            binaryURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            inSupportedRange: false
        )
        let mock = MockProcessRunner(detectOutcome: .success(check))
        await model.detect(using: mock)
        #expect(model.state == .unsupported(check))
    }

    @Test("binaryNotFound maps to .missing")
    func missingState() async {
        let model = StatusIndicatorModel()
        let mock = MockProcessRunner(detectOutcome: .failure(.binaryNotFound))
        await model.detect(using: mock)
        #expect(model.state == .missing)
    }

    @Test("parseError maps to .failed(.parseError)")
    func parseErrorState() async {
        let model = StatusIndicatorModel()
        let mock = MockProcessRunner(detectOutcome: .failure(.parseError("junk")))
        await model.detect(using: mock)
        #expect(model.state == .failed(.parseError("junk")))
    }

    @Test("spawnFailed maps to .failed(.spawnFailed)")
    func spawnFailedState() async {
        let model = StatusIndicatorModel()
        let mock = MockProcessRunner(detectOutcome: .failure(.spawnFailed("boom")))
        await model.detect(using: mock)
        #expect(model.state == .failed(.spawnFailed("boom")))
    }

    @Test("nonZeroExit maps to .failed(.nonZeroExit)")
    func nonZeroExitState() async {
        let model = StatusIndicatorModel()
        let mock = MockProcessRunner(
            detectOutcome: .failure(.nonZeroExit(code: 127, stderr: "not found"))
        )
        await model.detect(using: mock)
        #expect(model.state == .failed(.nonZeroExit(code: 127, stderr: "not found")))
    }
}
