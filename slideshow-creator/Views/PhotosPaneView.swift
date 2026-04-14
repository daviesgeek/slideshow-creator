import SwiftUI
import UniformTypeIdentifiers

struct PhotosPaneView: View {
    @ObservedObject var model: AppModel
    let onThumbnailTap: (PhotoItem) -> Void

    @State private var draggedPhotoID: PhotoItem.ID?
    @State private var gridDropTargetID: PhotoItem.ID?
    @State private var isGridDroppingAtEnd = false
    @State private var gridAvailableWidth: CGFloat = 0
    @State private var gridCellWidth: CGFloat = 170

    private var selectedPhotoIDs: Set<PhotoItem.ID> { model.selectedPhotoIDs }
    private var selectedPhotoCount: Int { selectedPhotoIDs.count }
    private var hasSelection: Bool { selectedPhotoCount > 0 }
    private let gridMinCellWidth: CGFloat = 120
    private let gridMaxCellWidth: CGFloat = 280
    private let gridSpacing: CGFloat = 10
    private let gridThumbnailHeightScale: CGFloat = 0.72

    private var gridColumnCount: Int {
        let columns = Int((gridAvailableWidth + gridSpacing) / (gridCellWidth + gridSpacing))
        return max(1, columns)
    }

    private var gridThumbnailHeight: CGFloat {
        max(90, gridCellWidth * gridThumbnailHeightScale)
    }

    private func keyEquivalent(for number: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(number)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let folderURL = model.folderURL {
                Text(folderURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            if model.photosViewMode == .list {
                listView
            } else {
                gridView
            }

            selectionActions
            keyboardShortcuts
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Photos")
                .font(.headline)

            Picker("View", selection: $model.photosViewMode) {
                ForEach(AppModel.PhotosViewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)

            if model.photosViewMode == .grid {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.grid.2x2")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Slider(value: $gridCellWidth, in: gridMinCellWidth ... gridMaxCellWidth)
                        .frame(width: 150)
                        .help("Grid tile size")

                    Image(systemName: "rectangle.grid.1x2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("Drag photos to reorder")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var listView: some View {
        List(selection: Binding(get: {
            model.selectedPhotoIDs
        }, set: { newValue in
            model.selectPhotos(newValue)
        })) {
            ForEach(model.items) { item in
                PhotoRow(
                    item: item,
                    shortcutFlags: model.shortcutFlags,
                    isSelected: model.selectedPhotoIDs.contains(item.id),
                    dragProvider: {
                        draggedPhotoID = item.id
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    },
                    onThumbnailTap: {
                        model.selectPhoto(item.id)
                        onThumbnailTap(item)
                    },
                    onExcludeToggle: { isExcluded in
                        model.setPhotoExcluded(isExcluded, for: item.id)
                    },
                    onFlagToggle: { flag, isEnabled in
                        model.setFlag(flag, enabled: isEnabled, for: item.id)
                    }
                )
                .tag(item.id)
            }
            .onInsert(of: [UTType.text.identifier], perform: handleListInsert)
        }
        .frame(minHeight: 260)
    }

    private var gridView: some View {
        ScrollView {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { gridAvailableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        gridAvailableWidth = newWidth
                    }
            }
            .frame(height: 0)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: gridCellWidth), spacing: gridSpacing)], spacing: gridSpacing) {
                ForEach(model.items) { item in
                    PhotoGridCellView(
                        item: item,
                        shortcutFlags: model.shortcutFlags,
                        isSelected: model.selectedPhotoIDs.contains(item.id),
                        isDropTarget: gridDropTargetID == item.id,
                        thumbnailHeight: gridThumbnailHeight,
                        onSelect: { model.selectPhoto(item.id) },
                        onThumbnailTap: {
                            model.selectPhoto(item.id)
                            onThumbnailTap(item)
                        },
                        onExcludeToggle: { isExcluded in
                            model.setPhotoExcluded(isExcluded, for: item.id)
                        },
                        onFlagToggle: { flag, isEnabled in
                            model.setFlag(flag, enabled: isEnabled, for: item.id)
                        },
                        dragProvider: {
                            draggedPhotoID = item.id
                            return NSItemProvider(object: item.id.uuidString as NSString)
                        }
                    )
                    .onDrop(
                        of: [UTType.text],
                        delegate: GridPhotoDropDelegate(
                            targetItemID: item.id,
                            model: model,
                            draggedItemID: $draggedPhotoID,
                            dropTargetID: $gridDropTargetID,
                            isDroppingAtEnd: $isGridDroppingAtEnd
                        )
                    )
                }

                Color.clear
                    .frame(height: 20)
                    .overlay(alignment: .leading) {
                        if isGridDroppingAtEnd {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor)
                                .frame(width: 3)
                                .padding(.vertical, 2)
                                .padding(.leading, 2)
                        }
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: GridPhotoDropToEndDelegate(
                            model: model,
                            draggedItemID: $draggedPhotoID,
                            dropTargetID: $gridDropTargetID,
                            isDroppingAtEnd: $isGridDroppingAtEnd
                        )
                    )
            }
            .padding(.vertical, 4)
        }
        .frame(minHeight: 260)
    }

    private var selectionActions: some View {
        HStack(spacing: 8) {
            Text(hasSelection ? "\(selectedPhotoCount) selected" : "No selection")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Group {
                Button("Top") {
                    model.moveSelectedPhotosToTop(selectedPhotoIDs)
                }
                Button("Up") {
                    model.moveSelectedPhotosUp(selectedPhotoIDs)
                }
                Button("Down") {
                    model.moveSelectedPhotosDown(selectedPhotoIDs)
                }
                Button("Bottom") {
                    model.moveSelectedPhotosToBottom(selectedPhotoIDs)
                }
            }
            .disabled(!hasSelection)

            Divider()
                .frame(height: 14)

            Button("Include") {
                model.setPhotosExcluded(false, for: selectedPhotoIDs)
            }
            .disabled(!hasSelection)

            Button("Exclude") {
                model.setPhotosExcluded(true, for: selectedPhotoIDs)
            }
            .disabled(!hasSelection)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var keyboardShortcuts: some View {
        HStack(spacing: 0) {
            Button("Toggle Exclude") {
                model.toggleExcludeForSelectedPhoto()
            }
            .keyboardShortcut("x", modifiers: [])
            .opacity(0.001)
            .frame(width: 0, height: 0)

            ForEach(1...9, id: \.self) { number in
                Button("Toggle Flag \(number)") {
                    model.toggleShortcutFlagForSelectedPhoto(number)
                }
                .keyboardShortcut(keyEquivalent(for: number), modifiers: [])
                .opacity(0.001)
                .frame(width: 0, height: 0)
            }

            if model.photosViewMode == .grid {
                Button("Grid Left") {
                    moveGridSelection(horizontalDelta: -1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(0.001)
                .frame(width: 0, height: 0)

                Button("Grid Right") {
                    moveGridSelection(horizontalDelta: 1)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .opacity(0.001)
                .frame(width: 0, height: 0)

                Button("Grid Up") {
                    moveGridSelection(verticalDelta: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: [])
                .opacity(0.001)
                .frame(width: 0, height: 0)

                Button("Grid Down") {
                    moveGridSelection(verticalDelta: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                .opacity(0.001)
                .frame(width: 0, height: 0)
            }
        }
        .allowsHitTesting(false)
    }

    private func handleListInsert(at index: Int, itemProviders _: [NSItemProvider]) {
        guard let draggedPhotoID else { return }

        if index >= model.items.count {
            model.movePhotoToEnd(withID: draggedPhotoID)
        } else {
            model.movePhoto(withID: draggedPhotoID, before: model.items[index].id)
        }

        self.draggedPhotoID = nil
    }

    private func moveGridSelection(horizontalDelta: Int = 0, verticalDelta: Int = 0) {
        guard model.photosViewMode == .grid else { return }
        guard !model.items.isEmpty else { return }

        let currentIndex = model.selectedPhotoID.flatMap { selectedID in
            model.items.firstIndex(where: { $0.id == selectedID })
        } ?? 0

        let movement = horizontalDelta + (verticalDelta * gridColumnCount)
        let targetIndex = min(max(0, currentIndex + movement), model.items.count - 1)
        model.selectPhoto(model.items[targetIndex].id)
    }
}

private struct GridPhotoDropDelegate: DropDelegate {
    let targetItemID: PhotoItem.ID
    let model: AppModel
    @Binding var draggedItemID: PhotoItem.ID?
    @Binding var dropTargetID: PhotoItem.ID?
    @Binding var isDroppingAtEnd: Bool

    func dropEntered(info _: DropInfo) {
        guard let draggedItemID else { return }
        guard draggedItemID != targetItemID else { return }
        isDroppingAtEnd = false
        dropTargetID = targetItemID
        model.movePhoto(withID: draggedItemID, before: targetItemID)
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggedItemID = nil
        dropTargetID = nil
        isDroppingAtEnd = false
        return true
    }
}

private struct GridPhotoDropToEndDelegate: DropDelegate {
    let model: AppModel
    @Binding var draggedItemID: PhotoItem.ID?
    @Binding var dropTargetID: PhotoItem.ID?
    @Binding var isDroppingAtEnd: Bool

    func dropEntered(info _: DropInfo) {
        guard let draggedItemID else { return }
        dropTargetID = nil
        isDroppingAtEnd = true
        model.movePhotoToEnd(withID: draggedItemID)
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info _: DropInfo) {
        isDroppingAtEnd = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggedItemID = nil
        dropTargetID = nil
        isDroppingAtEnd = false
        return true
    }
}
