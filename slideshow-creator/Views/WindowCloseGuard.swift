import SwiftUI
import AppKit

struct WindowCloseGuard: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.model = model
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        weak var model: AppModel?
        weak var window: NSWindow?

        init(model: AppModel) {
            self.model = model
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            guard self.window !== window else { return }

            self.window = window
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            model?.canCloseWindow() ?? true
        }
    }
}
