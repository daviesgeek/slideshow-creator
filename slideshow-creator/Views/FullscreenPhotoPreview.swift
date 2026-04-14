import SwiftUI
import AppKit

struct FullscreenPhotoPreview: View {
    let items: [PhotoItem]
    let shortcutFlags: [String]
    @Binding var currentIndex: Int
    let onToggleExclude: (PhotoItem.ID) -> Void
    let onToggleFlag: (Int, PhotoItem.ID) -> Void
    let onClose: () -> Void

    private var hasItems: Bool { !items.isEmpty }

    private var safeIndex: Int {
        guard hasItems else { return 0 }
        return min(max(currentIndex, 0), items.count - 1)
    }

    private var currentItem: PhotoItem? {
        guard hasItems else { return nil }
        return items[safeIndex]
    }

    private func goPrevious() {
        currentIndex = max(0, safeIndex - 1)
    }

    private func goNext() {
        currentIndex = min(items.count - 1, safeIndex + 1)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let item = currentItem {
                if let image = NSImage(contentsOf: item.url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(40)
                } else {
                    Text("Unable to preview image")
                        .foregroundStyle(.white)
                }

                VStack {
                    Spacer()

                    HStack(spacing: 12) {
                        Button("Previous", action: goPrevious)
                            .keyboardShortcut(.leftArrow, modifiers: [])
                            .disabled(safeIndex == 0)

                        Button("Next", action: goNext)
                            .keyboardShortcut(.rightArrow, modifiers: [])
                            .disabled(safeIndex == items.count - 1)

                        Button(item.isExcluded ? "Include (X)" : "Exclude (X)") {
                            onToggleExclude(item.id)
                        }
                        .keyboardShortcut("x", modifiers: [])

                        ForEach(Array(shortcutFlags.enumerated()), id: \.offset) { index, flag in
                            let enabled = item.flags.contains(flag)
                            Button {
                                onToggleFlag(index + 1, item.id)
                            } label: {
                                Text("\(index + 1) \(flag)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(enabled ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
                        }

                        Divider()
                            .frame(height: 18)

                        Text(item.url.path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        } label: {
                            Image(systemName: "arrow.up.forward")
                        }
                        .help("Reveal in Finder")

                        Spacer(minLength: 0)

                        Text("\(safeIndex + 1) / \(items.count)")
                            .font(.caption.monospacedDigit())

                        Button("Close", action: onClose)
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            } else {
                VStack(spacing: 10) {
                    Text("No images to preview")
                        .foregroundStyle(.white)
                    Button("Close", action: onClose)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
        }
        .onAppear {
            guard hasItems else { return }
            currentIndex = safeIndex
        }
    }
}
