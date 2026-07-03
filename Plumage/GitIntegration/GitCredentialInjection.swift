import Foundation

nonisolated struct GitPushCredential: Sendable, Equatable {
    let login: String
    let token: String
}

// The token travels only in a private env var, never in argv, and no global git
// config or osxkeychain state is touched.
nonisolated enum GitCredentialInjection {
    static let tokenEnvVar = "PLUMAGE_GH_TOKEN"

    static func arguments(login: String) -> [String] {
        [
            // Empty first helper clears any inherited helper (osxkeychain, …) so
            // only our inline helper answers; it echoes the token from the env var.
            "-c", "credential.helper=",
            "-c",
            "credential.helper=!f() { echo username=\(shellSingleQuoted(login)); echo password=\"$\(tokenEnvVar)\"; }; f",
        ]
    }

    static func environment(token: String) -> [String: String] {
        [tokenEnvVar: token, "GIT_TERMINAL_PROMPT": "0"]
    }

    // Single-quote for /bin/sh so a login carrying shell metacharacters can't
    // break out of the inline helper; git still receives the literal value.
    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
