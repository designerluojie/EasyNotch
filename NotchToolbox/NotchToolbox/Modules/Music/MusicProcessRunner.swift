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

    init(beforeLaunch: @escaping @Sendable () async throws -> Void = {}) {
        self.beforeLaunch = beforeLaunch
    }

    func run(_ launchPath: String, arguments: [String]) async throws -> MusicProcessOutput {
        let processBox = RunningProcessBox()
        let beforeLaunch = self.beforeLaunch
        let task = Task.detached(priority: nil) {
            try Task.checkCancellation()

            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            defer { processBox.clear() }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try await beforeLaunch()
            try Task.checkCancellation()
            try processBox.launch(process)

            async let stdoutData = Self.readAll(from: stdoutPipe.fileHandleForReading)
            async let stderrData = Self.readAll(from: stderrPipe.fileHandleForReading)

            process.waitUntilExit()
            try Task.checkCancellation()

            return MusicProcessOutput(
                stdout: String(decoding: try await stdoutData, as: UTF8.self),
                stderr: String(decoding: try await stderrData, as: UTF8.self),
                status: process.terminationStatus
            )
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            processBox.cancel()
            task.cancel()
        }
    }

    private static func readAll(from handle: FileHandle) async throws -> Data {
        var data = Data()
        for try await byte in handle.bytes {
            data.append(byte)
        }
        return data
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
