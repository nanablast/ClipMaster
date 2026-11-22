import XCTest
@testable import ClipMaster

final class StorageServiceTests: XCTestCase {
    private var tempRoot: URL!
    private var storage: StorageService!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipMasterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let databasePath = tempRoot.appendingPathComponent("test.sqlite").path
        let imageCacheDir = tempRoot.appendingPathComponent("images", isDirectory: true)
        storage = try StorageService(databasePath: databasePath, imageCacheDir: imageCacheDir)
    }

    override func tearDownWithError() throws {
        storage = nil
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
    }

    func testTextDedupKeepsLatestItem() throws {
        let first = ClipboardItem(content: "same-text", type: .text, appSource: "AppA")
        let second = ClipboardItem(content: "same-text", type: .text, appSource: "AppB")

        try storage.insert(first)
        try storage.insert(second)

        let all = try storage.fetchAll(limit: 10)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.content, "same-text")
        XCTAssertEqual(all.first?.type, .text)
        XCTAssertEqual(all.first?.appSource, "AppB")
    }

    func testImageDedupUsesImageHash() throws {
        let imageA = ClipboardItem(
            content: Constants.imagePlaceholderText,
            type: .image,
            appSource: "A",
            imageHash: "hash-a"
        )
        let imageB = ClipboardItem(
            content: Constants.imagePlaceholderText,
            type: .image,
            appSource: "B",
            imageHash: "hash-b"
        )
        let imageADuplicate = ClipboardItem(
            content: Constants.imagePlaceholderText,
            type: .image,
            appSource: "A2",
            imageHash: "hash-a"
        )

        try storage.insert(imageA)
        try storage.insert(imageB)
        try storage.insert(imageADuplicate)

        let all = try storage.fetchAll(limit: 10)
        XCTAssertEqual(all.count, 2)

        let hashAItems = all.filter { $0.imageHash == "hash-a" }
        XCTAssertEqual(hashAItems.count, 1)
        XCTAssertEqual(hashAItems.first?.appSource, "A2")
    }

    func testExpireSessionImagesDowngradesOrRemovesImageItems() throws {
        let keepID = UUID()
        let removeID = UUID()

        let keepPath = storage.saveImageFile(Data([0x01, 0x02]), id: keepID)
        let removePath = storage.saveImageFile(Data([0x03, 0x04]), id: removeID)

        let keepItem = ClipboardItem(
            id: keepID,
            content: "识别文本",
            type: .image,
            imagePath: keepPath,
            imageHash: "hash-keep"
        )
        let removeItem = ClipboardItem(
            id: removeID,
            content: Constants.imagePlaceholderText,
            type: .image,
            imagePath: removePath,
            imageHash: "hash-remove"
        )

        try storage.insert(keepItem)
        try storage.insert(removeItem)

        storage.clearImageCache()
        storage.expireSessionImages()

        let all = try storage.fetchAll(limit: 10)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.content, "识别文本")
        XCTAssertEqual(all.first?.type, .text)
        XCTAssertNil(all.first?.imagePath)
        XCTAssertNil(all.first?.imageHash)
    }

    func testSearchEscapesLikeWildcardsAsLiteralText() throws {
        try storage.insert(ClipboardItem(content: "100% match", type: .text))
        try storage.insert(ClipboardItem(content: "foo_bar", type: .text))
        try storage.insert(ClipboardItem(content: "plain text", type: .text))

        let percentMatches = try storage.search(keyword: "%", limit: 20)
        XCTAssertEqual(Set(percentMatches.map(\.content)), Set(["100% match"]))

        let underscoreMatches = try storage.search(keyword: "_", limit: 20)
        XCTAssertEqual(Set(underscoreMatches.map(\.content)), Set(["foo_bar"]))
    }

    func testSearchSupportsOffsetAndCount() throws {
        try storage.insert(ClipboardItem(content: "keyword one", type: .text))
        try storage.insert(ClipboardItem(content: "keyword two", type: .text))
        try storage.insert(ClipboardItem(content: "keyword three", type: .text))

        let total = try storage.searchCount(keyword: "keyword")
        XCTAssertEqual(total, 3)

        let page1 = try storage.search(keyword: "keyword", limit: 2, offset: 0)
        XCTAssertEqual(page1.count, 2)

        let page2 = try storage.search(keyword: "keyword", limit: 2, offset: 2)
        XCTAssertEqual(page2.count, 1)

        XCTAssertEqual(Set(page1.map(\.id)).intersection(Set(page2.map(\.id))).count, 0)
    }

    func testSearchMatchesAppSource() throws {
        try storage.insert(ClipboardItem(content: "plain content", type: .text, appSource: "Safari"))
        try storage.insert(ClipboardItem(content: "another content", type: .text, appSource: "Notes"))

        let matches = try storage.search(keyword: "safa", limit: 20)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.appSource, "Safari")
    }

    func testSearchFallsBackToLikeForInfixAppSourceMatch() throws {
        try storage.insert(ClipboardItem(content: "plain content", type: .text, appSource: "Safari"))
        try storage.insert(ClipboardItem(content: "another content", type: .text, appSource: "Notes"))

        let matches = try storage.search(keyword: "afar", limit: 20)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.appSource, "Safari")

        let count = try storage.searchCount(keyword: "afar")
        XCTAssertEqual(count, 1)
    }

    func testFTSTriggersKeepDuplicateDeletePathHealthy() throws {
        try storage.insert(ClipboardItem(content: "duplicate text", type: .text, appSource: "A"))
        try storage.insert(ClipboardItem(content: "duplicate text", type: .text, appSource: "B"))

        let all = try storage.fetchAll(limit: 10)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.appSource, "B")
    }

    func testFTSTriggersKeepExpireSessionUpdatePathHealthy() throws {
        let id = UUID()
        let path = storage.saveImageFile(Data([0x11, 0x22]), id: id)
        let image = ClipboardItem(
            id: id,
            content: "ocr keep text",
            type: .image,
            imagePath: path,
            imageHash: "hash-update"
        )
        try storage.insert(image)

        storage.expireSessionImages()

        let matches = try storage.search(keyword: "ocr keep", limit: 10)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.type, .text)
    }

    func testExpireSessionImagesTreatsWhitespaceOnlyAsEmptyAndDeletes() throws {
        let blankID = UUID()
        let newlineID = UUID()
        let textID = UUID()
        let blankPath = storage.saveImageFile(Data([0x01]), id: blankID)
        let newlinePath = storage.saveImageFile(Data([0x02]), id: newlineID)
        let textPath = storage.saveImageFile(Data([0x03]), id: textID)

        try storage.insert(ClipboardItem(
            id: blankID,
            content: "   ",
            type: .image,
            imagePath: blankPath,
            imageHash: "hash-blank"
        ))
        try storage.insert(ClipboardItem(
            id: newlineID,
            content: "\n\t\r ",
            type: .image,
            imagePath: newlinePath,
            imageHash: "hash-newline"
        ))
        try storage.insert(ClipboardItem(
            id: textID,
            content: "  有文本  ",
            type: .image,
            imagePath: textPath,
            imageHash: "hash-text"
        ))
        // Non-image rows must never be touched by the expire pass.
        try storage.insert(ClipboardItem(content: "plain", type: .text, appSource: "KeepMe"))

        // Session cache is cleared at startup; files are gone before rows are reaped.
        storage.clearImageCache()
        storage.expireSessionImages()

        let all = try storage.fetchAll(limit: 10)
        XCTAssertEqual(all.count, 2)

        let remainingText = all.first { $0.content == "  有文本  " }
        XCTAssertNotNil(remainingText)
        XCTAssertEqual(remainingText?.type, .text)
        XCTAssertNil(remainingText?.imagePath)
        XCTAssertNil(remainingText?.imageHash)

        XCTAssertNotNil(all.first { $0.content == "plain" })
        XCTAssertTrue(all.allSatisfy { $0.type == .text })
    }

    func testHistoryLimitUsesClampedMinimumSetting() throws {
        let defaults = UserDefaults.standard
        let key = Constants.UserDefaultsKeys.maxHistoryCount
        let previous = defaults.object(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(1, forKey: key)

        for index in 0..<60 {
            try storage.insert(ClipboardItem(content: "item-\(index)", type: .text))
        }

        let count = try storage.totalCount()
        XCTAssertEqual(count, Constants.minMaxHistoryCount)
    }

    func testMigrateLegacyCachedImagesMovesFilesAndClearsEmptyLegacyDir() throws {
        let rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipMasterMigration-\(UUID().uuidString)", isDirectory: true)
        let primaryDir = rootDir.appendingPathComponent("primary/images", isDirectory: true)
        let legacyDir = rootDir.appendingPathComponent("legacy/images", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let sampleBytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4])
        try sampleBytes.write(to: legacyDir.appendingPathComponent("legacy-1.png"))

        let storage = try StorageService(
            databasePath: rootDir.appendingPathComponent("db.sqlite").path,
            imageCacheDir: primaryDir,
            legacyImageCacheDir: legacyDir
        )

        storage.migrateLegacyCachedImagesIfNeeded()

        XCTAssertEqual(storage.loadImageData(filename: "legacy-1.png"), sampleBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryDir.appendingPathComponent("legacy-1.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDir.path))
    }

    func testPersistedImageLimitsDowngradeOCRAndPruneOverflowOnInsertAndReconcile() throws {
        let rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipMasterCap-\(UUID().uuidString)", isDirectory: true)
        let imageDir = rootDir.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let storage = try StorageService(
            databasePath: rootDir.appendingPathComponent("db.sqlite").path,
            imageCacheDir: imageDir,
            maxPersistedImageCount: 2,
            maxPersistedImageTotalBytes: 220
        )

        let id1 = UUID()
        let path1 = try XCTUnwrap(storage.saveImageFile(Data(repeating: 1, count: 100), id: id1))
        try storage.insert(ClipboardItem(
            id: id1,
            content: "OCR text preserved",
            type: .image,
            createdAt: Date(timeIntervalSince1970: 100),
            imagePath: path1,
            imageHash: "h1"
        ))

        let id2 = UUID()
        let path2 = try XCTUnwrap(storage.saveImageFile(Data(repeating: 2, count: 100), id: id2))
        try storage.insert(ClipboardItem(
            id: id2,
            content: Constants.imagePlaceholderText,
            type: .image,
            createdAt: Date(timeIntervalSince1970: 200),
            imagePath: path2,
            imageHash: "h2"
        ))

        // Insert 3rd image (150 bytes): total 150 + 100 = 250 > 220, so only newest (id3) survives bytes cap!
        let id3 = UUID()
        let path3 = try XCTUnwrap(storage.saveImageFile(Data(repeating: 3, count: 150), id: id3))
        try storage.insert(ClipboardItem(
            id: id3,
            content: Constants.imagePlaceholderText,
            type: .image,
            createdAt: Date(timeIntervalSince1970: 300),
            imagePath: path3,
            imageHash: "h3"
        ))

        let allAfterInsert = try storage.fetchAll()
        // id1 carried OCR text so it downgraded to .text; id2 had placeholder so it was deleted; id3 survived.
        XCTAssertEqual(allAfterInsert.count, 2)
        let keptImage = try XCTUnwrap(allAfterInsert.first(where: { $0.id == id3 }))
        XCTAssertEqual(keptImage.type, .image)
        let downgradedOCR = try XCTUnwrap(allAfterInsert.first(where: { $0.id == id1 }))
        XCTAssertEqual(downgradedOCR.type, .text)
        XCTAssertNil(downgradedOCR.imagePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageDir.appendingPathComponent(path1).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageDir.appendingPathComponent(path2).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageDir.appendingPathComponent(path3).path))

        // Drop an orphan file into imageDir and ensure reconcileImageStorage removes it.
        let orphanURL = imageDir.appendingPathComponent("orphan.png")
        try Data([9, 9, 9]).write(to: orphanURL)
        storage.reconcileImageStorage()
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageDir.appendingPathComponent(path3).path))
    }
}
