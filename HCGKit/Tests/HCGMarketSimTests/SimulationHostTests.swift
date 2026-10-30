import Foundation
import Testing
import HCGDomain
import HCGTrading
@testable import HCGMarketSim

/// A ticker that never sleeps, so the real playback loop runs as fast as the
/// main actor allows.
struct ImmediateTicker: SimulationTicker {
    func wait(for duration: Duration) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}

/// Records every requested wait and blocks until cancelled, so a test can see
/// exactly which interval the playback loop is waiting on.
final class RecordingTicker: SimulationTicker, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []

    var requests: [Duration] {
        lock.withLock { recorded }
    }

    func wait(for duration: Duration) async throws {
        lock.withLock { recorded.append(duration) }
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
@Suite("Simulation host — playback")
struct SimulationHostTests {
    /// Waits (bounded, about 5 s) until `condition` holds, letting the
    /// playback loop run in between.
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<5_000 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return condition()
    }

    @Test("Pause stops the clock and resume continues it")
    func pauseAndResume() async {
        let host = SimulationHost(seed: 12, ticker: ImmediateTicker())
        #expect(!host.isPlaying)
        host.play()
        #expect(host.isPlaying)
        #expect(await waitUntil { host.frame.sequence >= 25 })

        await host.pauseAndWait()
        #expect(!host.isPlaying)
        let paused = host.frame.sequence
        for _ in 0..<500 { await Task.yield() }
        #expect(host.frame.sequence == paused, "no updates while paused")

        host.play()
        #expect(await waitUntil { host.frame.sequence >= paused + 25 })
        await host.pauseAndWait()
        let resumed = host.frame.sequence
        #expect(resumed >= paused + 25)
    }

    @Test("Playback with pauses reproduces an uninterrupted run exactly")
    func pausedRunMatchesContinuousRun() async {
        let host = SimulationHost(seed: 3, ticker: ImmediateTicker())
        for _ in 0..<3 {
            host.play()
            _ = await waitUntil { host.frame.sequence >= 40 }
            await host.pauseAndWait()
        }
        var reference = SimulationState(seed: 3)
        for _ in 0..<host.frame.sequence { reference.advance() }
        #expect(host.frame == reference.frame())
    }

    @Test("Manual steps advance exactly one update while paused")
    func manualStep() async {
        let host = SimulationHost(seed: 1, ticker: ImmediateTicker())
        await host.step()
        await host.step()
        #expect(host.frame.sequence == 2)
        var reference = SimulationState(seed: 1)
        reference.advance()
        reference.advance()
        #expect(host.frame == reference.frame())
    }

    @Test("Speed control is bounded")
    func speedBounds() {
        let host = SimulationHost(ticker: ImmediateTicker())
        #expect(host.speed == .normal)
        for _ in 0..<10 { host.faster() }
        #expect(host.speed == .octuple)
        for _ in 0..<10 { host.slower() }
        #expect(host.speed == .quarter)
        #expect(SimulationSpeed.normal.interval == .milliseconds(500))
        #expect(SimulationSpeed.octuple.interval == .milliseconds(63))
    }

    @Test("A speed change applies to the pending wait immediately")
    func speedChangeIsImmediate() async {
        let ticker = RecordingTicker()
        let host = SimulationHost(seed: 2, speed: .quarter, ticker: ticker)
        host.play()
        #expect(await waitUntil { ticker.requests.count == 1 })
        #expect(ticker.requests.first == SimulationSpeed.quarter.interval)

        host.setSpeed(.octuple)
        #expect(await waitUntil { ticker.requests.count == 2 }, "the 2-second wait must be abandoned")
        #expect(ticker.requests.last == SimulationSpeed.octuple.interval)
        #expect(host.isPlaying)

        host.setSpeed(.octuple) // unchanged speed: no restart
        for _ in 0..<200 { await Task.yield() }
        #expect(ticker.requests.count == 2)
        await host.pauseAndWait()
        #expect(host.frame.sequence == 0, "no update completed while waiting")
    }

    @Test("Reset keeps playback running when it was running")
    func resetPreservesPlayback() async {
        let host = SimulationHost(seed: 8, ticker: ImmediateTicker())
        host.play()
        _ = await waitUntil { host.frame.sequence >= 10 }
        await host.reset(seed: 8)
        #expect(host.isPlaying, "reset must not silently stop the clock")
        #expect(await waitUntil { host.frame.sequence >= 5 })
        await host.pauseAndWait()

        await host.reset(seed: 8)
        #expect(!host.isPlaying, "a paused session stays paused after reset")
        #expect(host.frame.sequence == 0)
    }

    @Test("Orders and resets publish through the same frame")
    func ordersPublishFrames() async {
        let host = SimulationHost(seed: 6, ticker: ImmediateTicker())
        let result = await host.submit(.market(.buy, 1, .gc, id: "t-1"))
        #expect(result.order.status == .filled)
        #expect(host.frame.account.position(.gc)?.quantity == 1)
        #expect(host.lastOrderMessage?.hasPrefix("Simulated #") == true)
        await host.closePosition(.gc)
        #expect(host.frame.account.position(.gc) == nil)
        let rejected = await host.submit(.market(.buy, 0, .gc, id: "t-2"))
        #expect(rejected.order.status == .rejected)
        #expect(host.lastOrderMessage?.hasPrefix("Rejected:") == true)

        let revisionBefore = host.frame.revision
        await host.reset(seed: 6)
        #expect(host.frame.sequence == 0)
        #expect(host.frame.revision > revisionBefore)
        #expect(host.frame.account.fills.isEmpty)
        #expect(host.frame.account.resetCount == 1)
    }
}
