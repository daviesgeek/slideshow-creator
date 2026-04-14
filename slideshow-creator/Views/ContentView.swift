import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isPreviewPresented = false
    @State private var previewIndex = 0
    @State private var newFlagName = ""

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

                HStack(alignment: .top, spacing: 12) {
                    PhotosPaneView(model: model) { item in
                        openPreview(for: item)
                    }

                    SoundtracksPaneView(model: model)
                }

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
                    currentIndex: $previewIndex,
                    onClose: { isPreviewPresented = false }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    private func openPreview(for item: PhotoItem) {
        guard let index = model.items.firstIndex(of: item) else { return }
        previewIndex = index
        isPreviewPresented = true
    }
}
