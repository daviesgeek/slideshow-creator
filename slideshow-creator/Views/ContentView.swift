import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var isPreviewPresented = false
    @State private var previewIndex = 0
    @State private var newFlagName = ""
    private let leftPaneMinWidth: CGFloat = 480
    private let rightPaneMinWidth: CGFloat = 320

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                ProjectToolbarView(model: model)

                if let projectURL = model.currentProjectURL {
                    Text("Project: \(projectURL.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                EncodingSettingsView(model: model)

                FlagsPanelView(model: model, newFlagName: $newFlagName)

                PersistentHSplitView(
                    ratio: $model.photosSoundtracksSplitRatio,
                    minLeftWidth: leftPaneMinWidth,
                    minRightWidth: rightPaneMinWidth
                ) {
                    PhotosPaneView(model: model) { item in
                        openPreview(for: item)
                    }
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

            if isPreviewPresented {
                FullscreenPhotoPreview(
                    items: model.items,
                    shortcutFlags: model.shortcutFlags,
                    currentIndex: $previewIndex,
                    onToggleExclude: { id in
                        model.toggleExclude(for: id)
                    },
                    onToggleFlag: { number, id in
                        model.toggleShortcutFlag(number, for: id)
                    },
                    onClose: { isPreviewPresented = false }
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
        guard let index = model.items.firstIndex(of: item) else { return }
        previewIndex = index
        isPreviewPresented = true
    }
}
