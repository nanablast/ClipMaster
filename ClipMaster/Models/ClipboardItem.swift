import Foundation
import GRDB

enum ContentType: String, Codable, DatabaseValueConvertible {
    case text
    case image
    case link
    case file
}

struct ClipboardItem: Identifiable, Equatable {
    var id: UUID
    var content: String
    var type: ContentType
    var appSource: String?
    var createdAt: Date
    var imagePath: String?
    var imageHash: String?

    init(
        id: UUID = UUID(),
        content: String,
        type: ContentType,
        appSource: String? = nil,
        createdAt: Date = Date(),
        imagePath: String? = nil,
        imageHash: String? = nil
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.appSource = appSource
        self.createdAt = createdAt
        self.imagePath = imagePath
        self.imageHash = imageHash
    }
}

// MARK: - GRDB Support

extension ClipboardItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "clipboardItems"

    enum Columns: String, ColumnExpression {
        case id, content, type, appSource, createdAt, imagePath, imageHash
    }

    // Only persist these columns (excludes old imageData)
    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["content"] = content
        container["type"] = type
        container["appSource"] = appSource
        container["createdAt"] = createdAt
        container["imagePath"] = imagePath
        container["imageHash"] = imageHash
    }

    init(row: Row) throws {
        id = row["id"]
        content = row["content"]
        type = row["type"]
        appSource = row["appSource"]
        createdAt = row["createdAt"]
        imagePath = row["imagePath"]
        imageHash = row["imageHash"]
    }
}
