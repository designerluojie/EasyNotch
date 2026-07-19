import Foundation

protocol MusicProcessRunning: Sendable {
    func run(_ launchPath: String, arguments: [String]) async throws -> MusicProcessOutput
}

struct MusicProcessOutput: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let status: Int32
}

struct FoundationMusicProcessRunner: MusicProcessRunning {
    private let beforeLaunch: @Sendable () async throws -> Void

    // Blocking process execution (`waitUntilExit`, pipe `group.wait()`) must never run on
    // the Swift concurrency cooperative pool: that pool has ~core-count threads, and
    // blocking several of them while probing music players starves the main actor and
    // SwiftUI rendering, freezing the notch panel on expand/switch. Run it on a dedicated
    // GCD queue instead so the cooperative pool stays free.
    private static let processQueue = DispatchQueue(
        label: "com.notch.music.process",
        qos: .utility,
        attributes: .concurrent
    )

    // Hard cap on how long a single probe may run. A hung `nowplaying-cli` / `osascript`
    // (e.g. an unresponsive player) would otherwise linger indefinitely.
    private static let processTimeout: TimeInterval = 5

    init(beforeLaunch: @escaping @Sendable () async throws -> Void = {}) {
        self.beforeLaunch = beforeLaunch
    }

    func run(_ launchPath: String, arguments: [String]) async throws -> MusicProcessOutput {
        let processBox = RunningProcessBox()

        try Task.checkCancellation()
        try await beforeLaunch()
        try Task.checkCancellation()

        let output = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MusicProcessOutput, Error>) in
                Self.processQueue.async {
                    do {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: launchPath)
                        process.arguments = arguments
                        defer { processBox.clear() }

                        let stdoutPipe = Pipe()
                        let stderrPipe = Pipe()
                        process.standardOutput = stdoutPipe
                        process.standardError = stderrPipe

                        let exited = DispatchSemaphore(value: 0)
                        process.terminationHandler = { _ in exited.signal() }

                        try processBox.launch(process)

                        let outputReader = ProcessPipeReader(
                            stdout: stdoutPipe.fileHandleForReading,
                            stderr: stderrPipe.fileHandleForReading
                        )
                        outputReader.start()

                        if exited.wait(timeout: .now() + Self.processTimeout) == .timedOut {
                            process.terminate()
                            _ = exited.wait(timeout: .now() + 1)
                        }
                        let outputData = outputReader.waitForData()

                        continuation.resume(returning: MusicProcessOutput(
                            stdout: String(decoding: outputData.stdout, as: UTF8.self),
                            stderr: String(decoding: outputData.stderr, as: UTF8.self),
                            status: process.terminationStatus
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            processBox.cancel()
        }

        // onCancel SIGTERMs the child, which then exits with status 15 and resumes the
        // continuation like any other run. Returning that output would let one cancelled
        // poll masquerade as a real probe failure — panel collapse cancels the in-flight
        // poll, and that fake failure used to blank the music module back to the default
        // notch. A cancelled run reports cancellation, never a result.
        try Task.checkCancellation()
        return output
    }

}

private final class RunningProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var process: Process?
    nonisolated(unsafe) private var isCancelled = false

    nonisolated func launch(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }

        if isCancelled {
            throw CancellationError()
        }

        self.process = process
        try process.run()
    }

    nonisolated func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    nonisolated func cancel() {
        lock.lock()
        isCancelled = true
        let process = process
        lock.unlock()

        guard let process, process.isRunning else {
            return
        }

        process.terminate()
    }
}

nonisolated private final class ProcessPipeReader: @unchecked Sendable {
    private let stdout: FileHandle
    private let stderr: FileHandle
    private let stdoutData = LockedProcessData()
    private let stderrData = LockedProcessData()
    private let group = DispatchGroup()

    init(stdout: FileHandle, stderr: FileHandle) {
        self.stdout = stdout
        self.stderr = stderr
    }

    func start() {
        read(stdout, into: stdoutData)
        read(stderr, into: stderrData)
    }

    func waitForData() -> (stdout: Data, stderr: Data) {
        group.wait()
        return (stdoutData.value(), stderrData.value())
    }

    private func read(_ handle: FileHandle, into box: LockedProcessData) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = handle.readDataToEndOfFile()
            box.set(data)
            self.group.leave()
        }
    }
}

nonisolated private final class LockedProcessData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ data: Data) {
        lock.lock()
        self.data = data
        lock.unlock()
    }

    func value() -> Data {
        lock.lock()
        let value = data
        lock.unlock()
        return value
    }
}
