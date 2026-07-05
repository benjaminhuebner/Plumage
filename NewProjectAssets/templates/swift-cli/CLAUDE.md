## Project layout
- `Sources/<ToolName>/` — main target with `@main` entry and command implementations
- `Tests/<ToolName>Tests/` — unit tests

## Conventions
- Argument parsing via **swift-argument-parser**. Commands conform to `AsyncParsableCommand`; subcommands nest naturally.
- Validate input in `validate()`. Throw `ValidationError("...")` on bad args.
- User-facing text → stdout. Errors, progress, diagnostics → stderr.
- Machine-readable output (`--json`): valid JSON to stdout, no log lines or progress decoration mixed in.
- Exit codes: `0` success, `1` generic error, `2` argument misuse. Document them in `--help`.
- Signal handling (`SIGINT`, `SIGTERM`): use swift-system or argument-parser helpers, not raw signal handlers.
- Color and progress decoration only when stdout is a TTY (`isatty`), and respect `NO_COLOR`. Piped output stays plain.

## Build and test
- Build/run: `swift build` / `swift run <ToolName>`. Release: `swift build -c release`.
- End-to-end CLI tests: build the binary and exec it as a subprocess via `Foundation.Process`. Capture stdout and stderr separately.

## Common pitfalls
- Piping stdin/stdout in-process for tests leaks state. Always exec the actual binary.
- Exit via `throw ExitCode(...)`, not `Foundation.exit(...)`. `exit()` bypasses Swift's cleanup (defers, actor isolation, task cancellation).
