import SwiftUI
import AppKit

struct PhotoRow: View {
    let item: PhotoItem
    let shortcutFlags: [String]
    let isSelected: Bool
    let isMissing: Bool
    let effectiveTransitionToNext: PhotoTransitionStyle
    let effectiveTransitionDurationToNext: Double
    let dragProvider: (() -> NSItemProvider)?
    let onActivate: () -> Void
    let onRelink: () -> Void
    let onExcludeToggle: (Bool) -> Void
    let onFlagToggle: (String, Bool) -> Void
    let onTransitionToNextChange: (PhotoTransitionStyle?) -> Void
    let onTransitionDurationToNextChange: (Double?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let dragProvider {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 20)
                    .contentShape(Rectangle())
                    .onDrag(dragProvider)
                    .help("Drag to reorder")
            }

            ThumbnailView(url: item.url, maxPixelSize: 72)
                .frame(width: 72, height: 72)
                .help("Open fullscreen preview")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .lineLimit(1)
                        .foregroundStyle(isMissing ? .red : .primary)

                    if isMissing {
                        Button("Relink…") {
                            onRelink()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                    }

                    Button(item.isExcluded ? "Include (X)" : "Exclude (X)") {
                        onExcludeToggle(!item.isExcluded)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Shortcut: X")

                    if !shortcutFlags.isEmpty {
                        PhotoFlagControlsView(
                            shortcutFlags: shortcutFlags,
                            selectedFlags: item.flags,
                            visibleFlagLimit: 4,
                            onFlagToggle: onFlagToggle
                        )
                    }
                }

                Text(item.url.path)
                    .font(.caption)
                    .foregroundStyle(isMissing ? .red : .secondary)
                    .lineLimit(1)

                if isMissing {
                    Text("Missing file")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }

                if !item.flags.isEmpty {
                    Text(item.flags.sorted().joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Toggle("Override default", isOn: transitionOverrideBinding)
                        .toggleStyle(.checkbox)
                        .font(.caption)

                    Picker("Transition", selection: transitionToNextBinding) {
                        ForEach(PhotoTransitionStyle.allCases) { transition in
                            Text(transition.label).tag(transition)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                    .disabled(!transitionOverrideBinding.wrappedValue)

                    SecondsPerPhotoField(
                        label: "Transition duration:",
                        value: transitionDurationToNextBinding
                    )
                    .disabled(!transitionOverrideBinding.wrappedValue)
                }
            }
        }
        .opacity(item.isExcluded ? 0.45 : 1)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : (isMissing ? Color.red.opacity(0.08) : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .modifier(PhotoRowActivationInteractions(isSelected: isSelected, onActivate: onActivate))
    }
}

extension PhotoRow {
    private var transitionOverrideBinding: Binding<Bool> {
        Binding(
            get: { item.transitionToNext != nil || item.transitionDurationToNext != nil },
            set: { isEnabled in
                if isEnabled {
                    onTransitionToNextChange(item.transitionToNext ?? effectiveTransitionToNext)
                    onTransitionDurationToNextChange(item.transitionDurationToNext ?? effectiveTransitionDurationToNext)
                } else {
                    onTransitionToNextChange(nil)
                    onTransitionDurationToNextChange(nil)
                }
            }
        )
    }

    private var transitionToNextBinding: Binding<PhotoTransitionStyle> {
        Binding(
            get: { item.transitionToNext ?? effectiveTransitionToNext },
            set: { onTransitionToNextChange($0) }
        )
    }

    private var transitionDurationToNextBinding: Binding<Double> {
        Binding(
            get: { item.transitionDurationToNext ?? effectiveTransitionDurationToNext },
            set: { onTransitionDurationToNextChange($0) }
        )
    }
}

private struct PhotoRowActivationInteractions: ViewModifier {
    let isSelected: Bool
    let onActivate: () -> Void

    func body(content: Content) -> some View {
        content
            .onTapGesture(count: 1) {
                let clickCount = NSApp.currentEvent?.clickCount ?? 1
                let modifiers = (NSApp.currentEvent?.modifierFlags ?? [])
                    .intersection([.shift, .command])

                guard modifiers.isEmpty else { return }

                if clickCount == 2 || isSelected {
                    onActivate()
                }
            }
    }
}
