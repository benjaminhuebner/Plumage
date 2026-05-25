import Foundation

func loadFixture(_ name: String, file: StaticString = #filePath) throws -> String {
    let here = URL(filePath: String(describing: file)).deletingLastPathComponent()
    let url = here.appendingPathComponent("Fixtures").appendingPathComponent(name)
    return try String(contentsOf: url, encoding: .utf8)
}
