import Foundation

// Plumage-local slash commands: handled in-app instead of being forwarded to
// the claude subprocess (whose REPL-only commands need a TTY).
extension ClaudeSession {
    // Returns true when the text was consumed as a Plumage-local command.
    func handleIfLocalCommand(_ trimmed: String) -> Bool {
        guard Self.looksLikeLocalCommand(trimmed) else { return false }
        handleLocalSlashCommand(trimmed)
        return true
    }

    // A Plumage slash command is a single leading-slash token with no interior
    // slashes ("/clear"). A Finder-dropped absolute path also starts with "/" but
    // carries interior slashes — route those to claude as a normal message.
    private nonisolated static func looksLikeLocalCommand(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("/") else { return false }
        let firstToken =
            trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed
        return !firstToken.dropFirst().contains("/")
    }

    private func handleLocalSlashCommand(_ text: String) {
        let command = text.split(separator: " ", maxSplits: 1).first.map(String.init) ?? text
        switch command.lowercased() {
        case "/clear", "/restart":
            clearAndRestart()
        case "/exit", "/quit":
            stop()
        case "/status":
            appendSystemMessage(statusReport())
        case "/mcp":
            appendSystemMessage("Listing MCP servers…")
            // Tracked so stop()/clearAndRestart() can cancel the child via
            // dispatchSubcommand's withTaskCancellationHandler; cancelling the
            // prior subcommand prevents two slash commands racing for the slot.
            subcommandTask?.cancel()
            subcommandTask = Task { [weak self] in
                await self?.dispatchSubcommand(["mcp", "list"], label: "MCP servers")
            }
        case "/doctor":
            appendSystemMessage("Running claude doctor…")
            subcommandTask?.cancel()
            subcommandTask = Task { [weak self] in
                await self?.dispatchSubcommand(["doctor"], label: "claude doctor")
            }
        case "/help":
            appendSystemMessage(
                """
                Plumage commands:
                  /clear     Clear chat and restart the claude session
                  /restart   Same as /clear
                  /exit      End the claude session
                  /status    Show current session info
                  /mcp       List configured MCP servers
                  /doctor    Run claude doctor health check
                  /help      Show this message

                Other claude slash commands (e.g. /resume, /login, /model) only \
                work in the interactive REPL — switch to Terminal mode for those.
                """
            )
        default:
            appendSystemMessage(
                """
                Unknown command: \(command). Plumage knows /clear, /restart, \
                /exit, /status, /mcp, /doctor, /help. For claude's own REPL \
                commands switch to Terminal mode.
                """
            )
        }
    }

    private func statusReport() -> String {
        let stateString: String
        switch state {
        case .idle: stateString = "idle"
        case .starting: stateString = "starting"
        case .running(let sid):
            stateString = "running" + (sid.map { " (claude session: \($0))" } ?? "")
        case .exited(let code, let reason): stateString = "ended (exit \(code), \(reason))"
        }
        return """
            Conversation ID: \(conversationID)
            State: \(stateString)
            Messages: \(messages.count)
            Working directory: \(cwd.path)
            """
    }

    private func dispatchSubcommand(_ args: [String], label: String) async {
        let binary = binaryURL
        let workingDirectory = cwd
        let process = Process()
        process.executableURL = binary
        process.arguments = args
        process.currentDirectoryURL = workingDirectory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        // Await exit via terminationHandler, not waitUntilExit() — the latter
        // deadlocks on the Swift cooperative pool. Reuses ProcessRunning's
        // ClaudeProcessTermination.
        let termination = ClaudeProcessTermination()
        process.terminationHandler = { finished in
            termination.complete(finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            appendSystemMessage("\(label):\nError: \(error.localizedDescription)")
            return
        }

        // If the surrounding session is torn down (stop/clearAndRestart or a
        // newer slash command cancels this Task), kill the child so the
        // exit-await resolves instead of pinning a cooperative thread.
        let output: String = await withTaskCancellationHandler {
            // Drain the pipe in parallel with the exit-await: a subcommand emitting
            // more than the ~64 KB pipe buffer would block on write() and never exit
            // if we read post-exit. Off the cooperative pool — readToEnd() blocks.
            async let data = Task.detached { () -> Data in
                (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            }.value
            _ = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
                termination.attach(continuation)
            }
            let text =
                String(data: await data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "(no output)" : text
        } onCancel: {
            // Same SIGTERM → grace → SIGKILL escalation as ProductionProcessRunner.
            ProcessKillEscalation.terminateThenKill(
                process, graceSeconds: ProductionProcessRunner.cancellationGraceSeconds)
        }
        if Task.isCancelled { return }
        appendSystemMessage("\(label):\n\(output)")
    }
}
