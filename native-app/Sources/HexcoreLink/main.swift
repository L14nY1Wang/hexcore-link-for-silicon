import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let store = DeviceStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = ContentView().environmentObject(store)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Hexcore Link"
        window.titlebarAppearsTransparent = true
        // center() follows the screen with keyboard focus, which is not always
        // the display the user is looking at; pin the window to the primary
        // display's visible frame instead.
        if let screen = NSScreen.screens.first {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            ))
        }
        window.contentView = NSHostingView(rootView: root)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        // The split view installs a sidebar toggle in the system toolbar; its
        // position shifts as the window resizes. The app draws its own fixed
        // button inside the detail pane instead.
        DispatchQueue.main.async {
            window.toolbar = nil
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.appearance = NSAppearance(named: .aqua)
    app.run()
}
