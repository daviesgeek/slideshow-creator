import SwiftUI

struct PhotoContextMenuContent: View {
    enum MoveDestination {
        case top
        case up
        case down
        case bottom
    }

    let targetItems: [PhotoItem]
    let primaryItem: PhotoItem
    let shortcutFlags: [String]
    let onOpenFullscreen: (() -> Void)?
    let onRevealInFinder: ([PhotoItem]) -> Void
    let onOpenInDefaultApp: ([PhotoItem]) -> Void
    let onSetExcluded: (Bool, [PhotoItem]) -> Void
    let onSetFlagEnabled: (String, Bool, [PhotoItem]) -> Void
    let onMove: (MoveDestination, [PhotoItem]) -> Void

    private var effectiveItems: [PhotoItem] {
        targetItems.isEmpty ? [primaryItem] : targetItems
    }

    private var allIncluded: Bool {
        !effectiveItems.isEmpty && effectiveItems.allSatisfy { !$0.isExcluded }
    }

    private var allExcluded: Bool {
        !effectiveItems.isEmpty && effectiveItems.allSatisfy(\.isExcluded)
    }

    var body: some View {
        if let onOpenFullscreen {
            Button("Open Fullscreen Preview") {
                onOpenFullscreen()
            }

            Divider()
        }

        Button("Reveal in Finder") {
            onRevealInFinder(effectiveItems)
        }

        Button("Open in Default App") {
            onOpenInDefaultApp(effectiveItems)
        }

        Divider()

        if allIncluded {
            Button(excludeLabel) {
                onSetExcluded(true, effectiveItems)
            }
        } else if allExcluded {
            Button(includeLabel) {
                onSetExcluded(false, effectiveItems)
            }
        } else {
            Button(includeSelectedLabel) {
                onSetExcluded(false, effectiveItems)
            }

            Button(excludeSelectedLabel) {
                onSetExcluded(true, effectiveItems)
            }
        }

        Menu("Flags") {
            ForEach(shortcutFlags, id: \.self) { flag in
                let shouldRemove = effectiveItems.allSatisfy { $0.flags.contains(flag) }

                Button(shouldRemove ? "Remove \(flag)" : "Add \(flag)") {
                    onSetFlagEnabled(flag, !shouldRemove, effectiveItems)
                }
            }
        }

        Menu("Move To") {
            Button("Top") {
                onMove(.top, effectiveItems)
            }

            Button("Up") {
                onMove(.up, effectiveItems)
            }

            Button("Down") {
                onMove(.down, effectiveItems)
            }

            Button("Bottom") {
                onMove(.bottom, effectiveItems)
            }
        }
    }

    private var includeLabel: String {
        effectiveItems.count > 1 ? includeSelectedLabel : "Include"
    }

    private var excludeLabel: String {
        effectiveItems.count > 1 ? excludeSelectedLabel : "Exclude"
    }

    private var includeSelectedLabel: String {
        effectiveItems.count > 1 ? "Include Selected" : "Include"
    }

    private var excludeSelectedLabel: String {
        effectiveItems.count > 1 ? "Exclude Selected" : "Exclude"
    }
}
