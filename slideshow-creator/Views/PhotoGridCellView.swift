import SwiftUI
import AppKit

struct PhotoGridCellView: View {
    let item: PhotoItem
    let shortcutFlags: [String]
    let isSelected: Bool
    let isDropTarget: Bool
    let isDropTargetOnTrailingEdge: Bool
    let dragPreviewItems: [PhotoItem]
    let dragSelectionCount: Int
    let thumbnailHeight: CGFloat
    let thumbnailMaxPixelSize: CGFloat
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onThumbnailTap: () -> Void
    let onFlagToggle: (String, Bool) -> Void
    let dragProvider: () -> NSItemProvider

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        cellContent
            .modifier(PhotoGridSelectionInteractions(onSelect: onSelect, onThumbnailTap: onThumbnailTap))
            .background(cellBackground)
            .overlay(cellBorder)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(item.isExcluded ? 0.45 : 1)
    }

    private var cellContent: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 8) {
                ThumbnailView(url: item.url, maxPixelSize: thumbnailMaxPixelSize)
                    .frame(height: thumbnailHeight)
                    .frame(maxWidth: .infinity)
                    .onDrag(dragProvider, preview: {
                        dragPreview
                    })

                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                if !shortcutFlags.isEmpty {
                    PhotoFlagControlsView(
                        shortcutFlags: shortcutFlags,
                        selectedFlags: item.flags,
                        visibleFlagLimit: 3,
                        onFlagToggle: onFlagToggle
                    )
                }
            }
            .padding(10)

            if isDropTarget {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(isDropTargetOnTrailingEdge ? .trailing : .leading, 2)
                    .frame(maxWidth: .infinity, alignment: isDropTargetOnTrailingEdge ? .trailing : .leading)
            }
        }
    }

    private var cellBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
    }

    private var cellBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: 2)
    }

    private var dragPreview: some View {
        let previewItems = {
            let candidates = Array(dragPreviewItems.prefix(3))
            return candidates.isEmpty ? [item] : candidates
        }()
        let step: CGFloat = 20
        let previewWidth = max(84, thumbnailHeight * 0.9)
        let previewHeight = max(64, thumbnailHeight * 0.7)
        let stackExtent = step * CGFloat(max(0, previewItems.count - 1))

        return ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(previewItems.enumerated()), id: \.element.id) { index, previewItem in
                    dragPreviewCard(for: previewItem)
                        .frame(width: previewWidth, height: previewHeight)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                        }
                        .offset(x: CGFloat(index) * step, y: CGFloat(index) * step)
                }
            }
            .frame(width: previewWidth + stackExtent, height: previewHeight + stackExtent, alignment: .topLeading)

            Text("\(max(1, dragSelectionCount))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(.red))
                .padding(4)
        }
        .compositingGroup()
    }

    @ViewBuilder
    private func dragPreviewCard(for previewItem: PhotoItem) -> some View {
        if let image = ThumbnailView.cachedThumbnail(
            for: previewItem.url,
            maxPixelSize: thumbnailMaxPixelSize,
            scale: displayScale
        ) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "photo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

private struct PhotoGridSelectionInteractions: ViewModifier {
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onThumbnailTap: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture(count: 1) {
                let clickCount = NSApp.currentEvent?.clickCount ?? 1
                let modifiers = (NSApp.currentEvent?.modifierFlags ?? [])
                    .intersection([.shift, .command])
                onSelect(modifiers)

                if clickCount == 2 {
                    onThumbnailTap()
                }
            }
    }
}
