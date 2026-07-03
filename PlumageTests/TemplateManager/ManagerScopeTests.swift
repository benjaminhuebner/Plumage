import Testing

@testable import Plumage

@Suite("ManagerScope (#00078)")
struct ManagerScopeTests {
    @Test("storageRoot maps each tier to its loose-file prefix")
    func storageRoots() {
        #expect(ManagerScope.base.storageRoot.isEmpty)
        #expect(ManagerScope.template("macos").storageRoot == "templates/macos")
        #expect(ManagerScope.component("swift-shared").storageRoot == "components/swift-shared")
    }

    @Test("scope(for:) maps a selection to its owning tier")
    func scopeForItem() {
        #expect(ManagerScope.scope(for: .base) == .base)
        #expect(ManagerScope.scope(for: .template("t")) == .template("t"))
        #expect(ManagerScope.scope(for: .sharedComponent("c")) == .component("c"))
    }

    @Test("scopeRelativePath strips the scope root and rejects foreign subtrees")
    func scopeRelativePaths() {
        #expect(ManagerScope.base.scopeRelativePath(of: "docs/x.md") == "docs/x.md")
        let scope = ManagerScope.template("macos")
        #expect(scope.scopeRelativePath(of: "templates/macos")?.isEmpty == true)
        #expect(scope.scopeRelativePath(of: "templates/macos/docs/x.md") == "docs/x.md")
        #expect(scope.scopeRelativePath(of: "templates/macos-sibling/x.md") == nil)
        #expect(scope.scopeRelativePath(of: "docs/x.md") == nil)
    }
}
