import SwiftUI
import AppKit

struct PhotoGridCellView: View {
    let item: PhotoItem
    let shortcutFlags: [String]
    let isSelected: Bool
    let isDropTarget: Bool
    let thumbnailHeight: CGFloat
    let thumbnailMaxPixelSize: CGFloat
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onThumbnailTap: () -> Void
    let onExcludeToggle: (Bool) -> Void
    let onFlagToggle: (String, Bool) -> Void
    let dragProvider: () -> NSItemProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThumbnailView(url: item.url, maxPixelSize: thumbnailMaxPixelSize)
                .frame(height: thumbnailHeight)
                .frame(maxWidth: .infinity)
                .onDrag(dragProvider)
                .help("Drag to reorder")

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
        .background(cardBackground)
        .overlay(alignment: .leading) {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 2)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(item.isExcluded ? 0.45 : 1)
        .contentShape(Rectangle())
        .background(ClickGestureView(onClick: onSelect, onDoubleClick: onThumbnailTap))
    }

    private var cardBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        }
        return AnyShapeStyle(Color.primary.opacity(0.04))
    }
}

private struct ClickGestureView: NSViewRepresentable {
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> ClickTrackingView {
        let view = ClickTrackingView()
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: ClickTrackingView, context: Context) {
        nsView.onClick = onClick
        nsView.onDoubleClick = onDoubleClick
    }

    final class ClickTrackingView: NSView {
        var onClick: ((NSEvent.ModifierFlags) -> Void)?
        var onDoubleClick: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            // Let double-click be handled natively
            if event.clickCount == 2 {
                onDoubleClick?()
            } else {
                // Store event for use after potential drag recognition
                // We call onClick on mouseUp to ensure drag doesn't fire first
            }
        }

        override func mouseUp(with event: NSEvent) {
            if event.clickCount == 1 {
                onClick?(event.modifierFlags)
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            // Still allow context menu via standard behavior if needed
            mouseDown(with: event)
        }
    }
}
