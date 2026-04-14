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
        ClickGestureView(
            onClick: onSelect,
            onDoubleClick: onThumbnailTap,
            content: cellContent
        )
    }

    private var cellContent: some View {
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
    }

    private var cardBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        }
        return AnyShapeStyle(Color.primary.opacity(0.04))
    }
}

private struct ClickGestureView<Content: View>: NSViewRepresentable {
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onDoubleClick: () -> Void
    let content: Content

    func makeCoordinator() -> _Coordinator {
        _Coordinator(onClick: onClick, onDoubleClick: onDoubleClick)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hostingView.setContentHuggingPriority(.defaultLow, for: .vertical)
        container.addSubview(hostingView)

        let clickView = ClickTrackingView()
        clickView.translatesAutoresizingMaskIntoConstraints = false
        clickView.onClick = { flags in
            context.coordinator.onClick(flags)
        }
        clickView.onDoubleClick = {
            context.coordinator.onDoubleClick()
        }
        container.addSubview(clickView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            clickView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            clickView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            clickView.topAnchor.constraint(equalTo: container.topAnchor),
            clickView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onClick = onClick
        context.coordinator.onDoubleClick = onDoubleClick
        if let clickView = nsView.subviews.last as? ClickTrackingView {
            clickView.onClick = { flags in
                context.coordinator.onClick(flags)
            }
            clickView.onDoubleClick = {
                context.coordinator.onDoubleClick()
            }
        }
    }

    final class _Coordinator {
        var onClick: (NSEvent.ModifierFlags) -> Void
        var onDoubleClick: () -> Void

        init(onClick: @escaping (NSEvent.ModifierFlags) -> Void, onDoubleClick: @escaping () -> Void) {
            self.onClick = onClick
            self.onDoubleClick = onDoubleClick
        }
    }

    private final class ClickTrackingView: NSView {
        var onClick: ((NSEvent.ModifierFlags) -> Void)?
        var onDoubleClick: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick?()
            }
        }

        override func mouseUp(with event: NSEvent) {
            if event.clickCount == 1 {
                onClick?(event.modifierFlags)
            }
        }
    }
}
