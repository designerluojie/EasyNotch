import Foundation
@testable import NotchToolbox

enum FakeRuntimeMode: Equatable {
    case manual
    case autoComplete
    case reasoningThenComplete
    case stopAfterFirstChunk
    case failAfterFirstChunk
}

@MainActor
final class FakeStreamingChatRuntime: AIChatRuntime {
    private let mode: FakeRuntimeMode

    private var currentRequestID: UUID?
    private var currentContinuation: AsyncThrowingStream<AIChatRuntimeEvent, Error>.Continuation?
    private var scheduledTask: Task<Void, Never>?
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(mode: FakeRuntimeMode = .manual) {
        self.mode = mode
    }

    func streamReply(for request: AIChatRequest) -> AsyncThrowingStream<AIChatRuntimeEvent, Error> {
        if let currentRequestID {
            stopStreaming(requestID: currentRequestID)
        }

        return AsyncThrowingStream { continuation in
            currentRequestID = request.id
            currentContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.finishActiveStream(clearContinuation: false)
                }
            }
            continuation.yield(.started(requestID: request.id))

            switch mode {
            case .manual:
                continuation.yield(
                    .delta(
                        requestID: request.id,
                        textChunk: "Fake response for: \(request.prompt)"
                    )
                )
            case .autoComplete:
                continuation.yield(.delta(requestID: request.id, textChunk: "Fake response for: "))
                scheduledTask = Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self, let continuation = self.currentContinuation else {
                        return
                    }

                    continuation.yield(.delta(requestID: request.id, textChunk: request.prompt))
                    continuation.yield(.completed(requestID: request.id))
                    await Task.yield()
                    self.finishActiveStream()
                }
            case .reasoningThenComplete:
                scheduledTask = Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self, let continuation = self.currentContinuation else {
                        return
                    }

                    continuation.yield(.reasoningDelta(requestID: request.id, textChunk: "先分析"))
                    continuation.yield(.delta(requestID: request.id, textChunk: "最终答案"))
                    continuation.yield(.completed(requestID: request.id))
                    await Task.yield()
                    self.finishActiveStream()
                }
            case .stopAfterFirstChunk:
                continuation.yield(
                    .delta(
                        requestID: request.id,
                        textChunk: "Fake response for: \(request.prompt)"
                    )
                )
                scheduledTask = Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self, let continuation = self.currentContinuation else {
                        return
                    }

                    continuation.yield(.stopped(requestID: request.id))
                    self.finishActiveStream()
                }
            case .failAfterFirstChunk:
                continuation.yield(
                    .delta(
                        requestID: request.id,
                        textChunk: "Fake response for: \(request.prompt)"
                    )
                )
                scheduledTask = Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self, let continuation = self.currentContinuation else {
                        return
                    }

                    continuation.yield(
                        .failed(
                            requestID: request.id,
                            summary: "Fake runtime failure"
                        )
                    )
                    self.finishActiveStream()
                }
            }
        }
    }

    func stopStreaming(requestID: UUID) {
        guard requestID == currentRequestID, let currentContinuation else {
            return
        }

        currentContinuation.yield(.stopped(requestID: requestID))
        finishActiveStream()
    }

    func waitForDrain() async {
        guard currentContinuation != nil || scheduledTask != nil else {
            for _ in 0..<5 {
                await Task.yield()
            }
            return
        }

        await withCheckedContinuation { continuation in
            drainWaiters.append(continuation)
        }
        for _ in 0..<5 {
            await Task.yield()
        }
    }
}

private extension FakeStreamingChatRuntime {
    func finishActiveStream(clearContinuation: Bool = true) {
        scheduledTask?.cancel()
        scheduledTask = nil

        if clearContinuation {
            currentContinuation?.finish()
        }
        currentContinuation = nil
        currentRequestID = nil

        let waiters = drainWaiters
        drainWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}
