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
        let previousHistory = try loadHistory()
        var history = previousHistory
        var removedItems: [ClipboardHistoryItem] = []
        var createdPayloadFileNames: [String] = []
        var createdThumbnailFileNames: [String] = []

        if let duplicateIndex = history.firstIndex(where: {
            $0.contentHash == capture.contentHash && $0.contentType == capture.contentType
        }) {
            removedItems.append(history.remove(at: duplicateIndex))
        }

        do {
            let payloadResult = try makePayloadDescriptor(for: capture.payload)
            createdPayloadFileNames = payloadResult.createdFileNames

            let thumbnailResult = try makeThumbnailDescriptor(for: capture.thumbnail)
            createdThumbnailFileNames = thumbnailResult.createdFileNames

            let item = ClipboardHistoryItem(
                id: UUID(),
                contentType: capture.contentType,
                previewText: capture.previewText,
                contentHash: capture.contentHash,
                copiedAt: capture.capturedAt,
                sourceAppBundleID: capture.sourceAppBundleID,
                sourceAppName: capture.sourceAppName,
                payload: payloadResult.descriptor,
                thumbnail: thumbnailResult.descriptor
            )

            history.insert(item, at: 0)

            if history.count > maxItems {
                removedItems.append(contentsOf: history.suffix(history.count - maxItems))
                history = Array(history.prefix(maxItems))
            }

            try persist(history)
            try removeDetachedFiles(
                previouslyStoredItems: removedItems,
                retaining: history
            )
            return history
        } catch {
            try? removeStoredFiles(at: payloadsDirectoryURL, named: createdPayloadFileNames)
            try? removeStoredFiles(at: thumbnailsDirectoryURL, named: createdThumbnailFileNames)
            try? persist(previousHistory)
            throw error
        }
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
        case let .figma(representations):
            guard let first = representations.first else {
                return Data()
            }

            return try Data(contentsOf: payloadsDirectoryURL.appending(path: first.fileName))
        case let .fileReferences(references):
            return try JSONEncoder().encode(references)
        }
    }

    func payloadRepresentations(
        for item: ClipboardHistoryItem
    ) throws -> [ClipboardInlineRepresentation] {
        switch item.payload {
        case let .inline(fileName, pasteboardType, suggestedFileExtension):
            return [
                ClipboardInlineRepresentation(
                    data: try Data(contentsOf: payloadsDirectoryURL.appending(path: fileName)),
                    pasteboardType: pasteboardType,
                    suggestedFileExtension: suggestedFileExtension
                ),
            ]
        case let .figma(representations):
            return try representations.map { representation in
                ClipboardInlineRepresentation(
                    data: try Data(
                        contentsOf: payloadsDirectoryURL.appending(path: representation.fileName)
                    ),
                    pasteboardType: representation.pasteboardType,
                    suggestedFileExtension: representation.suggestedFileExtension
                )
            }
        case .fileReferences:
            return []
        }
    }

    func replaceHistory(_ history: [ClipboardHistoryItem]) throws -> [ClipboardHistoryItem] {
        let previous = try loadHistory()
        let removedPayloadFileNames = Set(previous.flatMap(\.payloadFileNames))
            .subtracting(Set(history.flatMap(\.payloadFileNames)))
        let removedThumbnailFileNames = Set(previous.compactMap(\.thumbnailFileName))
            .subtracting(Set(history.compactMap(\.thumbnailFileName)))

        try persist(history)
        try removeStoredFiles(at: payloadsDirectoryURL, named: removedPayloadFileNames)
        try removeStoredFiles(at: thumbnailsDirectoryURL, named: removedThumbnailFileNames)
        return history
    }

    func promote(itemID: UUID, copiedAt: Date) throws -> [ClipboardHistoryItem] {
        var history = try loadHistory()
        guard let index = history.firstIndex(where: { $0.id == itemID }) else {
            return history
        }

        var item = history.remove(at: index)
        item.copiedAt = copiedAt
        history.insert(item, at: 0)

        try persist(history)
        return history
    }

    private var historyURL: URL {
        fileStore.url(for: .clipboard).appending(path: "history.json")
    }

    private var payloadsDirectoryURL: URL {
        fileStore.url(for: .clipboardPayloads)
    }

    private var thumbnailsDirectoryURL: URL {
        fileStore.url(for: .clipboardThumbnails)
    }

    private func makePayloadDescriptor(
        for payload: ClipboardCapturePayload
    ) throws -> StoredPayloadResult {
        switch payload {
        case let .inline(data, pasteboardType, suggestedFileExtension):
            try fileStore.prepareDirectory(.clipboardPayloads)
            let fileName = payloadFileName(for: suggestedFileExtension)
            let payloadURL = payloadsDirectoryURL.appending(path: fileName)
            try data.write(to: payloadURL, options: [.atomic])
            return StoredPayloadResult(
                descriptor: .inline(
                    fileName: fileName,
                    pasteboardType: pasteboardType,
                    suggestedFileExtension: suggestedFileExtension
                ),
                createdFileNames: [fileName]
            )
        case let .figma(figmaPayload):
            try fileStore.prepareDirectory(.clipboardPayloads)
            let descriptors = try figmaPayload.representations.map { representation in
                let fileName = payloadFileName(for: representation.suggestedFileExtension)
                let payloadURL = payloadsDirectoryURL.appending(path: fileName)
                try representation.data.write(to: payloadURL, options: [.atomic])
                return ClipboardStoredRepresentationDescriptor(
                    fileName: fileName,
                    pasteboardType: representation.pasteboardType,
                    suggestedFileExtension: representation.suggestedFileExtension
                )
            }
            return StoredPayloadResult(
                descriptor: .figma(descriptors),
                createdFileNames: descriptors.map(\.fileName)
            )
        case let .fileReferences(references):
            return StoredPayloadResult(
                descriptor: .fileReferences(references),
                createdFileNames: []
            )
        }
    }

    private func makeThumbnailDescriptor(
        for snapshot: ClipboardThumbnailSnapshot?
    ) throws -> StoredThumbnailResult {
        guard let snapshot else {
            return StoredThumbnailResult(descriptor: nil, createdFileNames: [])
        }

        try fileStore.prepareDirectory(.clipboardThumbnails)
        let suggestedFileExtension = URL(filePath: snapshot.descriptor.fileName).pathExtension
        let storedFileName = payloadFileName(
            for: suggestedFileExtension.isEmpty ? nil : suggestedFileExtension
        )
        let thumbnailURL = thumbnailsDirectoryURL.appending(path: storedFileName)
        try snapshot.data.write(to: thumbnailURL, options: [.atomic])

        var descriptor = snapshot.descriptor
        descriptor.fileName = storedFileName

        return StoredThumbnailResult(
            descriptor: descriptor,
            createdFileNames: [storedFileName]
        )
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
        try removeStoredFiles(at: payloadsDirectoryURL, named: item.payloadFileNames)

        if let thumbnailFileName = item.thumbnailFileName {
            try removeStoredFiles(at: thumbnailsDirectoryURL, named: [thumbnailFileName])
        }
    }

    private func removeDetachedFiles(
        previouslyStoredItems: [ClipboardHistoryItem],
        retaining history: [ClipboardHistoryItem]
    ) throws {
        let retainedPayloadFileNames = Set(history.flatMap(\.payloadFileNames))
        let removedPayloadFileNames = Set(previouslyStoredItems.flatMap(\.payloadFileNames))
            .subtracting(retainedPayloadFileNames)
        let retainedThumbnailFileNames = Set(history.compactMap(\.thumbnailFileName))
        let removedThumbnailFileNames = Set(previouslyStoredItems.compactMap(\.thumbnailFileName))
            .subtracting(retainedThumbnailFileNames)

        try removeStoredFiles(at: payloadsDirectoryURL, named: removedPayloadFileNames)
        try removeStoredFiles(at: thumbnailsDirectoryURL, named: removedThumbnailFileNames)
    }

    private func removeStoredFiles(
        at directoryURL: URL,
        named fileNames: some Sequence<String>
    ) throws {
        for fileName in fileNames {
            let fileURL = directoryURL.appending(path: fileName)
            guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
                continue
            }

            try fileManager.removeItem(at: fileURL)
        }
    }
}

private struct StoredPayloadResult {
    var descriptor: ClipboardPayloadDescriptor
    var createdFileNames: [String]
}

private struct StoredThumbnailResult {
    var descriptor: ClipboardThumbnailDescriptor?
    var createdFileNames: [String]
}

private extension ClipboardHistoryItem {
    var payloadFileNames: [String] {
        switch payload {
        case let .inline(fileName, _, _):
            return [fileName]
        case let .figma(representations):
            return representations.map(\.fileName)
        case .fileReferences:
            return []
        }
    }

    var thumbnailFileName: String? {
        thumbnail?.fileName
    }
}
