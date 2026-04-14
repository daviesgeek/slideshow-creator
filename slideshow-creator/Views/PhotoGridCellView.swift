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
        PhotoGridCellNSView(
            item: item,
            shortcutFlags: shortcutFlags,
            isSelected: isSelected,
            isDropTarget: isDropTarget,
            thumbnailHeight: thumbnailHeight,
            thumbnailMaxPixelSize: thumbnailMaxPixelSize,
            onSelect: onSelect,
            onThumbnailTap: onThumbnailTap,
            onExcludeToggle: onExcludeToggle,
            onFlagToggle: onFlagToggle,
            dragProvider: dragProvider
        )
    }
}

private struct PhotoGridCellNSView: NSViewRepresentable {
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

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelect: onSelect,
            onThumbnailTap: onThumbnailTap,
            onExcludeToggle: onExcludeToggle,
            onFlagToggle: onFlagToggle,
            dragProvider: dragProvider
        )
    }

    func makeNSView(context: Context) -> PhotoGridCellNSViewClass {
        let nsView = PhotoGridCellNSViewClass()
        updateCoordinatorAndNSView(nsView: nsView, context: context)
        return nsView
    }

    func updateNSView(_ nsView: PhotoGridCellNSViewClass, context: Context) {
        updateCoordinatorAndNSView(nsView: nsView, context: context)
    }

    private func updateCoordinatorAndNSView(nsView: PhotoGridCellNSViewClass, context: Context) {
        let c = context.coordinator
        c.item = item
        c.shortcutFlags = shortcutFlags
        c.isSelected = isSelected
        c.isDropTarget = isDropTarget
        c.thumbnailHeight = thumbnailHeight
        c.thumbnailMaxPixelSize = thumbnailMaxPixelSize
        c.onSelect = onSelect
        c.onThumbnailTap = onThumbnailTap
        c.onExcludeToggle = onExcludeToggle
        c.onFlagToggle = onFlagToggle
        c.dragProvider = dragProvider

        nsView.updateContent(
            item: item,
            shortcutFlags: shortcutFlags,
            isSelected: isSelected,
            isDropTarget: isDropTarget,
            thumbnailHeight: thumbnailHeight,
            thumbnailMaxPixelSize: thumbnailMaxPixelSize,
            onExcludeToggle: onExcludeToggle,
            onFlagToggle: onFlagToggle,
            dragProvider: dragProvider
        )
    }

    final class Coordinator {
        var onSelect: (NSEvent.ModifierFlags) -> Void = { _ in }
        var onThumbnailTap: () -> Void = {}
        var onExcludeToggle: (Bool) -> Void = { _ in }
        var onFlagToggle: (String, Bool) -> Void = { _, _ in }
        var dragProvider: () -> NSItemProvider = { NSItemProvider() }
        var item: PhotoItem = PhotoItem(url: URL(fileURLWithPath: "/"))
        var shortcutFlags: [String] = []
        var isSelected: Bool = false
        var isDropTarget: Bool = false
        var thumbnailHeight: CGFloat = 120
        var thumbnailMaxPixelSize: CGFloat = 120

        init(
            onSelect: @escaping (NSEvent.ModifierFlags) -> Void,
            onThumbnailTap: @escaping () -> Void,
            onExcludeToggle: @escaping (Bool) -> Void,
            onFlagToggle: @escaping (String, Bool) -> Void,
            dragProvider: @escaping () -> NSItemProvider
        ) {
            _ = onSelect
            _ = onThumbnailTap
            _ = onExcludeToggle
            _ = onFlagToggle
            _ = dragProvider
        }
    }

    final class PhotoGridCellNSViewClass: NSView {
        private var hostingView: NSHostingView<AnyView>?
        private var clickView: ClickTrackingView?
        private var coordinator: Coordinator?
        private var isSetup = false

        func configureWithCoordinator(_ coordinator: Coordinator) {
            self.coordinator = coordinator
            setupIfNeeded()
        }

        private func setupIfNeeded() {
            guard !isSetup else { return }
            isSetup = true

            wantsLayer = true
            layer?.cornerRadius = 10
            layer?.masksToBounds = true

            // Placeholder content initially
            updateHostingView(
                content: buildCellContent(
                    item: PhotoItem(url: URL(fileURLWithPath: "/"), isExcluded: false, flags: []),
                    shortcutFlags: [],
                    isSelected: false,
                    isDropTarget: false,
                    thumbnailHeight: 120,
                    thumbnailMaxPixelSize: 120,
                    onExcludeToggle: { _ in },
                    onFlagToggle: { _, _ in },
                    dragProvider: { NSItemProvider() }
                )
            )
        }

        func updateContent(
            item: PhotoItem,
            shortcutFlags: [String],
            isSelected: Bool,
            isDropTarget: Bool,
            thumbnailHeight: CGFloat,
            thumbnailMaxPixelSize: CGFloat,
            onExcludeToggle: @escaping (Bool) -> Void,
            onFlagToggle: @escaping (String, Bool) -> Void,
            dragProvider: @escaping () -> NSItemProvider
        ) {
            setupIfNeeded()

            let content = buildCellContent(
                item: item,
                shortcutFlags: shortcutFlags,
                isSelected: isSelected,
                isDropTarget: isDropTarget,
                thumbnailHeight: thumbnailHeight,
                thumbnailMaxPixelSize: thumbnailMaxPixelSize,
                onExcludeToggle: onExcludeToggle,
                onFlagToggle: onFlagToggle,
                dragProvider: dragProvider
            )

            updateHostingView(content: content)

            layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
                : NSColor.windowBackgroundColor.withAlphaComponent(0.04).cgColor
            layer?.opacity = Float(item.isExcluded ? 0.45 : 1.0)
        }

        private func updateHostingView(content: AnyView) {
            let newHosting = NSHostingView(rootView: content)
            newHosting.translatesAutoresizingMaskIntoConstraints = false
            newHosting.setContentHuggingPriority(.defaultLow, for: .horizontal)
            newHosting.setContentHuggingPriority(.defaultLow, for: .vertical)
            newHosting.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            newHosting.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

            let newClickView = ClickTrackingView()
            newClickView.translatesAutoresizingMaskIntoConstraints = false
            newClickView.onClick = { [weak self] flags in
                self?.coordinator?.onSelect(flags)
            }
            newClickView.onDoubleClick = { [weak self] in
                self?.coordinator?.onThumbnailTap()
            }

            // Remove old views
            hostingView?.removeFromSuperview()
            clickView?.removeFromSuperview()

            addSubview(newHosting)
            addSubview(newClickView)

            NSLayoutConstraint.activate([
                newHosting.leadingAnchor.constraint(equalTo: leadingAnchor),
                newHosting.trailingAnchor.constraint(equalTo: trailingAnchor),
                newHosting.topAnchor.constraint(equalTo: topAnchor),
                newHosting.bottomAnchor.constraint(equalTo: bottomAnchor),
                newClickView.leadingAnchor.constraint(equalTo: leadingAnchor),
                newClickView.trailingAnchor.constraint(equalTo: trailingAnchor),
                newClickView.topAnchor.constraint(equalTo: topAnchor),
                newClickView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

            hostingView = newHosting
            clickView = newClickView
        }

        private func buildCellContent(
            item: PhotoItem,
            shortcutFlags: [String],
            isSelected: Bool,
            isDropTarget: Bool,
            thumbnailHeight: CGFloat,
            thumbnailMaxPixelSize: CGFloat,
            onExcludeToggle: @escaping (Bool) -> Void,
            onFlagToggle: @escaping (String, Bool) -> Void,
            dragProvider: @escaping () -> NSItemProvider
        ) -> AnyView {
            AnyView(
                ZStack(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 8) {
                        ThumbnailView(url: item.url, maxPixelSize: thumbnailMaxPixelSize)
                            .frame(height: thumbnailHeight)
                            .frame(maxWidth: .infinity)
                            .onDrag(dragProvider)

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
                            .padding(.leading, 2)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .opacity(item.isExcluded ? 0.45 : 1)
            )
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
