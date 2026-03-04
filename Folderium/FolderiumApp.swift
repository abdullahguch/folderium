import SwiftUI
import AppKit

enum FolderiumTheme {
    static let softDarkWindow = Color(red: 0.16, green: 0.18, blue: 0.21)
    static let softDarkControl = Color(red: 0.20, green: 0.22, blue: 0.26)
    static let softDarkCard = Color(red: 0.23, green: 0.25, blue: 0.30)
    static let softDarkSeparator = Color(red: 0.34, green: 0.37, blue: 0.43)
    static let softDarkStripe = Color.white.opacity(0.04)

    static func windowBackground(isSoftDark: Bool) -> Color {
        isSoftDark ? softDarkWindow : Color(NSColor.windowBackgroundColor)
    }

    static func controlBackground(isSoftDark: Bool) -> Color {
        isSoftDark ? softDarkControl : Color(NSColor.controlBackgroundColor)
    }

    static func cardBackground(isSoftDark: Bool) -> Color {
        isSoftDark ? softDarkCard : Color(NSColor.windowBackgroundColor)
    }

    static func separator(isSoftDark: Bool) -> Color {
        isSoftDark ? softDarkSeparator : Color(NSColor.separatorColor)
    }

    static func stripedRowBackground(isSoftDark: Bool) -> Color {
        isSoftDark ? softDarkStripe : Color(NSColor.controlBackgroundColor).opacity(0.5)
    }
}

enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case newWindow
    case renameSelected
    case copySelected
    case cutSelected
    case pasteIntoActivePane
    case deleteSelected
    case compressSelected
    case refreshActivePane
    case openTerminalActivePane
    case navigateBackActivePane
    case navigateForwardActivePane
    case navigateUpActivePane

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newWindow: return "New Window"
        case .renameSelected: return "Rename Selected Item"
        case .copySelected: return "Copy Selection"
        case .cutSelected: return "Cut Selection"
        case .pasteIntoActivePane: return "Paste Into Active Pane"
        case .deleteSelected: return "Delete Selection"
        case .compressSelected: return "Compress Selection"
        case .refreshActivePane: return "Refresh Active Pane"
        case .openTerminalActivePane: return "Open Active Pane in Terminal"
        case .navigateBackActivePane: return "Navigate Back (Active Pane)"
        case .navigateForwardActivePane: return "Navigate Forward (Active Pane)"
        case .navigateUpActivePane: return "Navigate Up (Active Pane)"
        }
    }
}

struct ShortcutBinding: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var action: ShortcutAction
    var combo: String
    var isEnabled: Bool = true
}

enum ShortcutStore {
    static let storageKey = "folderium.shortcuts.v1"

    static var defaultBindings: [ShortcutBinding] {
        [
            ShortcutBinding(action: .newWindow, combo: "cmd+n"),
            ShortcutBinding(action: .renameSelected, combo: "shift+f2"),
            ShortcutBinding(action: .copySelected, combo: "cmd+c"),
            ShortcutBinding(action: .cutSelected, combo: "cmd+x"),
            ShortcutBinding(action: .pasteIntoActivePane, combo: "cmd+v"),
            ShortcutBinding(action: .deleteSelected, combo: "delete"),
            ShortcutBinding(action: .compressSelected, combo: "space"),
            ShortcutBinding(action: .refreshActivePane, combo: "cmd+r"),
            ShortcutBinding(action: .openTerminalActivePane, combo: "cmd+t"),
            ShortcutBinding(action: .navigateBackActivePane, combo: "cmd+["),
            ShortcutBinding(action: .navigateForwardActivePane, combo: "cmd+]"),
            ShortcutBinding(action: .navigateUpActivePane, combo: "cmd+up")
        ]
    }

    static func load(from rawValue: String) -> [ShortcutBinding] {
        guard !rawValue.isEmpty, let data = rawValue.data(using: .utf8) else {
            return defaultBindings
        }

        do {
            let decoded = try JSONDecoder().decode([ShortcutBinding].self, from: data)
            return migrateLegacyRenameShortcut(decoded)
        } catch {
            return defaultBindings
        }
    }

    private static func migrateLegacyRenameShortcut(_ shortcuts: [ShortcutBinding]) -> [ShortcutBinding] {
        shortcuts.map { shortcut in
            guard shortcut.action == .renameSelected,
                  ShortcutParser.normalizedCombo(shortcut.combo) == "f2" else {
                return shortcut
            }

            var migrated = shortcut
            migrated.combo = "shift+f2"
            return migrated
        }
    }

    static func save(_ shortcuts: [ShortcutBinding]) -> String {
        do {
            let data = try JSONEncoder().encode(shortcuts)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

enum ShortcutParser {
    private static let modifierOrder = ["cmd", "shift", "opt", "ctrl", "fn"]
    private static let validSpecialKeys: Set<String> = [
        "space", "delete", "tab", "enter", "return", "esc", "escape",
        "up", "down", "left", "right",
        "home", "end", "pageup", "pagedown",
        "[", "]", "-", "=", ";", "'", ",", ".", "/", "\\"
    ]

    static func normalizedCombo(_ combo: String) -> String? {
        let compact = combo
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "command", with: "cmd")
            .replacingOccurrences(of: "option", with: "opt")
            .replacingOccurrences(of: "alt", with: "opt")
            .replacingOccurrences(of: "control", with: "ctrl")
            .replacingOccurrences(of: "function", with: "fn")
            .replacingOccurrences(of: "escape", with: "esc")
            .replacingOccurrences(of: "return", with: "enter")
            .replacingOccurrences(of: "uparrow", with: "up")
            .replacingOccurrences(of: "downarrow", with: "down")
            .replacingOccurrences(of: "leftarrow", with: "left")
            .replacingOccurrences(of: "rightarrow", with: "right")

        let parts = compact.split(separator: "+").map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        var modifiers = Set<String>()
        var key: String?

        for part in parts {
            switch part {
            case "cmd", "shift", "opt", "ctrl", "fn":
                modifiers.insert(part)
            default:
                guard key == nil else { return nil }
                key = part
            }
        }

        guard let keyToken = key, isValidKeyToken(keyToken) else { return nil }
        let orderedModifiers = modifierOrder.filter { modifiers.contains($0) }
        return (orderedModifiers + [keyToken]).joined(separator: "+")
    }

    static func comboFromEvent(_ event: NSEvent) -> String? {
        let key = keyToken(from: event) ?? characterToken(from: event)
        guard let key else { return nil }

        var parts: [String] = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { parts.append("cmd") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.option) { parts.append("opt") }
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.function) { parts.append("fn") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    private static func isValidKeyToken(_ token: String) -> Bool {
        if token.count == 1 { return true }
        if token.hasPrefix("f"), let number = Int(token.dropFirst()), number >= 1, number <= 20 { return true }
        return validSpecialKeys.contains(token)
    }

    private static func keyToken(from event: NSEvent) -> String? {
        switch event.keyCode {
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        case 48: return "tab"
        case 51: return "delete"
        case 36, 76: return "enter"
        case 53: return "esc"
        case 122: return "f1"
        case 120: return "f2"
        case 99: return "f3"
        case 118: return "f4"
        case 96: return "f5"
        case 97: return "f6"
        case 98: return "f7"
        case 100: return "f8"
        case 101: return "f9"
        case 109: return "f10"
        case 103: return "f11"
        case 111: return "f12"
        default: return nil
        }
    }

    private static func characterToken(from event: NSEvent) -> String? {
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1 else {
            return nil
        }
        let key = String(chars)
        return isValidKeyToken(key) ? key : nil
    }
}

@main
struct FolderiumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup("Folderium") {
            ContentView()
                .background(
                    WindowChromeConfigurator()
                        .frame(width: 0, height: 0)
                )
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    appDelegate.openNewWindow()
                }
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
        Self.configureWindowChrome(window)
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
        Self.configureWindowChrome(newWindow)
        newWindow.setFrame(screenFrame, display: true)
        newWindow.isReleasedWhenClosed = true
        
        // Show the window
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func configureWindowChrome(_ window: NSWindow) {
        let centeredTitleTag = 98_420
        window.title = "Folderium"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false

        guard let titlebarView = window.standardWindowButton(.closeButton)?.superview else { return }

        if titlebarView.viewWithTag(centeredTitleTag) == nil {
            let titleLabel = NSTextField(labelWithString: "Folderium")
            titleLabel.tag = centeredTitleTag
            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLabel.textColor = .labelColor
            titleLabel.alignment = .center
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titlebarView.addSubview(titleLabel)

            NSLayoutConstraint.activate([
                titleLabel.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: titlebarView.centerYAnchor),
                titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titlebarView.leadingAnchor, constant: 96),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titlebarView.trailingAnchor, constant: -96)
            ])
        }

        let hasDoubleClickRecognizer = titlebarView.gestureRecognizers.contains(where: { recognizer in
            guard let clickRecognizer = recognizer as? NSClickGestureRecognizer else { return false }
            return clickRecognizer.target === TitlebarZoomHandler.shared &&
                clickRecognizer.action == #selector(TitlebarZoomHandler.handleDoubleClick(_:)) &&
                clickRecognizer.numberOfClicksRequired == 2
        })

        if !hasDoubleClickRecognizer {
            let recognizer = NSClickGestureRecognizer(target: TitlebarZoomHandler.shared, action: #selector(TitlebarZoomHandler.handleDoubleClick(_:)))
            recognizer.numberOfClicksRequired = 2
            titlebarView.addGestureRecognizer(recognizer)
        }
    }
}

private final class TitlebarZoomHandler: NSObject {
    static let shared = TitlebarZoomHandler()
    private var previousFrames: [ObjectIdentifier: NSRect] = [:]

    @objc func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended,
              let hostView = recognizer.view,
              let window = hostView.window else { return }

        let location = recognizer.location(in: hostView)
        let controlButtons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let clickedControl = controlButtons.contains { buttonType in
            guard let button = window.standardWindowButton(buttonType) else { return false }
            let frameInTitlebar = button.convert(button.bounds, to: hostView)
            return frameInTitlebar.contains(location)
        }
        guard !clickedControl else { return }

        toggleFillScreenWithoutFullscreen(window)
    }

    private func toggleFillScreenWithoutFullscreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let targetFrame = screen.visibleFrame
        let windowID = ObjectIdentifier(window)

        if isApproximatelyEqual(window.frame, targetFrame),
           let previous = previousFrames[windowID] {
            window.setFrame(previous, display: true, animate: true)
            previousFrames.removeValue(forKey: windowID)
            return
        }

        previousFrames[windowID] = window.frame
        window.setFrame(targetFrame, display: true, animate: true)
    }

    private func isApproximatelyEqual(_ lhs: NSRect, _ rhs: NSRect, tolerance: CGFloat = 2) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
        abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
        abs(lhs.size.width - rhs.size.width) <= tolerance &&
        abs(lhs.size.height - rhs.size.height) <= tolerance
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                AppDelegate.configureWindowChrome(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                AppDelegate.configureWindowChrome(window)
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage("folderium.windowsFamiliarMode") private var windowsFamiliarMode: Bool = true
    @AppStorage("folderium.softDarkThemeEnabled") private var softDarkThemeEnabled: Bool = false
    @AppStorage("folderium.globalFontSize") private var globalFontSize: Double = 12
    @AppStorage(ShortcutStore.storageKey) private var shortcutsRaw: String = ""
    @State private var shortcuts: [ShortcutBinding] = ShortcutStore.defaultBindings
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Folderium Settings")
                    .font(.title)
                
                Text("Privacy-focused file manager for macOS")
                    .foregroundColor(.secondary)
                
                Toggle("Windows Familiar Mode", isOn: $windowsFamiliarMode)
                
                Text("When enabled, Folderium prioritizes File Explorer-like labels and interactions.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Toggle("Soft Dark Theme", isOn: $softDarkThemeEnabled)

                Text("Uses a charcoal-gray dark appearance that is easier on the eyes than pure black.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Global Font Size")
                        Spacer()
                        Text("\(Int(globalFontSize))")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $globalFontSize, in: 11...20, step: 1)
                    Text("Applies a global base font size across the app windows.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                ShortcutSettingsPanel(shortcuts: $shortcuts) {
                    shortcuts = ShortcutStore.defaultBindings
                    shortcutsRaw = ShortcutStore.save(shortcuts)
                }
                
                Spacer(minLength: 0)
            }
            .padding()
        }
        .frame(width: 680, height: 520)
        .onAppear {
            shortcuts = ShortcutStore.load(from: shortcutsRaw)
        }
        .onChange(of: shortcuts) { _, newValue in
            shortcutsRaw = ShortcutStore.save(newValue)
        }
    }
}

struct ShortcutSettingsPanel: View {
    @Binding var shortcuts: [ShortcutBinding]
    let onResetDefaults: () -> Void

    @State private var inputErrors: [UUID: String] = [:]
    
    private var conflictsByID: [UUID: String] {
        var grouped: [String: [ShortcutBinding]] = [:]
        
        for shortcut in shortcuts where shortcut.isEnabled {
            guard let normalized = ShortcutParser.normalizedCombo(shortcut.combo) else { continue }
            grouped[normalized, default: []].append(shortcut)
        }
        
        var result: [UUID: String] = [:]
        for (combo, entries) in grouped where entries.count > 1 {
            let actionNames = entries.map { $0.action.title }.joined(separator: ", ")
            for entry in entries {
                result[entry.id] = "Conflict: '\(combo)' is assigned multiple times (\(actionNames))."
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                Button("Add Shortcut") {
                    shortcuts.append(ShortcutBinding(action: .renameSelected, combo: "shift+f2"))
                }
                .buttonStyle(.bordered)

                Button("Reset Defaults") {
                    onResetDefaults()
                }
                .buttonStyle(.bordered)
            }

            Text("Edit combos like cmd+n, cmd+shift+n, f2, delete, cmd+[ or cmd+up.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !conflictsByID.isEmpty {
                Text("There are \(conflictsByID.count) conflicting shortcut entries.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                        let hasConflict = conflictsByID[shortcut.id] != nil
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Toggle("", isOn: bindingForEnabled(at: index))
                                    .labelsHidden()
                                    .help("Enable/disable this shortcut")

                                Picker("Action", selection: bindingForAction(at: index)) {
                                    ForEach(ShortcutAction.allCases) { action in
                                        Text(action.title).tag(action)
                                    }
                                }
                                .frame(maxWidth: .infinity)

                                TextField("Shortcut", text: bindingForCombo(at: index))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 180)
                                    .onChange(of: shortcuts[index].combo) { _, newValue in
                                        validateShortcutInput(for: shortcuts[index].id, combo: newValue)
                                    }

                                Button {
                                    shortcuts.remove(at: index)
                                    inputErrors[shortcut.id] = nil
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }

                            if let message = inputErrors[shortcut.id] {
                                Text(message)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            } else if let conflictMessage = conflictsByID[shortcut.id] {
                                Text(conflictMessage)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(8)
                        .background(hasConflict ? Color.orange.opacity(0.14) : Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(hasConflict ? Color.orange.opacity(0.7) : Color.clear, lineWidth: 1)
                        )
                        .cornerRadius(8)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 220)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Built-in (not editable)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Up / Down Arrow - Move file selection in active pane")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func validateShortcutInput(for id: UUID, combo: String) {
        let normalized = ShortcutParser.normalizedCombo(combo)
        if normalized == nil {
            inputErrors[id] = "Invalid format."
        } else {
            inputErrors[id] = nil
        }
    }

    private func bindingForAction(at index: Int) -> Binding<ShortcutAction> {
        Binding(
            get: { shortcuts[index].action },
            set: { shortcuts[index].action = $0 }
        )
    }

    private func bindingForCombo(at index: Int) -> Binding<String> {
        Binding(
            get: { shortcuts[index].combo },
            set: { shortcuts[index].combo = $0 }
        )
    }

    private func bindingForEnabled(at index: Int) -> Binding<Bool> {
        Binding(
            get: { shortcuts[index].isEnabled },
            set: { shortcuts[index].isEnabled = $0 }
        )
    }
}
