import XCTest

final class ClaudeDockOverlayUITests: XCTestCase {
    // Skipped until the XCUITest-termination problem documented in
    // notes.md (2026-05-12 entries) is solved — a launching test here
    // would resurrect the stuck-Plumage-process bug and brick all
    // subsequent test runs on this machine. Manual verification protocol:
    //
    //   1. Open Plumage, open a project window.
    //   2. Confirm the floating sparkles button is bottom-trailing.
    //   3. Click button → panel scales out of the corner.
    //   4. Toggle Chat ↔ Terminal in the panel header.
    //   5. Press ⌘⌥T → panel toggles (closes).
    //   6. Press ⌘⌥0 → panel opens again.
    //   7. Press ESC → panel closes.
    //   8. Close the window. Verify in Activity Monitor that the
    //      `claude` subprocess for that window is gone.
    //   9. Open the window again. Confirm the dock state persists per
    //      @SceneStorage and the session restarts on .task.
    func testToggleAndModeSwitch() throws {
        try XCTSkipIf(true, "Awaiting XCUITest termination fix; see notes.md")
    }
}
