import Foundation
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
}
