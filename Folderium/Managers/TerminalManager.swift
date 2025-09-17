import Foundation
import AppKit
import SwiftUI

class TerminalManager: ObservableObject {
    static let shared = TerminalManager()
    
    @Published var isTerminalOpen: Bool = false
    @Published var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    
    private var terminalProcess: Process?
    private var terminalWindow: NSWindow?
    
    private init() {}
    
    // MARK: - Terminal Operations
    
    func openTerminal(at directory: URL) {
        currentDirectory = directory
        isTerminalOpen = true
        
        // Try to open Terminal.app with the specified directory
        openInTerminalApp(directory: directory)
    }
    
    func openInTerminalApp(directory: URL) {
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(directory.path)'"
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            print("Error opening Terminal: \(error)")
            // Fallback to iTerm2 if available
            openInITerm2(directory: directory)
        }
    }
    
    func openInITerm2(directory: URL) {
        let script = """
        tell application "iTerm"
            activate
            tell current window
                tell current session
                    write text "cd '\(directory.path)'"
                end tell
            end tell
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            print("Error opening iTerm2: \(error)")
            // Fallback to built-in terminal
            openBuiltInTerminal(directory: directory)
        }
    }
    
    func openBuiltInTerminal(directory: URL) {
        // Create a new window with a terminal view
        let terminalView = TerminalView(directory: directory)
        let hostingView = NSHostingView(rootView: terminalView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Terminal - \(directory.lastPathComponent)"
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        terminalWindow = window
    }
    
    func closeTerminal() {
        terminalWindow?.close()
        terminalWindow = nil
        isTerminalOpen = false
    }
    
    func syncDirectory(_ directory: URL) {
        currentDirectory = directory
        // Notify the terminal about directory change
        NotificationCenter.default.post(name: .terminalDirectoryChanged, object: directory)
    }
    
    // MARK: - Command Execution
    
    func executeCommand(_ command: String, in directory: URL) async throws -> CommandResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/bash")
                    process.arguments = ["-c", command]
                    process.currentDirectoryURL = directory
                    
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let error = String(data: errorData, encoding: .utf8) ?? ""
                    
                    let result = CommandResult(
                        command: command,
                        output: output,
                        error: error,
                        exitCode: process.terminationStatus,
                        executionTime: Date()
                    )
                    
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Directory Synchronization
    
    func getCurrentTerminalDirectory() -> URL? {
        // This would require more complex integration with the actual terminal
        // For now, we'll return the last known directory
        return currentDirectory
    }
    
    func updateDirectoryFromTerminal(_ directory: URL) {
        currentDirectory = directory
        // Notify the file manager about the directory change
        NotificationCenter.default.post(name: .fileManagerDirectoryChanged, object: directory)
    }
}

// MARK: - Terminal View

struct TerminalView: View {
    let directory: URL
    @State private var command: String = ""
    @State private var output: String = ""
    @State private var isExecuting: Bool = false
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int = -1
    
    var body: some View {
        VStack(spacing: 0) {
            // Directory info
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.blue)
                Text(directory.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Output area
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(output)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
            }
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            // Command input
            HStack {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                
                TextField("Enter command...", text: $command)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .onSubmit {
                        executeCommand()
                    }
                    .onKeyPress(.upArrow) {
                        navigateHistory(up: true)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        navigateHistory(up: false)
                        return .handled
                    }
                
                if isExecuting {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            output = "Terminal ready. Current directory: \(directory.path)\n"
        }
        .onReceive(NotificationCenter.default.publisher(for: .terminalDirectoryChanged)) { notification in
            if let newDirectory = notification.object as? URL {
                output += "\nDirectory changed to: \(newDirectory.path)\n"
            }
        }
    }
    
    private func executeCommand() {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let commandToExecute = command
        commandHistory.append(commandToExecute)
        historyIndex = commandHistory.count
        
        output += "$ \(commandToExecute)\n"
        command = ""
        isExecuting = true
        
        Task {
            do {
                let result = try await TerminalManager.shared.executeCommand(commandToExecute, in: directory)
                
                await MainActor.run {
                    if !result.output.isEmpty {
                        output += result.output
                    }
                    if !result.error.isEmpty {
                        output += "Error: \(result.error)"
                    }
                    if result.exitCode != 0 {
                        output += "Exit code: \(result.exitCode)\n"
                    }
                    output += "\n"
                    isExecuting = false
                }
            } catch {
                await MainActor.run {
                    output += "Error executing command: \(error.localizedDescription)\n"
                    isExecuting = false
                }
            }
        }
    }
    
    private func navigateHistory(up: Bool) {
        guard !commandHistory.isEmpty else { return }
        
        if up {
            if historyIndex > 0 {
                historyIndex -= 1
                command = commandHistory[historyIndex]
            }
        } else {
            if historyIndex < commandHistory.count - 1 {
                historyIndex += 1
                command = commandHistory[historyIndex]
            } else {
                historyIndex = commandHistory.count
                command = ""
            }
        }
    }
}

// MARK: - Data Models

struct CommandResult {
    let command: String
    let output: String
    let error: String
    let exitCode: Int32
    let executionTime: Date
}

// MARK: - Notifications

extension Notification.Name {
    static let terminalDirectoryChanged = Notification.Name("terminalDirectoryChanged")
    static let fileManagerDirectoryChanged = Notification.Name("fileManagerDirectoryChanged")
}

// MARK: - Terminal Integration

class TerminalIntegration: ObservableObject {
    @Published var isIntegrated: Bool = false
    @Published var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    
    private var fileWatcher: FileWatcher?
    
    func startIntegration() {
        isIntegrated = true
        startFileWatching()
        
        NotificationCenter.default.addObserver(
            forName: .terminalDirectoryChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let directory = notification.object as? URL {
                self?.currentDirectory = directory
            }
        }
    }
    
    func stopIntegration() {
        isIntegrated = false
        fileWatcher?.stop()
        fileWatcher = nil
        
        NotificationCenter.default.removeObserver(self)
    }
    
    private func startFileWatching() {
        fileWatcher = FileWatcher(directory: currentDirectory) { [weak self] url in
            DispatchQueue.main.async {
                self?.currentDirectory = url
                NotificationCenter.default.post(name: .terminalDirectoryChanged, object: url)
            }
        }
        fileWatcher?.start()
    }
}

// MARK: - File Watcher

class FileWatcher {
    private let directory: URL
    private let callback: (URL) -> Void
    private var fileSystemSource: DispatchSourceFileSystemObject?
    
    init(directory: URL, callback: @escaping (URL) -> Void) {
        self.directory = directory
        self.callback = callback
    }
    
    func start() {
        let fileDescriptor = open(directory.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }
        
        fileSystemSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .background)
        )
        
        fileSystemSource?.setEventHandler { [weak self] in
            self?.callback(self?.directory ?? URL(fileURLWithPath: "/"))
        }
        
        fileSystemSource?.resume()
    }
    
    func stop() {
        fileSystemSource?.cancel()
        fileSystemSource = nil
    }
    
    deinit {
        stop()
    }
}
