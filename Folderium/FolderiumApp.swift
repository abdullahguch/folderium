import SwiftUI

@main
struct FolderiumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    AppDelegate.shared.openNewWindow()
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
    static let shared = AppDelegate()
    
    private override init() {
        super.init()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy to regular
        NSApp.setActivationPolicy(.regular)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Create a new window when clicking the dock icon if no windows are visible
            openNewWindow()
        }
        return true
    }
    
    func openNewWindow() {
        // Create a new window using NSWindow
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        let contentView = ContentView()
        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.title = "Folderium"
        newWindow.center()
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
