import Foundation
import GRDB

final class StorageService {
    enum Mode: Equatable {
        case readWrite
        case readOnly
    }

    enum StorageError: LocalizedError {
        case readOnlyMode

        var errorDescription: String? {
            switch self {
            case .readOnlyMode:
                return "Storage is running in read-only mode."
            }
        }
    }

    static let shared = StorageService()
    private static let ftsTableName = "clipboardItemsFTS"
    private static let ftsInsertTriggerName = "clipboardItems_ai_fts"
    private static let ftsUpdateTriggerName = "clipboardItems_au_fts"
    private static let ftsDeleteTriggerName = "clipboardItems_ad_fts"

    private let imageCacheDir: URL
    private var dbQueue: DatabaseQueue!
    private(set) var mode: Mode = .readWrite
    private(set) var startupWarningMessage: String?

    private init() {
        self.imageCacheDir = Self.defaultImageCacheDir()
        do {
            try setupDatabase()
            mode = .readWrite
        } catch let initialError {
            AppLogger.storage.error("Database setup failed: \(initialError.localizedDescription, privacy: .public)")

            if shouldAttemptDatabaseRecovery(after: initialError) {
                do {
                    let backupLocation: URL?
                    do {
                        backupLocation = try backupDatabaseFiles()
                    } catch {
                        AppLogger.storage.error("Database backup before recovery failed: \(error.localizedDescription, privacy: .public)")
                        backupLocation = nil
                    }
                    try recoverDatabase(after: initialError, backupLocation: backupLocation)
                    mode = .readWrite
                    return
                } catch {
                    AppLogger.storage.error("Database recovery failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            if !setupReadOnlyFallback(after: initialError) {
                do {
                    dbQueue = try DatabaseQueue()
                    try migrator.migrate(dbQueue)
                    mode = .readOnly
                    startupWarningMessage = "数据库不可用，已进入只读降级模式。"
                    AppLogger.storage.error("Storage switched to in-memory read-only fallback")
                } catch {
                    fatalError("Failed to setup storage fallback: \(error)")
                }
            }
        }
    }

    init(databasePath: String, imageCacheDir: URL) throws {
        self.imageCacheDir = imageCacheDir
        try setupDatabase(atPath: databasePath)
    }

    private func setupDatabase() throws {
        let fileManager = FileManager.default
        let appDirectory = Self.defaultAppDirectory()

        if !fileManager.fileExists(atPath: appDirectory.path) {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        let dbPath = Self.defaultDatabaseURL().path
        try setupDatabase(atPath: dbPath)
    }

    private func setupDatabase(atPath path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrator.migrate(dbQueue)
    }

    private func setupReadOnlyFallback(after initialError: Error) -> Bool {
        let dbURL = Self.defaultDatabaseURL()
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            startupWarningMessage = "数据库初始化失败，已进入只读降级模式。"
            return false
        }

        do {
            var configuration = Configuration()
            configuration.readonly = true
            dbQueue = try DatabaseQueue(path: dbURL.path, configuration: configuration)
            mode = .readOnly
            startupWarningMessage = "数据库异常，已进入只读模式。建议备份后重新部署。"
            AppLogger.storage.error(
                "Storage opened in read-only fallback mode after startup error: \(initialError.localizedDescription, privacy: .public)"
            )
            return true
        } catch {
            AppLogger.storage.error("Read-only fallback setup failed: \(error.localizedDescription, privacy: .public)")
            startupWarningMessage = "数据库异常，已进入只读降级模式。"
            return false
        }
    }

    private static func defaultImageCacheDir() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("ClipMaster/images", isDirectory: true)
    }

    private static func defaultAppDirectory() -> URL {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupportURL.appendingPathComponent("ClipMaster", isDirectory: true)
    }

    private static func defaultDatabaseURL() -> URL {
        defaultAppDirectory().appendingPathComponent(Constants.databaseFileName)
    }

    private func recoverDatabase(after initialError: Error, backupLocation: URL?) throws {
        let fileManager = FileManager.default
        let appDirectory = Self.defaultAppDirectory()
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        let dbURL = Self.defaultDatabaseURL()
        for suffix in ["", "-wal", "-shm"] {
            let path = dbURL.path + suffix
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(atPath: path)
            }
        }

        try setupDatabase(atPath: dbURL.path)
        if let backupLocation {
            AppLogger.storage.notice(
                "Database recovered from startup error (\(initialError.localizedDescription, privacy: .public)); backup: \(backupLocation.path, privacy: .public)"
            )
        } else {
            AppLogger.storage.notice(
                "Database recovered from startup error (\(initialError.localizedDescription, privacy: .public))"
            )
        }
    }

    private func shouldAttemptDatabaseRecovery(after error: Error) -> Bool {
        guard let dbError = error as? DatabaseError else {
            return false
        }
        return dbError.resultCode == .SQLITE_CORRUPT || dbError.resultCode == .SQLITE_NOTADB
    }

    private func backupDatabaseFiles() throws -> URL? {
        let fileManager = FileManager.default
        let appDirectory = Self.defaultAppDirectory()
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        let backupDirectory = appDirectory.appendingPathComponent("db-backups", isDirectory: true)
        if !fileManager.fileExists(atPath: backupDirectory.path) {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }

        let timestamp = Self.makeRecoveryTimestamp()
        let baseBackupURL = backupDirectory.appendingPathComponent("ClipMaster-\(timestamp).sqlite")
        let dbURL = Self.defaultDatabaseURL()

        var copiedAny = false
        for suffix in ["", "-wal", "-shm"] {
            let sourcePath = dbURL.path + suffix
            guard fileManager.fileExists(atPath: sourcePath) else { continue }
            let destinationPath = baseBackupURL.path + suffix
            try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
            copiedAny = true
        }
        return copiedAny ? baseBackupURL : nil
    }

    private static func makeRecoveryTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: ClipboardItem.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("content", .text).notNull()
                t.column("type", .text).notNull()
                t.column("appSource", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("imageData", .blob)
            }

            try db.create(
                index: "idx_clipboardItems_createdAt",
                on: ClipboardItem.databaseTableName,
                columns: ["createdAt"]
            )
            try db.create(
                index: "idx_clipboardItems_content",
                on: ClipboardItem.databaseTableName,
                columns: ["content"]
            )
        }

        migrator.registerMigration("v2_imagePath") { db in
            try db.alter(table: ClipboardItem.databaseTableName) { t in
                t.add(column: "imagePath", .text)
            }
            // Clear old BLOB data
            try db.execute(sql: "UPDATE clipboardItems SET imageData = NULL")
        }

        migrator.registerMigration("v3_imageHash") { db in
            try db.alter(table: ClipboardItem.databaseTableName) { t in
                t.add(column: "imageHash", .text)
            }
            try db.create(
                index: "idx_clipboardItems_imageHash",
                on: ClipboardItem.databaseTableName,
                columns: ["imageHash"]
            )
        }

        migrator.registerMigration("v4_appSourceIndex") { db in
            try db.execute(
                sql: "CREATE INDEX IF NOT EXISTS idx_clipboardItems_appSource ON clipboardItems(appSource)"
            )
        }

        migrator.registerMigration("v5_searchFTS") { db in
            guard try Self.isFTS5Available(in: db) else { return }
            try Self.createFTSObjects(in: db)
            try Self.rebuildFTSIndex(in: db)
        }

        migrator.registerMigration("v6_ftsTriggerRefresh") { db in
            guard try Self.isFTS5Available(in: db) else { return }
            try Self.dropFTSTriggers(in: db)
            try Self.createFTSObjects(in: db)
            try Self.rebuildFTSIndex(in: db)
        }

        return migrator
    }

    private static func isFTS5Available(in db: Database) throws -> Bool {
        let enabled: Int? = try Int.fetchOne(
            db,
            sql: "SELECT sqlite_compileoption_used('ENABLE_FTS5')"
        )
        return (enabled ?? 0) == 1
    }

    private static func createFTSObjects(in db: Database) throws {
        try db.execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS \(ftsTableName)
            USING fts5(
                id UNINDEXED,
                content,
                appSource,
                tokenize='unicode61'
            )
            """)

        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS \(ftsInsertTriggerName)
            AFTER INSERT ON \(ClipboardItem.databaseTableName)
            BEGIN
                INSERT INTO \(ftsTableName)(rowid, id, content, appSource)
                VALUES (new.rowid, new.id, new.content, coalesce(new.appSource, ''));
            END
            """)

        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS \(ftsUpdateTriggerName)
            AFTER UPDATE ON \(ClipboardItem.databaseTableName)
            BEGIN
                DELETE FROM \(ftsTableName) WHERE rowid = old.rowid;
                INSERT INTO \(ftsTableName)(rowid, id, content, appSource)
                VALUES (new.rowid, new.id, new.content, coalesce(new.appSource, ''));
            END
            """)

        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS \(ftsDeleteTriggerName)
            AFTER DELETE ON \(ClipboardItem.databaseTableName)
            BEGIN
                DELETE FROM \(ftsTableName) WHERE rowid = old.rowid;
            END
            """)
    }

    private static func dropFTSTriggers(in db: Database) throws {
        try db.execute(sql: "DROP TRIGGER IF EXISTS \(ftsInsertTriggerName)")
        try db.execute(sql: "DROP TRIGGER IF EXISTS \(ftsUpdateTriggerName)")
        try db.execute(sql: "DROP TRIGGER IF EXISTS \(ftsDeleteTriggerName)")
    }

    private static func rebuildFTSIndex(in db: Database) throws {
        try db.execute(sql: "DELETE FROM \(ftsTableName)")
        try db.execute(sql: """
            INSERT INTO \(ftsTableName)(rowid, id, content, appSource)
            SELECT rowid, id, content, coalesce(appSource, '')
            FROM \(ClipboardItem.databaseTableName)
            """)
    }

    // MARK: - Image File Management

    /// Save image data to cache directory. Returns the filename.
    func saveImageFile(_ data: Data, id: UUID) -> String? {
        if mode == .readOnly {
            return nil
        }

        let filename = "\(id.uuidString).png"
        let fileURL = imageCacheDir.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: imageCacheDir, withIntermediateDirectories: true)
            try data.write(to: fileURL)
            return filename
        } catch {
            AppLogger.storage.error("Failed to save image file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Load image data from cache directory.
    func loadImageData(filename: String) -> Data? {
        let fileURL = imageCacheDir.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }

    /// Load image data by item ID (convenience).
    func fetchImageData(for itemId: UUID) throws -> Data? {
        let item = try dbQueue.read { db in
            try ClipboardItem.fetchOne(db, key: itemId)
        }
        guard let path = item?.imagePath else { return nil }
        return loadImageData(filename: path)
    }

    /// Delete the entire image cache directory. Called on app launch.
    func clearImageCache() {
        try? FileManager.default.removeItem(at: imageCacheDir)
    }

    /// Expire image entries after clearing session cache.
    /// Keeps OCR text by downgrading image rows to text when possible.
    func expireSessionImages() {
        guard mode == .readWrite else { return }
        do {
            try dbQueue.write { db in
                let imageItems = try ClipboardItem
                    .filter(ClipboardItem.Columns.type == ContentType.image.rawValue)
                    .fetchAll(db)

                for item in imageItems {
                    let normalized = item.content.trimmingCharacters(in: .whitespacesAndNewlines)

                    if normalized.isEmpty || normalized == Constants.imagePlaceholderText {
                        if let path = item.imagePath {
                            removeImageFile(filename: path)
                        }
                        _ = try item.delete(db)
                        continue
                    }

                    var downgraded = item
                    downgraded.type = .text
                    downgraded.imagePath = nil
                    downgraded.imageHash = nil
                    try downgraded.update(db)
                }
            }
        } catch {
            AppLogger.storage.error("Failed to expire session images: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - CRUD Operations

    func insert(_ item: ClipboardItem) throws {
        try ensureWritable()
        try dbQueue.write { db in
            let duplicateItems = try findDuplicateItems(for: item, in: db)
            for duplicate in duplicateItems {
                if let path = duplicate.imagePath {
                    removeImageFile(filename: path)
                }
                _ = try duplicate.delete(db)
            }

            try item.insert(db)
        }

        try enforceMaxHistoryCount()
    }

    func fetchAll(limit: Int = 50, offset: Int = 0) throws -> [ClipboardItem] {
        try dbQueue.read { db in
            try ClipboardItem
                .order(ClipboardItem.Columns.createdAt.desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }

    func search(keyword: String, limit: Int = 50, offset: Int = 0) throws -> [ClipboardItem] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try fetchAll(limit: limit, offset: offset)
        }

        return try dbQueue.read { db in
            if let ftsQuery = makeFTSQuery(for: trimmed), try isFTSEnabled(in: db) {
                do {
                    let ftsResults = try fetchUsingFTS(
                        in: db,
                        query: ftsQuery,
                        limit: limit,
                        offset: offset
                    )
                    // Keep LIKE fallback for edge cases such as infix-only matches.
                    if !ftsResults.isEmpty || offset > 0 {
                        return ftsResults
                    }
                } catch {
                    AppLogger.storage.error("FTS search failed; fallback to LIKE: \(error.localizedDescription, privacy: .public)")
                    // Fallback to LIKE search
                }
            }

            let likePattern = makeEscapedLikePattern(for: trimmed)
            return try ClipboardItem
                .filter(makeSearchFilter(pattern: likePattern))
                .order(ClipboardItem.Columns.createdAt.desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }

    func searchCount(keyword: String) throws -> Int {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try totalCount()
        }

        return try dbQueue.read { db in
            if let ftsQuery = makeFTSQuery(for: trimmed), try isFTSEnabled(in: db) {
                do {
                    let ftsCount = try fetchCountUsingFTS(in: db, query: ftsQuery)
                    if ftsCount > 0 {
                        return ftsCount
                    }
                } catch {
                    AppLogger.storage.error("FTS count failed; fallback to LIKE: \(error.localizedDescription, privacy: .public)")
                    // Fallback to LIKE count
                }
            }

            let likePattern = makeEscapedLikePattern(for: trimmed)
            return try ClipboardItem
                .filter(makeSearchFilter(pattern: likePattern))
                .fetchCount(db)
        }
    }

    func delete(_ item: ClipboardItem) throws {
        try ensureWritable()
        // Delete associated image file
        if let path = item.imagePath {
            removeImageFile(filename: path)
        }
        try dbQueue.write { db in
            _ = try item.delete(db)
        }
    }

    func deleteAll() throws {
        try ensureWritable()
        clearImageCache()
        try dbQueue.write { db in
            _ = try ClipboardItem.deleteAll(db)
        }
    }

    func totalCount() throws -> Int {
        try dbQueue.read { db in
            try ClipboardItem.fetchCount(db)
        }
    }

    // MARK: - History Limit

    private func enforceMaxHistoryCount() throws {
        try ensureWritable()
        let defaults = UserDefaults.standard
        let key = Constants.UserDefaultsKeys.maxHistoryCount
        let storedValue = defaults.object(forKey: key) as? Int
        let limit: Int
        if let storedValue {
            let normalized = Constants.normalizedMaxHistoryCount(storedValue)
            if normalized != storedValue {
                defaults.set(normalized, forKey: key)
            }
            limit = normalized
        } else {
            limit = Constants.defaultMaxHistoryCount
        }

        try dbQueue.write { db in
            let count = try ClipboardItem.fetchCount(db)
            if count > limit {
                let overflow = count - limit
                let oldestItems = try ClipboardItem
                    .order(ClipboardItem.Columns.createdAt.asc)
                    .limit(overflow)
                    .fetchAll(db)
                for item in oldestItems {
                    // Delete associated image file
                    if let path = item.imagePath {
                        removeImageFile(filename: path)
                    }
                    _ = try item.delete(db)
                }
            }
        }
    }

    private func removeImageFile(filename: String) {
        let fileURL = imageCacheDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func ensureWritable() throws {
        guard mode == .readWrite else {
            throw StorageError.readOnlyMode
        }
    }

    private func findDuplicateItems(for item: ClipboardItem, in db: Database) throws -> [ClipboardItem] {
        switch item.type {
        case .image:
            guard let imageHash = item.imageHash, !imageHash.isEmpty else {
                return []
            }
            return try ClipboardItem
                .filter(ClipboardItem.Columns.type == ContentType.image.rawValue)
                .filter(ClipboardItem.Columns.imageHash == imageHash)
                .fetchAll(db)
        case .text, .link, .file:
            return try ClipboardItem
                .filter(ClipboardItem.Columns.content == item.content)
                .filter(ClipboardItem.Columns.type == item.type)
                .fetchAll(db)
        }
    }

    private func isFTSEnabled(in db: Database) throws -> Bool {
        try db.tableExists(Self.ftsTableName)
    }

    private func makeFTSQuery(for keyword: String) -> String? {
        let terms = keyword
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }

        let escapedTerms = terms.map { term in
            let escaped = term.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\"*"
        }
        return escapedTerms.joined(separator: " AND ")
    }

    private func fetchUsingFTS(
        in db: Database,
        query: String,
        limit: Int,
        offset: Int
    ) throws -> [ClipboardItem] {
        try ClipboardItem.fetchAll(
            db,
            sql: """
                SELECT clipboardItems.*
                FROM clipboardItems
                JOIN \(Self.ftsTableName)
                ON \(Self.ftsTableName).rowid = clipboardItems.rowid
                WHERE \(Self.ftsTableName) MATCH ?
                ORDER BY clipboardItems.createdAt DESC
                LIMIT ? OFFSET ?
                """,
            arguments: [query, limit, offset]
        )
    }

    private func fetchCountUsingFTS(in db: Database, query: String) throws -> Int {
        try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM \(Self.ftsTableName)
                WHERE \(Self.ftsTableName) MATCH ?
                """,
            arguments: [query]
        ) ?? 0
    }

    private func makeEscapedLikePattern(for keyword: String) -> String {
        let escaped = keyword
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }

    private func makeSearchFilter(pattern: String) -> SQLSpecificExpressible {
        ClipboardItem.Columns.content.like(pattern, escape: "\\")
            || ClipboardItem.Columns.appSource.like(pattern, escape: "\\")
    }
}
