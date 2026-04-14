import SwiftUI

struct PhotoFlagControlsView: View {
    let shortcutFlags: [String]
    let selectedFlags: Set<String>
    let visibleFlagLimit: Int
    let onFlagToggle: (String, Bool) -> Void

    private var visibleFlags: ArraySlice<(offset: Int, element: String)> {
        Array(shortcutFlags.enumerated()).prefix(visibleFlagLimit)
    }

    private var overflowFlags: ArraySlice<(offset: Int, element: String)> {
        Array(shortcutFlags.enumerated()).dropFirst(visibleFlagLimit)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(visibleFlags), id: \.offset) { index, flag in
                flagButton(flag: flag, shortcutNumber: index + 1)
            }

            if !overflowFlags.isEmpty {
                Menu {
                    ForEach(Array(overflowFlags), id: \.offset) { index, flag in
                        let enabled = selectedFlags.contains(flag)
                        Button(enabled ? "Remove \(flag)" : "Add \(flag)") {
                            onFlagToggle(flag, !enabled)
                        }
                    }
                } label: {
                    Text("+\(overflowFlags.count)")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.18), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .help("More flags")
            }
        }
    }

    private func flagButton(flag: String, shortcutNumber: Int) -> some View {
        let enabled = selectedFlags.contains(flag)

        return Button {
            onFlagToggle(flag, !enabled)
        } label: {
            Text("\(shortcutNumber) \(flag)")
                .font(.caption2)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(enabled ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Shortcut: \(shortcutNumber)")
    }
}
