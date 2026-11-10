import Foundation

/// Owns one native legible selection. Every suspension and AVKit mutation must
/// belong to the newest request and the same player item, including A→B→A.
@MainActor
final class NativeSubtitleSelectionOperation {
    struct Checkpoint {
        let isCurrent: () -> Bool

        func check() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
        }

        func wait<T>(_ work: () async throws -> T) async throws -> T {
            try check()
            let result = try await work()
            try check()
            return result
        }
    }

    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    @discardableResult
    func replace<Selection>(
        selects: Bool,
        isCurrentItem: @escaping () -> Bool,
        load: @escaping () async throws -> Selection?,
        prefill: @escaping (Selection, Checkpoint) async throws -> Bool,
        deselect: @escaping (Selection) -> Void,
        select: @escaping (Selection) -> Void,
        needsRetry: @escaping (Selection) -> Bool,
        wait: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) -> Task<Void, Never> {
        cancel()
        let requested = generation
        let checkpoint = Checkpoint(isCurrent: { [weak self] in
            self?.generation == requested && isCurrentItem()
        })
        let next = Task { @MainActor in
            do {
                guard let selection = try await checkpoint.wait(load) else { return }
                if selects {
                    guard try await checkpoint.wait({ try await prefill(selection, checkpoint) }) else { return }
                }
                try checkpoint.check()
                deselect(selection)
                guard selects else { return }
                try await checkpoint.wait { try await wait(100_000_000) }
                select(selection)
                for _ in 0..<4 {
                    try checkpoint.check()
                    guard needsRetry(selection) else { break }
                    try await checkpoint.wait { try await wait(700_000_000) }
                    select(selection)
                }
            } catch {
                // Cancellation, an obsolete item or a failed group load leaves
                // the newest operation solely responsible for AVKit selection.
            }
        }
        task = next
        return next
    }
}
