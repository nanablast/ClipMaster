import AppKit
import SwiftUI
import Carbon.HIToolbox

struct ClipboardHistoryView: View {
    @ObservedObject var clipboardMonitor: ClipboardMonitor
    @ObservedObject private var pasteQueue = PasteQueue.shared
    @State private var searchText = ""
    @State private var items: [ClipboardItem] = []
    @State private var totalItemsCount = 0
    @State private var canLoadMore = false
    @State private var isLoadingMore = false
    @State private var activeQuery = ""
    @State private var listVersion = 0
    @State private var selectedIndex: Int = 0
    @State private var eventMonitor: Any?
    @State private var showClearAllConfirmation = false
    @State private var searchDebounceWorkItem: DispatchWorkItem?
    @State private var loadMoreWorkItem: DispatchWorkItem?
    @State private var reloadRequestID = UUID()
    @State private var loadMoreRequestID = UUID()

    let onDismiss: () -> Void

    private let storageService = StorageService.shared
    private let pageSize = 100
    private let searchDebounceDelay: TimeInterval = 0.15
    private var searchBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { newValue in
                guard newValue != searchText else { return }
                searchText = newValue
                scheduleReload(queryOverride: newValue, debounced: true)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("剪贴板历史")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("⏎ 粘贴  ⇧⏎ 纯文本")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search
            SearchBar(text: searchBinding)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            Divider()

            // Items list
            if items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clipboard")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("暂无剪贴板记录")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                ClipboardItemRow(
                                    item: item,
                                    index: index,
                                    isSelected: selectedIndex == index,
                                    onPaste: { pasteItem($0) }
                                )
                                .id(item.id)
                                .onAppear {
                                    loadMoreIfNeeded(triggerIndex: index)
                                }
                                .contextMenu {
                                    Button("粘贴") { pasteItem(item) }
                                    Button("粘贴为纯文本") { pasteItemPlainText(item) }
                                    if item.type == .image {
                                        Button("保存图片") { saveImageToDownloads(item) }
                                    }
                                    Divider()
                                    Button("删除") { deleteItem(item) }
                                }
                            }
                            if isLoadingMore {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .controlSize(.small)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .id(listVersion)
                    .onChange(of: selectedIndex) { newIndex in
                        guard newIndex >= 0, newIndex < items.count else { return }
                        let targetID = items[newIndex].id
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(targetID, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Text("已加载 \(items.count)/\(totalItemsCount) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                if pasteQueue.isActive {
                    Text("队列: \(pasteQueue.remaining) 项")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
                Button("清空全部") {
                    showClearAllConfirmation = true
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .frame(width: 360, height: 480)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .onAppear {
            scheduleReload(queryOverride: searchText)
            startKeyboardMonitor()
        }
        .onDisappear {
            stopKeyboardMonitor()
            searchDebounceWorkItem?.cancel()
            searchDebounceWorkItem = nil
            loadMoreWorkItem?.cancel()
            loadMoreWorkItem = nil
        }
        .onChange(of: clipboardMonitor.latestItem) { _ in scheduleReload(queryOverride: searchText) }
        .alert("确认清空所有历史记录？", isPresented: $showClearAllConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                clearAll()
            }
        } message: {
            Text("此操作不可撤销。")
        }
        .onExitCommand { onDismiss() }
    }

    // MARK: - Keyboard Monitor

    private func startKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            return handleKeyDown(event) ? nil : event
        }
    }

    private func stopKeyboardMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = Int(event.keyCode)
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Enter: paste selected item
        if keyCode == kVK_Return {
            guard !items.isEmpty, selectedIndex < items.count else { return false }
            let item = items[selectedIndex]
            if modifiers.contains(.shift) {
                pasteItemPlainText(item)
            } else {
                pasteItem(item)
            }
            return true
        }

        // Arrow Up
        if keyCode == kVK_UpArrow {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return true
        }

        // Arrow Down
        if keyCode == kVK_DownArrow {
            if selectedIndex < items.count - 1 {
                selectedIndex += 1
            }
            return true
        }

        // Number keys 0-9 for quick select & paste
        if modifiers.isEmpty || modifiers == .capsLock {
            let numberKeyMap: [Int: Int] = [
                kVK_ANSI_0: 0, kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3,
                kVK_ANSI_4: 4, kVK_ANSI_5: 5, kVK_ANSI_6: 6, kVK_ANSI_7: 7,
                kVK_ANSI_8: 8, kVK_ANSI_9: 9,
            ]

            if let index = numberKeyMap[keyCode], index < items.count {
                // If search field is focused and has text, let it handle digit input
                if !searchText.isEmpty {
                    return false
                }
                pasteItem(items[index])
                return true
            }
        }

        // Escape
        if keyCode == kVK_Escape {
            onDismiss()
            return true
        }

        // Delete: remove selected item
        if keyCode == kVK_Delete && modifiers.contains(.command) {
            guard !items.isEmpty, selectedIndex < items.count else { return false }
            deleteItem(items[selectedIndex], preserveSelection: true)
            return true
        }

        return false
    }

    // MARK: - Data

    private func scheduleReload(
        preserveSelection: Bool = false,
        preferredIndex: Int? = nil,
        queryOverride: String? = nil,
        debounced: Bool = false
    ) {
        let baseIndex = preferredIndex ?? selectedIndex
        let query = (queryOverride ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        reloadRequestID = requestID

        let executeReload = {
            reloadItemsAsync(
                query: query,
                requestID: requestID,
                preserveSelection: preserveSelection,
                preferredIndex: baseIndex
            )
        }

        if debounced {
            searchDebounceWorkItem?.cancel()
            let workItem = DispatchWorkItem(block: executeReload)
            searchDebounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + searchDebounceDelay, execute: workItem)
        } else {
            searchDebounceWorkItem?.cancel()
            searchDebounceWorkItem = nil
            executeReload()
        }
    }

    private func reloadItemsAsync(
        query: String,
        requestID: UUID,
        preserveSelection: Bool,
        preferredIndex: Int
    ) {
        isLoadingMore = false

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let total: Int
                let firstPage: [ClipboardItem]
                if query.isEmpty {
                    total = try storageService.totalCount()
                    firstPage = try storageService.fetchAll(limit: pageSize, offset: 0)
                } else {
                    total = try storageService.searchCount(keyword: query)
                    firstPage = try storageService.search(keyword: query, limit: pageSize, offset: 0)
                }

                DispatchQueue.main.async {
                    guard reloadRequestID == requestID else { return }
                    loadMoreWorkItem?.cancel()
                    loadMoreWorkItem = nil
                    loadMoreRequestID = UUID()

                    activeQuery = query
                    listVersion += 1
                    totalItemsCount = total
                    items = firstPage
                    canLoadMore = items.count < totalItemsCount

                    guard !items.isEmpty else {
                        selectedIndex = 0
                        return
                    }

                    if preserveSelection {
                        selectedIndex = min(max(preferredIndex, 0), items.count - 1)
                    } else {
                        selectedIndex = 0
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard reloadRequestID == requestID else { return }
                    isLoadingMore = false
                    AppLogger.ui.error("Failed to load clipboard items: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func loadMoreIfNeeded(triggerIndex: Int) {
        guard canLoadMore, !isLoadingMore else { return }
        guard triggerIndex >= items.count - 5 else { return }

        loadMoreWorkItem?.cancel()
        isLoadingMore = true
        let query = activeQuery
        let offset = items.count
        let reloadID = reloadRequestID
        let requestID = UUID()
        loadMoreRequestID = requestID

        let workItem = DispatchWorkItem {
            do {
                let nextPage: [ClipboardItem]
                if query.isEmpty {
                    nextPage = try storageService.fetchAll(limit: pageSize, offset: offset)
                } else {
                    nextPage = try storageService.search(keyword: query, limit: pageSize, offset: offset)
                }

                DispatchQueue.main.async {
                    guard reloadRequestID == reloadID else { return }
                    guard loadMoreRequestID == requestID else { return }
                    guard activeQuery == query else { return }
                    guard offset <= items.count else {
                        isLoadingMore = false
                        return
                    }

                    let existingIDs = Set(items.map(\.id))
                    let uniquePage = nextPage.filter { !existingIDs.contains($0.id) }
                    items.append(contentsOf: uniquePage)
                    canLoadMore = items.count < totalItemsCount
                    isLoadingMore = false
                }
            } catch {
                DispatchQueue.main.async {
                    guard reloadRequestID == reloadID else { return }
                    guard loadMoreRequestID == requestID else { return }
                    isLoadingMore = false
                    AppLogger.ui.error("Failed to load more clipboard items: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        loadMoreWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    // MARK: - Actions

    private func pasteItem(_ item: ClipboardItem) {
        onDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            PasteService.paste(item)
        }
    }

    private func pasteItemPlainText(_ item: ClipboardItem) {
        onDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            PasteService.pastePlainText(item)
        }
    }

    private func deleteItem(_ item: ClipboardItem, preserveSelection: Bool = false) {
        let oldIndex = selectedIndex
        do {
            try storageService.delete(item)
            scheduleReload(preserveSelection: preserveSelection, preferredIndex: oldIndex)
        } catch {
            AppLogger.ui.error("History item delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveImageToDownloads(_ item: ClipboardItem) {
        guard item.type == .image,
              let data = try? StorageService.shared.fetchImageData(for: item.id) else {
            ToastService.shared.show(
                message: "图片数据不存在",
                systemImage: "xmark.circle.fill",
                tintColor: .systemRed
            )
            return
        }

        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "ClipMaster-\(timestamp).png"
        let fileURL = downloadsURL.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            ToastService.shared.show(
                message: "已保存到 Downloads/\(filename)",
                systemImage: "checkmark.circle.fill",
                tintColor: .systemGreen
            )
        } catch {
            AppLogger.ui.error("Save image failed: \(error.localizedDescription, privacy: .public)")
            ToastService.shared.show(
                message: "保存失败",
                systemImage: "xmark.circle.fill",
                tintColor: .systemRed
            )
        }
    }

    private func clearAll() {
        do {
            try storageService.deleteAll()
            scheduleReload()
            ToastService.shared.show(
                message: "已清空所有历史记录",
                systemImage: "checkmark.circle.fill",
                tintColor: .systemGreen
            )
        } catch {
            AppLogger.ui.error("Clear all history failed: \(error.localizedDescription, privacy: .public)")
            ToastService.shared.show(
                message: "清空失败",
                systemImage: "xmark.circle.fill",
                tintColor: .systemRed
            )
        }
    }
}
