import Testing

@testable import Plumage

@Suite("UserTemplateKind hook extensions")
struct UserTemplateKindTests {
    // MARK: - fileName

    @Test("A bare hook name defaults to .sh")
    func bareNameDefaultsToSh() {
        #expect(UserTemplateKind.hook.fileName(forSanitized: "my-hook") == "my-hook.sh")
    }

    @Test("A typed .sh extension is kept once, not doubled")
    func typedShKept() {
        #expect(UserTemplateKind.hook.fileName(forSanitized: "my-hook.sh") == "my-hook.sh")
    }

    @Test("A typed .py extension is kept literally")
    func typedPyKept() {
        #expect(UserTemplateKind.hook.fileName(forSanitized: "my-hook.py") == "my-hook.py")
    }

    @Test("An unknown extension is kept literally")
    func unknownExtensionKept() {
        #expect(UserTemplateKind.hook.fileName(forSanitized: "my-hook.rb") == "my-hook.rb")
    }

    // MARK: - starter shebang

    @Test("A .sh / bare hook starts with #!/bin/sh")
    func shStarter() {
        #expect(UserTemplateKind.hook.starter(forLeaf: "my-hook.sh") == "#!/bin/sh\n")
    }

    @Test("A .py hook starts with the python3 shebang")
    func pyStarter() {
        #expect(UserTemplateKind.hook.starter(forLeaf: "my-hook.py") == "#!/usr/bin/env python3\n")
    }

    @Test("An unknown-extension hook has an empty starter")
    func unknownStarterEmpty() {
        #expect(UserTemplateKind.hook.starter(forLeaf: "my-hook.rb").isEmpty)
    }

    // MARK: - hookBaseName (extension-agnostic recognition)

    @Test("Any file directly under hooks/ is recognized as a hook")
    func recognitionExtensionAgnostic() {
        #expect(UserTemplateKind.hookBaseName(forRelativePath: "hooks/my-hook.sh") == "my-hook")
        #expect(UserTemplateKind.hookBaseName(forRelativePath: "hooks/my-hook.py") == "my-hook")
        #expect(UserTemplateKind.hookBaseName(forRelativePath: "hooks/my-hook.rb") == "my-hook")
        #expect(UserTemplateKind.hookBaseName(forRelativePath: "hooks/my-hook") == "my-hook")
    }

    @Test("A non-hooks path is not a hook")
    func nonHooksRejected() {
        #expect(UserTemplateKind.hookBaseName(forRelativePath: "docs/readme.md") == nil)
        #expect(UserTemplateKind.hookBaseName(forRelativePath: "hooks/") == nil)
    }

    // MARK: - stored-name resolution

    @Test("hookFileName defaults a bare stored name to .sh, keeps a typed extension")
    func storedNameResolution() {
        #expect(UserTemplateKind.hookFileName(forStoredName: "legacy") == "legacy.sh")
        #expect(UserTemplateKind.hookFileName(forStoredName: "legacy.sh") == "legacy.sh")
        #expect(UserTemplateKind.hookFileName(forStoredName: "modern.py") == "modern.py")
    }

    @Test("hookShebang maps known extensions, empties the rest")
    func shebangMapping() {
        #expect(UserTemplateKind.hookShebang(forFileName: "h.sh") == "#!/bin/sh\n")
        #expect(UserTemplateKind.hookShebang(forFileName: "h") == "#!/bin/sh\n")
        #expect(UserTemplateKind.hookShebang(forFileName: "h.py") == "#!/usr/bin/env python3\n")
        #expect(UserTemplateKind.hookShebang(forFileName: "h.rb").isEmpty)
    }
}
