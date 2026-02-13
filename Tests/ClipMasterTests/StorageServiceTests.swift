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
}
