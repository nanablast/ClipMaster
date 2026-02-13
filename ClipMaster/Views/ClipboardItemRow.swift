import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let onPaste: (ClipboardItem) -> Void

    var body: some View {
        Button(action: { onPaste(item) }) {
            HStack(spacing: 8) {
                // Index badge (0-9 for quick select)
                if index < 10 {
                    Text("\(index)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .frame(width: 18, height: 18)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Color.clear.frame(width: 18, height: 18)
                }

                typeIcon
                    .foregroundStyle(iconColor)
                    .frame(width: 16)
                    .font(.system(size: 12))

                VStack(alignment: .leading, spacing: 2) {
                    contentPreview
                        .lineLimit(2)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        if let appSource = item.appSource {
                            Text(appSource)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Text(item.createdAt, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.32) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var typeIcon: some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.text")
        case .image:
            Image(systemName: "photo")
        case .link:
            Image(systemName: "link")
        case .file:
            Image(systemName: "doc")
        }
    }

    private var iconColor: Color {
        switch item.type {
        case .text: .primary
        case .image: .orange
        case .link: .blue
        case .file: .green
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .image:
            HStack(spacing: 6) {
                ImageThumbnail(imagePath: item.imagePath, maxHeight: 36)
                    .frame(maxWidth: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if item.content != Constants.imagePlaceholderText {
                    Text(item.content)
                        .foregroundStyle(.secondary)
                } else {
                    Text(Constants.imagePlaceholderText)
                        .foregroundStyle(.tertiary)
                }
            }
        case .text, .link, .file:
            Text(item.content)
        }
    }
}
