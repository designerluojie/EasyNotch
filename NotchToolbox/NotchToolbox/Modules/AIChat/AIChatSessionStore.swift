import Foundation

protocol AIChatSessionStore {
    func latest() throws -> AIChatSession?
    func loadAll() throws -> [AIChatSession]
    func loadMessages(for sessionID: UUID) throws -> [AIChatMessage]
    func loadAttachments(for messageID: UUID) throws -> [AIChatAttachment]
    func upsert(_ session: AIChatSession) throws
    func append(_ message: AIChatMessage) throws
    func append(_ attachment: AIChatAttachment) throws
    func update(_ message: AIChatMessage) throws
    func pruneHistory(olderThan cutoff: Date) throws
}

protocol AIChatHistoryPruning: AnyObject {
    func pruneIfNeeded() async
}

final class AIChatHistoryPruner: AIChatHistoryPruning {
    private let settingsStore: SettingsStore
    private let sessionStoreFactory: () throws -> any AIChatSessionStore
    private let nowProvider: () -> Date
    private let calendar: Calendar

    convenience init(sharedServices: SharedCoreServices) {
        self.init(
            settingsStore: sharedServices.settingsStore,
            sessionStoreFactory: {
                try SQLiteAIChatSessionStore(
                    databaseURL: sharedServices.localFileStore
                        .url(for: .aiChat)
                        .appending(path: "sessions.sqlite")
                )
            }
        )
    }

    init(
        settingsStore: SettingsStore,
        sessionStoreFactory: @escaping () throws -> any AIChatSessionStore,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.settingsStore = settingsStore
        self.sessionStoreFactory = sessionStoreFactory
        self.nowProvider = now
        self.calendar = calendar
    }

    func pruneIfNeeded() async {
        try? await pruneIfNeeded(now: nowProvider())
    }

    func pruneIfNeeded(now: Date) async throws {
        let lastPrunedAt = await MainActor.run {
            settingsStore.settings.lastAIChatHistoryPrunedAt
        }
        guard Self.shouldPrune(lastPrunedAt: lastPrunedAt, now: now) else {
            return
        }

        let sessionStore = try sessionStoreFactory()
        try sessionStore.pruneHistory(olderThan: historyRetentionCutoff(now: now))
        try await MainActor.run {
            try settingsStore.update { settings in
                settings.lastAIChatHistoryPrunedAt = now
            }
        }
    }

    nonisolated static func shouldPrune(lastPrunedAt: Date?, now: Date) -> Bool {
        guard let lastPrunedAt else {
            return true
        }

        return now.timeIntervalSince(lastPrunedAt) >= 24 * 60 * 60
    }

    private func historyRetentionCutoff(now: Date) -> Date {
        calendar.date(byAdding: .month, value: -3, to: now)
            ?? now.addingTimeInterval(-90 * 24 * 60 * 60)
    }
}

struct AIChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    var role: AIChatMessageRole
    var text: String
    var reasoningText: String
    var status: AIChatMessageStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        sessionID: UUID,
        role: AIChatMessageRole,
        text: String,
        reasoningText: String = "",
        status: AIChatMessageStatus,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.text = text
        self.reasoningText = reasoningText
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case role
        case text
        case reasoningText
        case status
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.sessionID = try container.decode(UUID.self, forKey: .sessionID)
        self.role = try container.decode(AIChatMessageRole.self, forKey: .role)
        self.text = try container.decode(String.self, forKey: .text)
        self.reasoningText = try container.decodeIfPresent(String.self, forKey: .reasoningText) ?? ""
        self.status = try container.decode(AIChatMessageStatus.self, forKey: .status)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

enum AIChatAttachmentKind: String, Codable, Equatable {
    case image
}

struct AIChatAttachment: Identifiable, Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    let messageID: UUID
    var kind: AIChatAttachmentKind
    var mimeType: String
    var localAssetPath: String
    var previewPath: String
    var createdAt: Date
}
