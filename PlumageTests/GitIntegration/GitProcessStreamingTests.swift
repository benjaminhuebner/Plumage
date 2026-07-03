import Foundation
import Testing

@testable import Plumage

@Suite("ProductionGitProcessStreamer: environment merge")
struct GitProcessStreamingTests {
    // A bare `process.environment = environment` would drop the inherited PATH
    // while still injecting the token, so both assertions must hold together.
    @Test("injects the token var and preserves the inherited environment (PATH)")
    func mergesInjectedEnvOntoInherited() async throws {
        let streamer = ProductionGitProcessStreamer()
        let (stream, outcome) = try await streamer.stream(
            binaryURL: URL(filePath: "/usr/bin/env"),
            args: [],
            cwd: nil,
            environment: ["PLUMAGE_GH_TOKEN": "sekret-token-value"])

        var lines: [String] = []
        for await line in stream { lines.append(line.text) }
        let result = await outcome()

        #expect(result.exitCode == 0)
        #expect(lines.contains("PLUMAGE_GH_TOKEN=sekret-token-value"))
        #expect(lines.contains { $0.hasPrefix("PATH=") && $0.count > "PATH=".count })
    }

    @Test("a nil environment leaves the inherited environment untouched")
    func nilEnvironmentInherits() async throws {
        let streamer = ProductionGitProcessStreamer()
        let (stream, outcome) = try await streamer.stream(
            binaryURL: URL(filePath: "/usr/bin/env"),
            args: [],
            cwd: nil,
            environment: nil)

        var lines: [String] = []
        for await line in stream { lines.append(line.text) }
        _ = await outcome()

        #expect(lines.contains { $0.hasPrefix("PATH=") })
        #expect(!lines.contains { $0.hasPrefix("PLUMAGE_GH_TOKEN=") })
    }
}
