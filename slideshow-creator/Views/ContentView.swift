import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var isPreviewPresented = false
    @State private var previewedPhotoID: PhotoItem.ID?
    @State private var newFlagName = ""
    private let leftPaneMinWidth: CGFloat = 480
    private let rightPaneMinWidth: CGFloat = 320

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                ProjectToolbarView(model: model)

                HStack(spacing: 8) {
                    Text(projectDisplayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)

                    if needsSaveIndicator {
                        Label("Unsaved", systemImage: "circle.fill")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.orange)
                    }

                    Spacer(minLength: 0)
                }

                EncodingSettingsView(model: model)

                FlagsPanelView(model: model, newFlagName: $newFlagName)

                PersistentHSplitView(
                    ratio: $model.photosSoundtracksSplitRatio,
                    minLeftWidth: leftPaneMinWidth,
                    minRightWidth: rightPaneMinWidth
                ) {
                    PhotosPaneView(
                        model: model,
                        isKeyboardNavigationEnabled: !isPreviewPresented,
                        onThumbnailTap: { item in
                            openPreview(for: item)
                        },
                        onRefresh: {
                            model.refreshPhotos()
                        },
                        onRelink: { id in
                            model.relinkPhoto(id: id)
                        }
                    )
                    .frame(minWidth: leftPaneMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                } right: {
                    SoundtracksPaneView(model: model)
                        .frame(minWidth: rightPaneMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)

                Text(model.status)
                    .font(.callout.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(minWidth: 900, minHeight: 600)
            .background(WindowCloseGuard(model: model))
            .disabled(isPreviewPresented)
            .allowsHitTesting(!isPreviewPresented)

            if isPreviewPresented {
                FullscreenPhotoPreview(
                    items: model.filteredPhotoItems,
                    shortcutFlags: model.shortcutFlags,
                    currentIndex: previewIndexBinding,
                    onToggleExclude: { id in
                        togglePreviewItemExclusion(id)
                    },
                    onToggleFlag: { number, id in
                        model.toggleShortcutFlag(number, for: id)
                    },
                    onSetExcluded: { isExcluded, id in
                        setPreviewItemExclusion(isExcluded, id: id)
                    },
                    onSetFlagEnabled: { flag, enabled, id in
                        model.setFlag(flag, enabled: enabled, for: id)
                    },
                    onMove: { destination, id in
                        movePreviewItem(destination, id: id)
                    },
                    onClose: {
                        if let previewedPhotoID {
                            model.selectPhoto(previewedPhotoID)
                        }
                        isPreviewPresented = false
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .onChange(of: model.isEncodingWindowPresented) { _, isPresented in
            if isPresented {
                openWindow(id: "encoding-progress")
            }
        }
    }

    private func openPreview(for item: PhotoItem) {
        guard model.filteredPhotoItems.contains(item) else { return }
        previewedPhotoID = item.id
        isPreviewPresented = true
    }

    private var previewIndexBinding: Binding<Int> {
        Binding(
            get: {
                guard let previewedPhotoID else { return 0 }
                return model.filteredPhotoItems.firstIndex(where: { $0.id == previewedPhotoID }) ?? 0
            },
            set: { newIndex in
                guard model.filteredPhotoItems.indices.contains(newIndex) else { return }
                previewedPhotoID = model.filteredPhotoItems[newIndex].id
            }
        )
    }

    private func currentPreviewIndex(in items: [PhotoItem]) -> Int {
        guard let previewedPhotoID,
              let index = items.firstIndex(where: { $0.id == previewedPhotoID }) else {
            return 0
        }
        return index
    }

    private func updatePreviewAfterFilteringChange(previousItems: [PhotoItem], previousIndex: Int) {
        let newItems = model.filteredPhotoItems

        if let previewedPhotoID, newItems.contains(where: { $0.id == previewedPhotoID }) {
            return
        }

        guard !newItems.isEmpty else {
            previewedPhotoID = nil
            isPreviewPresented = false
            return
        }

        let fallbackIndex = min(max(0, previousIndex), newItems.count - 1)
        previewedPhotoID = newItems[fallbackIndex].id
    }

    private func togglePreviewItemExclusion(_ id: PhotoItem.ID) {
        let previousItems = model.filteredPhotoItems
        let previousIndex = currentPreviewIndex(in: previousItems)
        model.toggleExclude(for: id)
        updatePreviewAfterFilteringChange(previousItems: previousItems, previousIndex: previousIndex)
    }

    private func setPreviewItemExclusion(_ isExcluded: Bool, id: PhotoItem.ID) {
        let previousItems = model.filteredPhotoItems
        let previousIndex = currentPreviewIndex(in: previousItems)
        model.setPhotoExcluded(isExcluded, for: id)
        updatePreviewAfterFilteringChange(previousItems: previousItems, previousIndex: previousIndex)
    }

    private func movePreviewItem(_ destination: PhotoContextMenuContent.MoveDestination, id: PhotoItem.ID) {
        switch destination {
        case .top:
            model.moveSelectedPhotosToTop(Set([id]))
        case .up:
            model.moveSelectedPhotosUp(Set([id]))
        case .down:
            model.moveSelectedPhotosDown(Set([id]))
        case .bottom:
            model.moveSelectedPhotosToBottom(Set([id]))
        }
    }

    private var projectDisplayText: String {
        if let projectURL = model.currentProjectURL {
            return "Project: \(projectURL.path)"
        }

        return "Project: Not saved yet"
    }

    private var needsSaveIndicator: Bool {
        model.hasUnsavedChanges || model.currentProjectURL == nil
    }
}
