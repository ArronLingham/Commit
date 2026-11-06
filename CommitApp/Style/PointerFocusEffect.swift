import AppKit
import SwiftUI

/// Keep a focus indicator for keyboard navigation without leaving it visible after a mouse click.
@MainActor
private final class InputFocusMode: ObservableObject {
    @Published var pointerActive = false
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            let pointerActive = event.type != .keyDown
            if self?.pointerActive != pointerActive { self?.pointerActive = pointerActive }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct PointerFocusEffect: ViewModifier {
    @StateObject private var input = InputFocusMode()

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled(input.pointerActive)
            .onAppear { input.start() }
            .onDisappear { input.stop() }
    }
}

extension View {
    func focusEffectForInput() -> some View { modifier(PointerFocusEffect()) }
}
