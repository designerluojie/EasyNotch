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

            let outputReader = ProcessPipeReader(
                stdout: stdoutPipe.fileHandleForReading,
                stderr: stderrPipe.fileHandleForReading
            )
            outputReader.start()

            process.waitUntilExit()
            let outputData = outputReader.waitForData()
            try Task.checkCancellation()

            return MusicProcessOutput(
                stdout: String(decoding: outputData.stdout, as: UTF8.self),
                stderr: String(decoding: outputData.stderr, as: UTF8.self),
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
