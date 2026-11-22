import SwiftUI

/// Compact quick-paste menu shown in the floating panel.
/// Keyboard-first: arrow keys to navigate, Enter to paste, number keys for quick select.
struct QuickPasteView: View {
    let items: [ClipboardItem]
    let selectedIndex: Int
    let searchText: String
    let listVersion: Int
    let keyboardInputAvailable: Bool
    let protectedInputRestricted: Bool
    let onItemSelect: (Int) -> Void

    private let rowHeight: CGFloat = 44
    private let maxPanelHeight: CGFloat = 420
    private let maxVisibleItems = 20

    private var selectedItem: ClipboardItem? {
        selectedIndex < items.count ? items[selectedIndex] : nil
    }

    private var displayedItemCount: Int {
        min(items.count, maxVisibleItems)
    }

    private var chromeHeight: CGFloat {
        50 + (searchText.isEmpty ? 0 : 30)
    }

    private var panelHeight: CGFloat {
        min(CGFloat(displayedItemCount) * rowHeight + chromeHeight, maxPanelHeight)
    }

    private var needsScroll: Bool {
        CGFloat(displayedItemCount) * rowHeight + chromeHeight > maxPanelHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "clipboard")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("ClipMaster")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if selectedItem?.type == .image, selectedItem?.content != Constants.imagePlaceholderText {
                    Text("⏎图片 ⇧⏎OCR文字")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("⏎粘贴 ⇧⏎纯文本")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if protectedInputRestricted {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 10))
                    Text("密码隐藏模式受限：点击条目复制，切换可见后粘贴")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            } else if !keyboardInputAvailable {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 10))
                    Text("当前输入框启用安全输入，请点击条目粘贴")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            if !searchText.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    Text(searchText)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("ESC 清除")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.3))
            }

            Divider()

            if items.isEmpty {
                Text(searchText.isEmpty ? "暂无记录" : "未找到匹配项")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(items.prefix(maxVisibleItems).enumerated()), id: \.element.id) { index, item in
                                QuickPasteRow(
                                    item: item,
                                    index: index,
                                    isSelected: selectedIndex == index
                                )
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onItemSelect(index)
                                }
                                .contextMenu {
                                    if item.type == .image {
                                        Button("保存图片") { ImageFileSaver.saveImageToDownloads(item) }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .onAppear {
                        if needsScroll {
                            scrollToSelection(proxy, animated: false)
                        }
                    }
                    .onChange(of: selectedIndex) { newIndex in
                        if needsScroll {
                            scrollToSelection(proxy, animated: true)
                        }
                    }
                }
                .id(listVersion)
            }
        }
        .frame(width: 320, height: panelHeight)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy, animated: Bool) {
        guard selectedIndex >= 0, selectedIndex < items.count else { return }
        let targetID = items[selectedIndex].id
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.08)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            } else {
                proxy.scrollTo(targetID, anchor: .center)
            }
        }
    }
}

// MARK: - Row

struct QuickPasteRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Index number
            if index < 10 {
                Text("\(index)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 16, height: 16)
                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Color.clear.frame(width: 16, height: 16)
            }

            // Type icon
            typeIcon
                .font(.system(size: 10))
                .foregroundStyle(iconColor)
                .frame(width: 14)

            // Content
            contentPreview
                .lineLimit(1)
                .font(.system(size: 12))
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            // App source
            if let app = item.appSource {
                Text(app)
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.32) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private var typeIcon: some View {
        switch item.type {
        case .text:  Image(systemName: "doc.text")
        case .image: Image(systemName: "photo")
        case .link:  Image(systemName: "link")
        case .file:  Image(systemName: MediaFilePresentation(content: item.content).iconSystemName)
        }
    }

    private var iconColor: Color {
        switch item.type {
        case .text:  .primary
        case .image: .orange
        case .link:  .blue
        case .file:  .green
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .image:
            HStack(spacing: 4) {
                ImageThumbnail(imagePath: item.imagePath, maxHeight: 20)
                if item.content != Constants.imagePlaceholderText {
                    Text(item.content.replacingOccurrences(of: "\n", with: " "))
                        .foregroundStyle(.secondary)
                } else {
                    Text(Constants.imagePlaceholderText)
                        .foregroundStyle(.tertiary)
                }
            }
        case .file:
            let presentation = MediaFilePresentation(content: item.content)
            HStack(spacing: 4) {
                if let fileURL = presentation.singleImageURL {
                    ImageThumbnail(fileURL: fileURL, maxHeight: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(presentation.displayText)
            }
        case .text, .link:
            Text(item.content.replacingOccurrences(of: "\n", with: " "))
        }
    }
}

/// Loads downsampled image thumbnails lazily from persisted image files or local file URLs
struct ImageThumbnail: View {
    let imagePath: String?
    let fileURL: URL?
    let maxHeight: CGFloat
    @State private var nsImage: NSImage?
    private let cache = ImageThumbnailCache.shared

    init(imagePath: String? = nil, fileURL: URL? = nil, maxHeight: CGFloat) {
        self.imagePath = imagePath
        self.fileURL = fileURL
        self.maxHeight = maxHeight
    }

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: maxHeight)
            }
        }
        .onAppear {
            guard nsImage == nil else { return }
            let cacheKey: String
            if let imagePath {
                cacheKey = ImageThumbnailLoader.cacheKey(imagePath: imagePath)
            } else if let fileURL {
                cacheKey = ImageThumbnailLoader.cacheKey(fileURL: fileURL)
            } else {
                return
            }

            if let cached = cache.image(forKey: cacheKey) {
                nsImage = cached
                return
            }

            let targetPath = imagePath
            let targetFileURL = fileURL
            DispatchQueue.global(qos: .userInitiated).async {
                let thumbnail: NSImage?
                if let targetPath {
                    if let url = StorageService.shared.imageFileURL(for: targetPath) {
                        thumbnail = ImageThumbnailLoader.loadThumbnail(fromFileURL: url)
                    } else if let data = StorageService.shared.loadImageData(filename: targetPath) {
                        thumbnail = ImageThumbnailLoader.loadThumbnail(from: data)
                    } else {
                        thumbnail = nil
                    }
                } else if let targetFileURL,
                          FileManager.default.fileExists(atPath: targetFileURL.path) {
                    thumbnail = ImageThumbnailLoader.loadThumbnail(fromFileURL: targetFileURL)
                } else {
                    thumbnail = nil
                }

                guard let thumbnail else { return }
                DispatchQueue.main.async {
                    cache.setImage(thumbnail, forKey: cacheKey)
                    nsImage = thumbnail
                }
            }
        }
    }
}
