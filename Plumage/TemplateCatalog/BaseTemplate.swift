import Foundation

// The first tier: assets unconditionally part of every template (the base
// `CLAUDE.md` skeleton and the workflow hooks). The remaining global assets
// (Plumage skills, issue template) are scaffolded straight from the
// bundled tree and don't vary by kind, so they aren't modelled per-field here;
// the Template Manager lists them from the bundle when "Base" is selected.
nonisolated struct BaseTemplate: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let claudeMdRelativePath: String
    let workflowHooks: [String]
}
