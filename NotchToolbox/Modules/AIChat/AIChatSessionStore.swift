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
        let (lastPrunedAt, retention) = await MainActor.run {
            (
                settingsStore.settings.lastAIChatHistoryPrunedAt,
                settingsStore.settings.aiChatHistoryRetention
            )
        }
        guard shouldPrune(lastPrunedAt: lastPrunedAt, retentionMonths: retention.months, now: now) else {
            return
        }

        let sessionStore = try sessionStoreFactory()
        try sessionStore.pruneHistory(
            olderThan: historyRetentionCutoff(now: now, months: retention.months)
        )
        try await MainActor.run {
            try settingsStore.update { settings in
                settings.lastAIChatHistoryPrunedAt = now
            }
        }
    }

    // Due one retention window after the last prune, counted from the last
    // actual prune rather than from whenever the setting changed. So shortening
    // the window (e.g. 3mo -> 1mo) can make a prune due immediately if that much
    // time already elapsed since the last prune, while lengthening it (1mo ->
    // 3mo) pushes the next run further out from where it already was.
    private func shouldPrune(lastPrunedAt: Date?, retentionMonths: Int, now: Date) -> Bool {
        guard let lastPrunedAt else {
            return true
        }

        guard let nextDueAt = calendar.date(byAdding: .month, value: retentionMonths, to: lastPrunedAt) else {
            return true
        }

        return now >= nextDueAt
    }

    private func historyRetentionCutoff(now: Date, months: Int) -> Date {
        calendar.date(byAdding: .month, value: -months, to: now)
            ?? now.addingTimeInterval(-Double(months) * 30 * 24 * 60 * 60)
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
