import Foundation

@MainActor
final class ClipboardStore {
    private let fileStore: LocalFileStore
    private let settingsStore: SettingsStore
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileStore: LocalFileStore,
        settingsStore: SettingsStore,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        self.fileStore = fileStore
        self.settingsStore = settingsStore
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func save(_ capture: ClipboardCapture, maxItems: Int) throws -> [ClipboardHistoryItem] {
        var history = try loadHistory()

        if let duplicateIndex = history.firstIndex(where: {
            $0.contentHash == capture.contentHash && $0.contentType == capture.contentType
        }) {
            let duplicate = history.remove(at: duplicateIndex)
            try removePayloadIfNeeded(for: duplicate)
        }

        let item = try ClipboardHistoryItem(
            id: UUID(),
            contentType: capture.contentType,
            previewText: capture.previewText,
            contentHash: capture.contentHash,
            copiedAt: capture.capturedAt,
            sourceAppBundleID: capture.sourceAppBundleID,
            sourceAppName: capture.sourceAppName,
            payload: makePayloadDescriptor(for: capture.payload)
        )

        history.insert(item, at: 0)

        if history.count > maxItems {
            let removedItems = Array(history.suffix(history.count - maxItems))
            history = Array(history.prefix(maxItems))
            for removedItem in removedItems {
                try removePayloadIfNeeded(for: removedItem)
            }
        }

        try persist(history)
        return history
    }

    func loadHistory() throws -> [ClipboardHistoryItem] {
        let historyURL = self.historyURL
        guard fileManager.fileExists(atPath: historyURL.path(percentEncoded: false)) else {
            return []
        }

        let data = try Data(contentsOf: historyURL)
        return try decoder.decode([ClipboardHistoryItem].self, from: data)
    }

    func payloadData(for item: ClipboardHistoryItem) throws -> Data {
        switch item.payload {
        case let .inline(fileName, _, _):
            return try Data(contentsOf: payloadsDirectoryURL.appending(path: fileName))
        case let .fileReferences(references):
            return try JSONEncoder().encode(references)
        }
    }

    func replaceHistory(_ history: [ClipboardHistoryItem]) throws -> [ClipboardHistoryItem] {
        let previous = try loadHistory()
        let retainedFileNames = Set(history.compactMap(\.inlinePayloadFileName))
        let removedFileNames = Set(previous.compactMap(\.inlinePayloadFileName))
            .subtracting(retainedFileNames)

        for removedFileName in removedFileNames {
            let payloadURL = payloadsDirectoryURL.appending(path: removedFileName)
            guard fileManager.fileExists(atPath: payloadURL.path(percentEncoded: false)) else {
                continue
            }

            try fileManager.removeItem(at: payloadURL)
        }

        try persist(history)
        return history
    }

    private var historyURL: URL {
        fileStore.url(for: .clipboard).appending(path: "history.json")
    }

    private var payloadsDirectoryURL: URL {
        fileStore.url(for: .clipboardPayloads)
    }

    private func makePayloadDescriptor(
        for payload: ClipboardCapturePayload
    ) throws -> ClipboardPayloadDescriptor {
        switch payload {
        case let .inline(data, pasteboardType, suggestedFileExtension):
            try fileStore.prepareDirectory(.clipboardPayloads)
            let fileName = payloadFileName(for: suggestedFileExtension)
            let payloadURL = payloadsDirectoryURL.appending(path: fileName)
            try data.write(to: payloadURL, options: [.atomic])
            return .inline(
                fileName: fileName,
                pasteboardType: pasteboardType,
                suggestedFileExtension: suggestedFileExtension
            )
        case let .fileReferences(references):
            return .fileReferences(references)
        }
    }

    private func persist(_ history: [ClipboardHistoryItem]) throws {
        try fileStore.prepareDirectory(.clipboard)
        let data = try encoder.encode(history)
        try data.write(to: historyURL, options: [.atomic])
    }

    private func payloadFileName(for suggestedFileExtension: String?) -> String {
        let baseName = UUID().uuidString
        guard let suggestedFileExtension, !suggestedFileExtension.isEmpty else {
            return baseName
        }

        return "\(baseName).\(suggestedFileExtension)"
    }

    private func removePayloadIfNeeded(for item: ClipboardHistoryItem) throws {
        guard case let .inline(fileName, _, _) = item.payload else {
            return
        }

        let payloadURL = payloadsDirectoryURL.appending(path: fileName)
        guard fileManager.fileExists(atPath: payloadURL.path(percentEncoded: false)) else {
            return
        }

        try fileManager.removeItem(at: payloadURL)
    }
}

private extension ClipboardHistoryItem {
    var inlinePayloadFileName: String? {
        guard case let .inline(fileName, _, _) = payload else {
            return nil
        }

        return fileName
    }
}
