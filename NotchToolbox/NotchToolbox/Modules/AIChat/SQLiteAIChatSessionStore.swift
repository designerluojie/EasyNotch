import Foundation
import SQLite3

final class SQLiteAIChatSessionStore: AIChatSessionStore {
    private let databaseURL: URL
    private var db: OpaquePointer?

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try open()
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    func latest() throws -> AIChatSession? {
        let sql = """
        SELECT id, title, selected_provider, selected_model_id, created_at, updated_at, last_message_at
        FROM sessions
        ORDER BY COALESCE(last_message_at, updated_at, created_at) DESC, updated_at DESC, created_at DESC
        LIMIT 1;
        """
        let rows = try querySessions(sql: sql)
        return rows.first
    }

    func loadAll() throws -> [AIChatSession] {
        let sql = """
        SELECT id, title, selected_provider, selected_model_id, created_at, updated_at, last_message_at
        FROM sessions
        ORDER BY COALESCE(last_message_at, updated_at, created_at) DESC, updated_at DESC, created_at DESC;
        """
        return try querySessions(sql: sql)
    }

    func loadMessages(for sessionID: UUID) throws -> [AIChatMessage] {
        let sql = """
        SELECT id, session_id, role, text, reasoning_text, status, created_at, updated_at
        FROM messages
        WHERE session_id = ?
        ORDER BY created_at ASC, updated_at ASC;
        """

        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }

        try bind(sessionID.uuidString, at: 1, in: statement)

        var messages: [AIChatMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            messages.append(try decodeMessage(statement))
        }
        return messages
    }

    func loadAttachments(for messageID: UUID) throws -> [AIChatAttachment] {
        let sql = """
        SELECT id, session_id, message_id, kind, mime_type, local_asset_path, preview_path, created_at
        FROM attachments
        WHERE message_id = ?
        ORDER BY created_at ASC;
        """

        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }

        try bind(messageID.uuidString, at: 1, in: statement)

        var attachments: [AIChatAttachment] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            attachments.append(try decodeAttachment(statement))
        }
        return attachments
    }

    func upsert(_ session: AIChatSession) throws {
        let sql = """
        INSERT INTO sessions (
            id, title, selected_provider, selected_model_id, created_at, updated_at, last_message_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            selected_provider = excluded.selected_provider,
            selected_model_id = excluded.selected_model_id,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            last_message_at = excluded.last_message_at;
        """

        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }

        try bindSession(session, into: statement)
        try execute(statement)
    }

    func append(_ message: AIChatMessage) throws {
        let sql = """
        INSERT INTO messages (
            id, session_id, role, text, reasoning_text, status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }

        try bindMessage(message, into: statement)
        try execute(statement)
        try touchSession(sessionID: message.sessionID, updatedAt: message.updatedAt, lastMessageAt: message.createdAt)
    }

    func append(_ attachment: AIChatAttachment) throws {
        guard try messageBelongsToSession(
            messageID: attachment.messageID,
            sessionID: attachment.sessionID
        ) else {
            throw SQLiteAIChatSessionStoreError.attachmentMessageSessionMismatch
        }

        let sql = """
        INSERT INTO attachments (
            id, session_id, message_id, kind, mime_type, local_asset_path, preview_path, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }

        try bindAttachment(attachment, into: statement)
        try execute(statement)
    }

    func update(_ message: AIChatMessage) throws {
        let sql = """
        UPDATE messages
        SET role = ?, text = ?, reasoning_text = ?, status = ?, created_at = ?, updated_at = ?
        WHERE id = ?;
        """

        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }

        try bind(message.role.rawValue, at: 1, in: statement)
        try bind(message.text, at: 2, in: statement)
        try bind(message.reasoningText, at: 3, in: statement)
        try bind(message.status.rawValue, at: 4, in: statement)
        sqlite3_bind_double(statement, 5, message.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 6, message.updatedAt.timeIntervalSince1970)
        try bind(message.id.uuidString, at: 7, in: statement)

        try execute(statement)
        try touchSession(sessionID: message.sessionID, updatedAt: message.updatedAt, lastMessageAt: nil)
    }

    func pruneHistory(olderThan cutoff: Date) throws {
        let attachmentPaths = try attachmentPathsForSessions(olderThan: cutoff)
        let sql = """
        DELETE FROM sessions
        WHERE COALESCE(last_message_at, updated_at, created_at) < ?;
        """

        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
        try execute(statement)

        attachmentPaths.forEach(cleanupFileIfPresent(atPath:))
    }
}

private extension SQLiteAIChatSessionStore {
    func open() throws {
        let directoryURL = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var connection: OpaquePointer?
        if sqlite3_open(databaseURL.path, &connection) != SQLITE_OK {
            let error = SQLiteAIChatSessionStoreError.databaseOpenFailed(message: Self.lastErrorMessage(from: connection))
            sqlite3_close(connection)
            throw error
        }

        db = connection
        try configureConnectionPragmas()
    }

    func configureConnectionPragmas() throws {
        try execute(sql: "PRAGMA foreign_keys = ON;")

        // WAL + synchronous=NORMAL: the default DELETE journal creates, fsyncs and
        // deletes a rollback journal on every write, and chat history churns on
        // each message append and stream settle. WAL removes that per-write journal
        // churn and lets reads proceed without blocking the writer. NORMAL stays
        // crash-safe under WAL (only a power loss can lose the last transaction,
        // acceptable for local chat history). journal_mode returns a row, so it
        // must go through sqlite3_exec rather than the DONE-expecting execute().
        if sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil) != SQLITE_OK {
            throw SQLiteAIChatSessionStoreError.statementExecutionFailed(
                message: Self.lastErrorMessage(from: db)
            )
        }
        try execute(sql: "PRAGMA synchronous = NORMAL;")
    }

    func migrate() throws {
        try execute(sql: """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            title TEXT,
            selected_provider TEXT NOT NULL,
            selected_model_id TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            last_message_at REAL
        );
        """)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            text TEXT NOT NULL,
            reasoning_text TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
        );
        """)

        try ensureColumnExists(
            table: "messages",
            column: "reasoning_text",
            definition: "TEXT NOT NULL DEFAULT ''"
        )

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS attachments (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            local_asset_path TEXT NOT NULL,
            preview_path TEXT NOT NULL,
            created_at REAL NOT NULL,
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
            FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE
        );
        """)

        // Every message/attachment lookup and every ON DELETE CASCADE filters by
        // these foreign keys; without indexes each is a full table scan.
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_messages_session_id ON messages(session_id);")
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_attachments_message_id ON attachments(message_id);")
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_attachments_session_id ON attachments(session_id);")
    }

    func ensureColumnExists(table: String, column: String, definition: String) throws {
        let columns = try tableColumns(table)
        guard !columns.contains(column) else { return }
        try execute(sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
    }

    func tableColumns(_ table: String) throws -> Set<String> {
        let statement = try prepareStatement("PRAGMA table_info(\(table));")
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            columns.insert(readString(column: 1, from: statement))
        }
        return columns
    }

    func querySessions(sql: String) throws -> [AIChatSession] {
        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }

        var sessions: [AIChatSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            sessions.append(try decodeSession(statement))
        }
        return sessions
    }

    func messageBelongsToSession(messageID: UUID, sessionID: UUID) throws -> Bool {
        let sql = """
        SELECT 1
        FROM messages
        WHERE id = ? AND session_id = ?
        LIMIT 1;
        """

        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }

        try bind(messageID.uuidString, at: 1, in: statement)
        try bind(sessionID.uuidString, at: 2, in: statement)

        return sqlite3_step(statement) == SQLITE_ROW
    }

    func attachmentPathsForSessions(olderThan cutoff: Date) throws -> [String] {
        let sql = """
        SELECT local_asset_path, preview_path
        FROM attachments
        WHERE session_id IN (
            SELECT id
            FROM sessions
            WHERE COALESCE(last_message_at, updated_at, created_at) < ?
        );
        """

        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)

        var paths: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            paths.append(readString(column: 0, from: statement))
            paths.append(readString(column: 1, from: statement))
        }
        return paths
    }

    func cleanupFileIfPresent(atPath path: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    func touchSession(sessionID: UUID, updatedAt: Date, lastMessageAt: Date?) throws {
        let sql: String
        if lastMessageAt == nil {
            sql = """
            UPDATE sessions
            SET updated_at = ?
            WHERE id = ?;
            """
        } else {
            sql = """
            UPDATE sessions
            SET updated_at = ?, last_message_at = ?
            WHERE id = ?;
            """
        }

        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, updatedAt.timeIntervalSince1970)
        if let lastMessageAt {
            sqlite3_bind_double(statement, 2, lastMessageAt.timeIntervalSince1970)
            try bind(sessionID.uuidString, at: 3, in: statement)
        } else {
            try bind(sessionID.uuidString, at: 2, in: statement)
        }

        try execute(statement)
    }

    func prepareStatement(_ sql: String) throws -> OpaquePointer? {
        guard let db else {
            throw SQLiteAIChatSessionStoreError.databaseUnavailable
        }

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteAIChatSessionStoreError.statementPreparationFailed(
                message: Self.lastErrorMessage(from: db)
            )
        }
        return statement
    }

    func execute(sql: String) throws {
        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }
        try execute(statement)
    }

    func execute(_ statement: OpaquePointer?) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw SQLiteAIChatSessionStoreError.statementExecutionFailed(
                message: Self.lastErrorMessage(from: db)
            )
        }
    }

    func bindSession(_ session: AIChatSession, into statement: OpaquePointer?) throws {
        try bind(session.id.uuidString, at: 1, in: statement)
        try bind(session.title, at: 2, in: statement)
        try bind(session.selectedProvider.rawValue, at: 3, in: statement)
        try bind(session.selectedModelID, at: 4, in: statement)
        sqlite3_bind_double(statement, 5, session.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 6, session.updatedAt.timeIntervalSince1970)
        if let lastMessageAt = session.lastMessageAt {
            sqlite3_bind_double(statement, 7, lastMessageAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 7)
        }
    }

    func bindMessage(_ message: AIChatMessage, into statement: OpaquePointer?) throws {
        try bind(message.id.uuidString, at: 1, in: statement)
        try bind(message.sessionID.uuidString, at: 2, in: statement)
        try bind(message.role.rawValue, at: 3, in: statement)
        try bind(message.text, at: 4, in: statement)
        try bind(message.reasoningText, at: 5, in: statement)
        try bind(message.status.rawValue, at: 6, in: statement)
        sqlite3_bind_double(statement, 7, message.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 8, message.updatedAt.timeIntervalSince1970)
    }

    func bindAttachment(_ attachment: AIChatAttachment, into statement: OpaquePointer?) throws {
        try bind(attachment.id.uuidString, at: 1, in: statement)
        try bind(attachment.sessionID.uuidString, at: 2, in: statement)
        try bind(attachment.messageID.uuidString, at: 3, in: statement)
        try bind(attachment.kind.rawValue, at: 4, in: statement)
        try bind(attachment.mimeType, at: 5, in: statement)
        try bind(attachment.localAssetPath, at: 6, in: statement)
        try bind(attachment.previewPath, at: 7, in: statement)
        sqlite3_bind_double(statement, 8, attachment.createdAt.timeIntervalSince1970)
    }

    func bind(_ value: String, at index: Int32, in statement: OpaquePointer?) throws {
        if sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) != SQLITE_OK {
            throw SQLiteAIChatSessionStoreError.statementBindingFailed(message: Self.lastErrorMessage(from: db))
        }
    }

    func bind(_ value: String?, at index: Int32, in statement: OpaquePointer?) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        try bind(value, at: index, in: statement)
    }

    func decodeSession(_ statement: OpaquePointer?) throws -> AIChatSession {
        AIChatSession(
            id: try readUUID(column: 0, from: statement),
            title: readOptionalString(column: 1, from: statement),
            selectedProvider: try readProvider(column: 2, from: statement),
            selectedModelID: readString(column: 3, from: statement),
            createdAt: readDate(column: 4, from: statement),
            updatedAt: readDate(column: 5, from: statement),
            lastMessageAt: readOptionalDate(column: 6, from: statement)
        )
    }

    func decodeMessage(_ statement: OpaquePointer?) throws -> AIChatMessage {
        AIChatMessage(
            id: try readUUID(column: 0, from: statement),
            sessionID: try readUUID(column: 1, from: statement),
            role: try readRole(column: 2, from: statement),
            text: readString(column: 3, from: statement),
            reasoningText: readString(column: 4, from: statement),
            status: try readStatus(column: 5, from: statement),
            createdAt: readDate(column: 6, from: statement),
            updatedAt: readDate(column: 7, from: statement)
        )
    }

    func decodeAttachment(_ statement: OpaquePointer?) throws -> AIChatAttachment {
        AIChatAttachment(
            id: try readUUID(column: 0, from: statement),
            sessionID: try readUUID(column: 1, from: statement),
            messageID: try readUUID(column: 2, from: statement),
            kind: try readAttachmentKind(column: 3, from: statement),
            mimeType: readString(column: 4, from: statement),
            localAssetPath: readString(column: 5, from: statement),
            previewPath: readString(column: 6, from: statement),
            createdAt: readDate(column: 7, from: statement)
        )
    }

    func readUUID(column: Int32, from statement: OpaquePointer?) throws -> UUID {
        guard let uuid = UUID(uuidString: readString(column: column, from: statement)) else {
            throw SQLiteAIChatSessionStoreError.decodingFailed
        }
        return uuid
    }

    func readProvider(column: Int32, from statement: OpaquePointer?) throws -> AIProviderKind {
        guard let provider = AIProviderKind(rawValue: readString(column: column, from: statement)) else {
            throw SQLiteAIChatSessionStoreError.decodingFailed
        }
        return provider
    }

    func readRole(column: Int32, from statement: OpaquePointer?) throws -> AIChatMessageRole {
        guard let role = AIChatMessageRole(rawValue: readString(column: column, from: statement)) else {
            throw SQLiteAIChatSessionStoreError.decodingFailed
        }
        return role
    }

    func readStatus(column: Int32, from statement: OpaquePointer?) throws -> AIChatMessageStatus {
        guard let status = AIChatMessageStatus(rawValue: readString(column: column, from: statement)) else {
            throw SQLiteAIChatSessionStoreError.decodingFailed
        }
        return status
    }

    func readAttachmentKind(column: Int32, from statement: OpaquePointer?) throws -> AIChatAttachmentKind {
        guard let kind = AIChatAttachmentKind(rawValue: readString(column: column, from: statement)) else {
            throw SQLiteAIChatSessionStoreError.decodingFailed
        }
        return kind
    }

    func readString(column: Int32, from statement: OpaquePointer?) -> String {
        guard let value = sqlite3_column_text(statement, column) else {
            return ""
        }
        return String(cString: value)
    }

    func readOptionalString(column: Int32, from statement: OpaquePointer?) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        return readString(column: column, from: statement)
    }

    func readDate(column: Int32, from statement: OpaquePointer?) -> Date {
        Date(timeIntervalSince1970: sqlite3_column_double(statement, column))
    }

    func readOptionalDate(column: Int32, from statement: OpaquePointer?) -> Date? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        return readDate(column: column, from: statement)
    }

    static func lastErrorMessage(from db: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(db) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }
}

private enum SQLiteAIChatSessionStoreError: Error {
    case databaseUnavailable
    case databaseOpenFailed(message: String)
    case statementPreparationFailed(message: String)
    case statementBindingFailed(message: String)
    case statementExecutionFailed(message: String)
    case attachmentMessageSessionMismatch
    case decodingFailed
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
