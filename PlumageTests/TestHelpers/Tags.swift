import Testing

extension Tag {
    // Marks suites that drive real FSEvents, subprocesses, or long sync waits.
    // The default test plan skips this tag; the --full plan runs it.
    @Tag static var integration: Self
}
