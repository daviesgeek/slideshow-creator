import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct PhotosPaneView: View {
    @ObservedObject var model: AppModel
    let isKeyboardNavigationEnabled: Bool
    let onThumbnailTap: (PhotoItem) -> Void

    @State private var draggedPhotoIDs: Set<PhotoItem.ID> = []
    @State private var gridDropTargetID: PhotoItem.ID?
    @State private var gridDropTargetEdge: GridDropEdge?
    @State private var isGridDroppingAtEnd = false
    @State private var gridAvailableWidth: CGFloat = 0

    private var selectedPhotoIDs: Set<PhotoItem.ID> { model.selectedPhotoIDs }
    private var visibleSelectedPhotoIDs: Set<PhotoItem.ID> {
        selectedPhotoIDs.intersection(Set(filteredItems.map(\.id)))
    }
    private var selectedPhotoCount: Int { visibleSelectedPhotoIDs.count }
    private var hasSelection: Bool { selectedPhotoCount > 0 }
    private var selectedDragPreviewItems: [PhotoItem] {
        guard !visibleSelectedPhotoIDs.isEmpty else { return [] }
        return filteredItems.filter { visibleSelectedPhotoIDs.contains($0.id) }
    }
    private var selectedDragSelectionCount: Int {
        max(1, visibleSelectedPhotoIDs.count)
    }
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

    private var gridEffectiveCellWidth: CGFloat {
        let totalSpacing = CGFloat(max(gridColumnCount - 1, 0)) * gridSpacing
        let available = max(0, gridAvailableWidth - totalSpacing)
        return max(1, available / CGFloat(gridColumnCount))
    }

    private var gridThumbnailMaxPixelSize: CGFloat {
        max(gridCellWidth, gridThumbnailHeight)
    }

    private var gridCellWidth: CGFloat {
        CGFloat(model.photosGridCellWidth)
    }

    private var filteredItems: [PhotoItem] {
        model.filteredPhotoItems
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
        .onAppear(perform: syncSelectionToFilter)
        .onChange(of: model.photosExclusionFilter) { _, _ in
            syncSelectionToFilter()
        }
        .onChange(of: model.items) { _, _ in
            syncSelectionToFilter()
        }
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

            Picker("Filter", selection: $model.photosExclusionFilter) {
                ForEach(AppModel.PhotosExclusionFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)

            if model.photosViewMode == .grid {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.grid.2x2")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Slider(value: $model.photosGridCellWidth, in: Double(gridMinCellWidth) ... Double(gridMaxCellWidth))
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
            ForEach(filteredItems) { item in
                PhotoRow(
                    item: item,
                    shortcutFlags: model.shortcutFlags,
                    isSelected: visibleSelectedPhotoIDs.contains(item.id),
                    dragProvider: {
                        beginPhotoDrag(for: item.id)
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
        ScrollViewReader { proxy in
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
                    ForEach(filteredItems) { item in
                        let isInVisibleSelection = visibleSelectedPhotoIDs.contains(item.id)

                        PhotoGridCellView(
                            item: item,
                            shortcutFlags: model.shortcutFlags,
                            isSelected: isInVisibleSelection,
                            isDropTarget: gridDropTargetID == item.id,
                            isDropTargetOnTrailingEdge: gridDropTargetEdge == .trailing,
                            dragPreviewItems: isInVisibleSelection ? selectedDragPreviewItems : [item],
                            dragSelectionCount: isInVisibleSelection ? selectedDragSelectionCount : 1,
                            thumbnailHeight: gridThumbnailHeight,
                            thumbnailMaxPixelSize: gridThumbnailMaxPixelSize,
                            onSelect: { modifiers in
                                handleGridSelection(for: item.id, modifiers: modifiers)
                            },
                            onThumbnailTap: {
                                model.selectPhoto(item.id)
                                onThumbnailTap(item)
                            },
                            onFlagToggle: { flag, isEnabled in
                                model.setFlag(flag, enabled: isEnabled, for: item.id)
                            },
                            dragProvider: {
                                beginPhotoDrag(for: item.id)
                                return NSItemProvider(object: item.id.uuidString as NSString)
                            }
                        )
                        .id(item.id)
                        .onDrop(
                            of: [UTType.text],
                            delegate: GridPhotoDropDelegate(
                                targetItemID: item.id,
                                visibleItemIDs: filteredItems.map(\.id),
                                cellWidth: gridEffectiveCellWidth,
                                model: model,
                                draggedItemIDs: $draggedPhotoIDs,
                                dropTargetID: $gridDropTargetID,
                                dropTargetEdge: $gridDropTargetEdge,
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
                                draggedItemIDs: $draggedPhotoIDs,
                                dropTargetID: $gridDropTargetID,
                                dropTargetEdge: $gridDropTargetEdge,
                                isDroppingAtEnd: $isGridDroppingAtEnd
                            )
                        )
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                scrollGridSelectionIntoView(with: proxy, animated: false)
            }
            .onChange(of: model.selectedPhotoID) { _, _ in
                scrollGridSelectionIntoView(with: proxy)
            }
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
                    model.moveSelectedPhotosToTop(visibleSelectedPhotoIDs)
                }
                Button("Up") {
                    model.moveSelectedPhotosUp(visibleSelectedPhotoIDs)
                }
                Button("Down") {
                    model.moveSelectedPhotosDown(visibleSelectedPhotoIDs)
                }
                Button("Bottom") {
                    model.moveSelectedPhotosToBottom(visibleSelectedPhotoIDs)
                }
            }
            .disabled(!hasSelection)

            Divider()
                .frame(height: 14)

            Button("Include") {
                model.setPhotosExcluded(false, for: visibleSelectedPhotoIDs)
            }
            .disabled(!hasSelection)

            Button("Exclude") {
                model.setPhotosExcluded(true, for: visibleSelectedPhotoIDs)
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

            if model.photosViewMode == .grid && isKeyboardNavigationEnabled {
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
        guard !draggedPhotoIDs.isEmpty else { return }

        if index >= filteredItems.count {
            model.movePhotosToEnd(withIDs: draggedPhotoIDs)
        } else {
            model.movePhotos(withIDs: draggedPhotoIDs, before: filteredItems[index].id)
        }

        draggedPhotoIDs = []
    }

    private func moveGridSelection(horizontalDelta: Int = 0, verticalDelta: Int = 0) {
        guard model.photosViewMode == .grid else { return }
        guard !filteredItems.isEmpty else { return }

        let currentIndex = model.selectedPhotoID.flatMap { selectedID in
            filteredItems.firstIndex(where: { $0.id == selectedID })
        } ?? 0

        let movement = horizontalDelta + (verticalDelta * gridColumnCount)
        let targetIndex = min(max(0, currentIndex + movement), filteredItems.count - 1)
        model.selectPhoto(filteredItems[targetIndex].id)
    }

    private func handleGridSelection(for id: PhotoItem.ID, modifiers: NSEvent.ModifierFlags) {
        let orderedIDs = filteredItems.map(\.id)
        let isShift = modifiers.contains(.shift)
        let isCommand = modifiers.contains(.command)

        if isShift {
            model.extendPhotoSelection(to: id, orderedIDs: orderedIDs, additive: isCommand)
        } else if isCommand {
            model.togglePhotoSelection(id)
        } else {
            model.selectPhoto(id)
        }
    }

    private func beginPhotoDrag(for id: PhotoItem.ID) {
        let selected = model.selectedPhotoIDs
        if selected.contains(id) {
            draggedPhotoIDs = selected
        } else {
            model.selectPhoto(id)
            draggedPhotoIDs = [id]
        }
    }

    private func scrollGridSelectionIntoView(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard model.photosViewMode == .grid, let selectedPhotoID = model.selectedPhotoID else { return }

        let action = {
            proxy.scrollTo(selectedPhotoID, anchor: .center)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.12), action)
        } else {
            action()
        }
    }

    private func syncSelectionToFilter() {
        let visibleIDs = Set(filteredItems.map(\.id))
        let updatedSelection = model.selectedPhotoIDs.intersection(visibleIDs)

        if updatedSelection != model.selectedPhotoIDs {
            if updatedSelection.isEmpty {
                model.selectPhoto(filteredItems.first?.id)
            } else {
                model.selectPhotos(updatedSelection)
            }
        } else if updatedSelection.isEmpty, model.selectedPhotoID == nil {
            model.selectPhoto(filteredItems.first?.id)
        }
    }
}

private enum GridDropEdge {
    case leading
    case trailing
}

private struct GridPhotoDropDelegate: DropDelegate {
    let targetItemID: PhotoItem.ID
    let visibleItemIDs: [PhotoItem.ID]
    let cellWidth: CGFloat
    let model: AppModel
    @Binding var draggedItemIDs: Set<PhotoItem.ID>
    @Binding var dropTargetID: PhotoItem.ID?
    @Binding var dropTargetEdge: GridDropEdge?
    @Binding var isDroppingAtEnd: Bool

    private func edge(for info: DropInfo) -> GridDropEdge {
        info.location.x < (max(1, cellWidth) * 0.5) ? .leading : .trailing
    }

    private func firstVisibleIDAfterTargetExcludingDragged() -> PhotoItem.ID? {
        guard let targetIndex = visibleItemIDs.firstIndex(of: targetItemID), targetIndex + 1 < visibleItemIDs.count else {
            return nil
        }

        for id in visibleItemIDs[(targetIndex + 1)...] where !draggedItemIDs.contains(id) {
            return id
        }

        return nil
    }

    func dropEntered(info: DropInfo) {
        guard !draggedItemIDs.isEmpty else { return }
        guard !draggedItemIDs.contains(targetItemID) else { return }

        isDroppingAtEnd = false
        dropTargetID = targetItemID
        dropTargetEdge = edge(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard !draggedItemIDs.isEmpty else { return nil }
        guard !draggedItemIDs.contains(targetItemID) else { return nil }

        isDroppingAtEnd = false
        dropTargetID = targetItemID
        dropTargetEdge = edge(for: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard !draggedItemIDs.isEmpty else {
            dropTargetID = nil
            dropTargetEdge = nil
            isDroppingAtEnd = false
            return true
        }

        switch edge(for: info) {
        case .leading:
            model.movePhotos(withIDs: draggedItemIDs, before: targetItemID)
        case .trailing:
            if let nextID = firstVisibleIDAfterTargetExcludingDragged() {
                model.movePhotos(withIDs: draggedItemIDs, before: nextID)
            } else {
                model.movePhotosToEnd(withIDs: draggedItemIDs)
            }
        }

        draggedItemIDs = []
        dropTargetID = nil
        dropTargetEdge = nil
        isDroppingAtEnd = false
        return true
    }
}

private struct GridPhotoDropToEndDelegate: DropDelegate {
    let model: AppModel
    @Binding var draggedItemIDs: Set<PhotoItem.ID>
    @Binding var dropTargetID: PhotoItem.ID?
    @Binding var dropTargetEdge: GridDropEdge?
    @Binding var isDroppingAtEnd: Bool

    func dropEntered(info _: DropInfo) {
        guard !draggedItemIDs.isEmpty else { return }
        dropTargetID = nil
        dropTargetEdge = nil
        isDroppingAtEnd = true
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info _: DropInfo) {
        isDroppingAtEnd = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        if !draggedItemIDs.isEmpty {
            model.movePhotosToEnd(withIDs: draggedItemIDs)
        }
        draggedItemIDs = []
        dropTargetID = nil
        dropTargetEdge = nil
        isDroppingAtEnd = false
        return true
    }
}
