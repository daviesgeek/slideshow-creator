import SwiftUI

struct PersistentHSplitView<Left: View, Right: View>: View {
    @Binding var ratio: Double

    let minLeftWidth: CGFloat
    let minRightWidth: CGFloat
    let dividerWidth: CGFloat
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right

    @State private var dragStartRatio: Double?

    init(
        ratio: Binding<Double>,
        minLeftWidth: CGFloat,
        minRightWidth: CGFloat,
        dividerWidth: CGFloat = 8,
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right
    ) {
        _ratio = ratio
        self.minLeftWidth = minLeftWidth
        self.minRightWidth = minRightWidth
        self.dividerWidth = dividerWidth
        self.left = left
        self.right = right
    }

    var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let contentWidth = max(0, totalWidth - dividerWidth)
            let minRatio = minAllowedRatio(for: contentWidth)
            let maxRatio = maxAllowedRatio(for: contentWidth)
            let clampedRatio = clamp(ratio, min: minRatio, max: maxRatio)
            let leftWidth = contentWidth * clampedRatio
            let rightWidth = contentWidth - leftWidth

            HStack(spacing: 0) {
                left()
                    .frame(width: leftWidth)

                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: dividerWidth)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: 2, height: 28)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard contentWidth > 0 else { return }
                                let startRatio = dragStartRatio ?? ratio
                                dragStartRatio = startRatio
                                let delta = Double(value.translation.width / contentWidth)
                                ratio = clamp(startRatio + delta, min: minRatio, max: maxRatio)
                            }
                            .onEnded { _ in
                                dragStartRatio = nil
                            }
                    )

                right()
                    .frame(width: rightWidth)
            }
            .frame(width: totalWidth, height: proxy.size.height)
            .onAppear {
                if ratio != clampedRatio {
                    ratio = clampedRatio
                }
            }
            .onChange(of: totalWidth) { _, _ in
                if ratio != clampedRatio {
                    ratio = clampedRatio
                }
            }
        }
    }

    private func minAllowedRatio(for contentWidth: CGFloat) -> Double {
        guard contentWidth > 0 else { return 0 }
        return Double(min(max(0, minLeftWidth / contentWidth), 1))
    }

    private func maxAllowedRatio(for contentWidth: CGFloat) -> Double {
        guard contentWidth > 0 else { return 1 }
        return Double(min(max(0, 1 - (minRightWidth / contentWidth)), 1))
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}
