import Foundation
import Testing

@testable import Plumage

@Suite("GitCredentialInjection")
struct GitCredentialInjectionTests {
    @Test("the token value never appears in the argument list")
    func tokenNeverInArgv() {
        let args = GitCredentialInjection.arguments(login: "octocat")
        let secret = "ghp_TOPSECRET_value_1234567890"
        for arg in args {
            #expect(!arg.contains(secret))
        }
        let environment = GitCredentialInjection.environment(token: secret)
        #expect(environment[GitCredentialInjection.tokenEnvVar] == secret)
    }

    @Test("arguments clear inherited helpers, carry the login, and reference the env var")
    func argumentShape() {
        let args = GitCredentialInjection.arguments(login: "octocat")
        #expect(Array(args.prefix(2)) == ["-c", "credential.helper="])
        #expect(args.contains { $0.contains("username='octocat'") })
        #expect(args.contains { $0.contains("$\(GitCredentialInjection.tokenEnvVar)") })
    }

    @Test("a login carrying shell metacharacters is single-quoted, not executed")
    func maliciousLoginIsQuoted() throws {
        let args = GitCredentialInjection.arguments(login: "x'; rm -rf ~ #")
        let helper = try #require(args.last)
        // The injected metacharacters survive only inside a single-quoted string;
        // the ' in the login is escaped as the standard '\'' close-escape-reopen.
        #expect(helper.contains("username='x'\\''; rm -rf ~ #'"))
    }

    @Test("environment disables terminal prompts")
    func environmentDisablesPrompt() {
        let environment = GitCredentialInjection.environment(token: "irrelevant")
        #expect(environment["GIT_TERMINAL_PROMPT"] == "0")
    }
}
