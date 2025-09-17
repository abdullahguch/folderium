import SwiftUI

@main
struct FolderiumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    appDelegate.openNewWindow()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
        
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy to regular
        NSApp.setActivationPolicy(.regular)
        
        // Maximize the initial window to screen size
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.maximizeInitialWindow()
        }
    }
    
    private func maximizeInitialWindow() {
        guard let window = NSApp.windows.first else { return }
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        window.setFrame(screenFrame, display: true, animate: true)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Create a new window when clicking the dock icon if no windows are visible
            openNewWindow()
        }
        return true
    }
    
    func openNewWindow() {
        // Get the screen size for full-screen window
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        
        // Create a new window using NSWindow with screen size
        let newWindow = NSWindow(
            contentRect: screenFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        let contentView = ContentView()
        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.title = "Folderium"
        newWindow.setFrame(screenFrame, display: true)
        newWindow.isReleasedWhenClosed = true
        
        // Show the window
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    var body: some View {
        VStack {
            Text("Folderium Settings")
                .font(.title)
                .padding()
            
            Text("Privacy-focused file manager for macOS")
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .frame(width: 400, height: 300)
    }
}
