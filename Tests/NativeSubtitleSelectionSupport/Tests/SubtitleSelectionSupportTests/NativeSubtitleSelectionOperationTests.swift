import XCTest
#if canImport(AetherEngine)
@testable import AetherEngine
#else
@testable import SubtitleSelectionSupport
#endif

@MainActor
private final class Gate {
    private var held: CheckedContinuation<Void, Never>?
    private var released = false
    let entered = XCTestExpectation(description: "controlled native reply is held")

    func wait() async {
        await withCheckedContinuation {
            if released { $0.resume(); return }
            held = $0
            entered.fulfill()
        }
    }
    func release() {
        released = true
        held?.resume()
        held = nil
    }

}

final class NativeSubtitleSelectionOperationTests: XCTestCase {
    /// Drive the actual production async owner; AVKit effects are recorded at
    /// their boundary. The gate deliberately ignores cancellation to simulate
    /// late successful OS replies. No media, clocks, network or sleeps.
    @MainActor func testExitAndTrackReplacementAtEverySuspension() async {
        for stage in ["group", "prefill", "reselect", "retry"] {
            for replacement in ["Off", "B", "A"] {
                let owner = NativeSubtitleSelectionOperation()
                let gate = Gate()
                var effects: [String] = []
                var waits = 0
                let old = owner.replace(
                    selects: true, isCurrentItem: { true },
                    load: {
                        if stage == "group" { await gate.wait() }
                        return "A"
                    },
                    prefill: { _, checkpoint in
                        if stage == "prefill" {
                            try await checkpoint.wait { await gate.wait() }
                        }
                        return true
                    },
                    deselect: { _ in effects.append("old:clear") },
                    select: { effects.append("old:\($0)") },
                    needsRetry: { _ in true },
                    wait: { _ in
                        waits += 1
                        if (stage == "reselect" && waits == 1) || (stage == "retry" && waits == 2) {
                            await gate.wait()
                        }
                    })
                // The owning task is canceled and every fake reply is released
                // even if the bounded start assertion fails.
                defer { owner.cancel(); gate.release() }
                let entered = await XCTWaiter.fulfillment(of: [gate.entered], timeout: 1)
                XCTAssertEqual(entered, .completed)
                let latest = owner.replace(
                    selects: replacement != "Off", isCurrentItem: { true },
                    load: { replacement }, prefill: { _, _ in true },
                    deselect: { _ in effects.append("new:clear") },
                    select: { effects.append("new:\($0)") },
                    needsRetry: { _ in false }, wait: { _ in })
                await latest.value
                let committed = effects
                gate.release()
                await old.value
                XCTAssertEqual(effects, committed, "late \(stage) after \(replacement)")
                XCTAssertEqual(effects.last, replacement == "Off" ? "new:clear" : "new:\(replacement)")
            }
        }
    }

    @MainActor func testItemReplacementAndTeardownRejectLatePrefillThenRecover() async {
        for teardown in [false, true] {
            let owner = NativeSubtitleSelectionOperation()
            let gate = Gate()
            var itemIsCurrent = true
            var selected: [Int] = []
            let old = owner.replace(
                selects: true, isCurrentItem: { itemIsCurrent }, load: { 1 },
                prefill: { _, _ in await gate.wait(); return true },
                deselect: { _ in }, select: { selected.append($0) },
                needsRetry: { _ in false }, wait: { _ in })
            defer { owner.cancel(); gate.release() }
            let entered = await XCTWaiter.fulfillment(of: [gate.entered], timeout: 1)
            XCTAssertEqual(entered, .completed)
            if teardown { owner.cancel() } else { itemIsCurrent = false }
            gate.release()
            await old.value
            XCTAssertTrue(selected.isEmpty)
            let recovered = owner.replace(
                selects: true, isCurrentItem: { true }, load: { 2 },
                prefill: { _, _ in true }, deselect: { _ in },
                select: { selected.append($0) }, needsRetry: { _ in false }, wait: { _ in })
            await recovered.value
            XCTAssertEqual(selected, [2])
        }
    }

    @MainActor func testFailedPreparationLeavesNoSelectionAndRetryIsBounded() async {
        let owner = NativeSubtitleSelectionOperation()
        var selected: [Int] = []
        for failure in ["group", "prefill", "empty"] {
            let failed = owner.replace(
                selects: true, isCurrentItem: { true },
                load: {
                    if failure == "group" { throw CancellationError() }
                    return failure == "empty" ? nil : 1
                },
                prefill: { _, _ in
                    if failure == "prefill" { throw CancellationError() }
                    return false
                }, deselect: { _ in XCTFail("failed preparation must not mutate selection") },
                select: { selected.append($0) }, needsRetry: { _ in true }, wait: { _ in })
            await failed.value
        }
        XCTAssertTrue(selected.isEmpty)
        let retry = owner.replace(
            selects: true, isCurrentItem: { true }, load: { 2 },
            prefill: { _, _ in true }, deselect: { _ in },
            select: { selected.append($0) }, needsRetry: { _ in true }, wait: { _ in })
        await retry.value
        XCTAssertEqual(selected, [2, 2, 2, 2, 2]) // first application + four retries
    }
}


private final class ReferenceSelection {
    var name = "A"
}

extension NativeSubtitleSelectionOperationTests {
    /// SV-492: model an AVKit reference that is deliberately not Sendable.
    /// Swift 6 must keep it on MainActor across both checkpoint suspensions.
    @MainActor func testNonSendableSelectionRemainsOnMainActorSV492() async {
        let owner = NativeSubtitleSelectionOperation()
        defer { owner.cancel() }
        let selection = ReferenceSelection()
        var selected: ReferenceSelection?
        var callbacks: Set<String> = []
        let task = owner.replace(
            selects: true,
            isCurrentItem: { MainActor.preconditionIsolated(); return true },
            load: {
                MainActor.preconditionIsolated()
                callbacks.insert("load")
                await Task.yield()
                MainActor.preconditionIsolated()
                return selection
            },
            prefill: { value, checkpoint in
                MainActor.preconditionIsolated()
                callbacks.insert("prefill")
                let same = try await checkpoint.wait {
                    await Task.yield()
                    MainActor.preconditionIsolated()
                    return value
                }
                XCTAssertTrue(same === selection)
                return true
            },
            deselect: { _ in MainActor.preconditionIsolated(); callbacks.insert("deselect") },
            select: { value in MainActor.preconditionIsolated(); selected = value; callbacks.insert("select") },
            needsRetry: { _ in MainActor.preconditionIsolated(); callbacks.insert("retry"); return false },
            wait: { _ in
                MainActor.preconditionIsolated()
                callbacks.insert("wait")
                await Task.yield()
                MainActor.preconditionIsolated()
            })
        await task.value
        XCTAssertTrue(selected === selection)
        XCTAssertEqual(callbacks, ["load", "prefill", "deselect", "select", "retry", "wait"])
    }
}
