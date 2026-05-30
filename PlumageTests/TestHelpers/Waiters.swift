import Foundation

struct WaitTimeoutError: Error {}

// Polls `condition` until it returns true or `timeout` elapses, sleeping with
// exponential backoff between checks (5/10/20/50/100 ms, capped). The fast first
// polls keep the success-case latency low (~5 ms instead of a fixed sleep); the
// cap stops a long wait from busy-spinning. This is the sanctioned replacement
// for ad-hoc `Task.sleep` polling in test bodies.
func waitUntil(
    timeout: Duration,
    condition: @Sendable () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    let backoff: [Duration] = [
        .milliseconds(5), .milliseconds(10), .milliseconds(20),
        .milliseconds(50), .milliseconds(100),
    ]
    var step = 0
    while clock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: backoff[min(step, backoff.count - 1)])
        step += 1
    }
    // The condition may have flipped during the final sleep, after which
    // `clock.now < deadline` is false but the wait did succeed. Check once more
    // before declaring a timeout to avoid a spurious failure under load.
    if await condition() { return }
    throw WaitTimeoutError()
}
