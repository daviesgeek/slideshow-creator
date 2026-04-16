import SwiftUI
import AppKit

extension View {
    func onSecondaryClick(perform action: @escaping () -> Void) -> some View {
        modifier(SecondaryClickModifier(onSecondaryClick: action))
    }
}

private struct SecondaryClickModifier: ViewModifier {
    let onSecondaryClick: () -> Void

    func body(content: Content) -> some View {
        content.background(SecondaryClickMonitor(onSecondaryClick: onSecondaryClick))
    }
}

private struct SecondaryClickMonitor: NSViewRepresentable {
    let onSecondaryClick: () -> Void

    func makeNSView(context _: Context) -> MonitorView {
        let view = MonitorView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ nsView: MonitorView, context _: Context) {
        nsView.onSecondaryClick = onSecondaryClick
    }

    final class MonitorView: NSView {
        var onSecondaryClick: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if window != nil {
                installMonitorIfNeeded()
            } else {
                removeMonitor()
            }
        }

        deinit {
            removeMonitor()
        }

        private func installMonitorIfNeeded() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else {
                    return event
                }

                let isSecondaryClick = event.type == .rightMouseDown ||
                    (event.type == .leftMouseDown && event.modifierFlags.contains(.control))

                guard isSecondaryClick else { return event }

                let point = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(point) {
                    self.onSecondaryClick?()
                }

                return event
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
