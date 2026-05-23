import XCTest

final class ClaudeDockOverlayUITests: XCTestCase {
    // Skipped until the XCUITest-termination problem documented in
    // notes.md (2026-05-12 entries) is solved — a launching test here
    // would resurrect the stuck-Plumage-process bug and brick all
    // subsequent test runs on this machine. Manual verification protocol:
    //
    //   1. Open Plumage, open a project window.
    //   2. Confirm the floating sparkles button is bottom-trailing of the
    //      whole window (anchored to the NavigationSplitView corner, not
    //      to the detail column — verify by opening the terminal inspector
    //      and confirming the button stays at the window's right edge).
    //   3. Click button → panel scales out of the corner.
    //   4. Press ⌘⌥J → chat dock toggles (closes/opens).
    //   5. Press ⌘⌥T → terminal inspector toggles.
    //   6. Press ESC while dock has focus → dock closes.
    //   7. Close the window. Verify in Activity Monitor that the
    //      `claude` subprocesses for that window are gone.
    //   8. Open the window again. Confirm dock + inspector state persists
    //      per @SceneStorage and sessions restart on .task.
    func testDockAndInspectorToggles() throws {
        try XCTSkipIf(true, "Awaiting XCUITest termination fix; see notes.md")
    }
}
