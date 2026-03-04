import Foundation
import AppKit

class TerminalManager: ObservableObject {
    @Published var currentDirectory: URL = SandboxAccessManager.defaultDirectory
    
    func openTerminal(at directory: URL) {
        currentDirectory = directory
        
        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            NSWorkspace.shared.open(directory)
            return
        }
        
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([directory], withApplicationAt: terminalURL, configuration: configuration) { _, error in
            if let error {
                print("Failed to open Terminal at \(directory.path): \(error.localizedDescription)")
                NSWorkspace.shared.open(directory)
            }
        }
    }
}
