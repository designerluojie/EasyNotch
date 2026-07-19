import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct DiagnosticsStoreTests {
    @Test func recordCapsStoredMessagesAtLimit() {
        let store = DiagnosticsStore(maxStoredMessages: 3)

        for index in 0..<5 {
            store.record(.info, message: "message-\(index)")
        }

        #expect(store.messages.count == 3)
        #expect(store.messages.first?.message == "message-2")
        #expect(store.messages.last?.message == "message-4")
    }

    @Test func recordAppendsLinesToLogFile() throws {
        let logFileURL = FileManager.default.temporaryDirectory
            .appending(path: "NotchToolboxTests")
            .appending(path: UUID().uuidString)
            .appending(path: "diagnostics.log")
        try FileManager.default.createDirectory(
            at: logFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let store = DiagnosticsStore(logFileURL: logFileURL)

        store.record(.error, message: "first failure")
        store.record(.warning, message: "second issue")

        let contents = try String(contentsOf: logFileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("[error] first failure"))
        #expect(lines[1].contains("[warning] second issue"))
    }

    @Test func sharedCoreServicesDefaultDiagnosticsWriteToLogsDirectory() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: "NotchToolboxTests")
            .appending(path: UUID().uuidString)
        let services = try SharedCoreServices(
            baseURL: baseURL,
            credentialStore: InMemorySecureCredentialStore()
        )

        services.diagnosticsStore.record(.error, message: "wiring check")

        let logFileURL = baseURL
            .appending(path: "Logs")
            .appending(path: "diagnostics.log")
        let contents = try String(contentsOf: logFileURL, encoding: .utf8)
        #expect(contents.contains("[error] wiring check"))
    }
}
