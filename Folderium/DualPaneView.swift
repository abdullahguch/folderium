import SwiftUI

enum ActivePane {
    case left, right
}

struct QuickLocation: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let url: URL
}

struct DraggableModifier: ViewModifier {
    let selection: Set<URL>
    let dragPreview: () -> AnyView
    
    func body(content: Content) -> some View {
        if selection.isEmpty {
            content
        } else {
            content.draggable(selection.first!) {
                dragPreview()
            }
        }
    }
}


struct DualPaneView: View {
    private let defaultQuickAccessWidth: CGFloat = 220
    private let defaultPaneSplitRatio: CGFloat = 0.5
    private let defaultTerminalHeight: CGFloat = 200
    @AppStorage("folderium.windowsFamiliarMode") private var windowsFamiliarMode: Bool = true
    @AppStorage("folderium.showWindowsOnboarding") private var showWindowsOnboarding: Bool = true
    @AppStorage("folderium.pinnedPaths") private var pinnedPathsRaw: String = ""
    @State private var leftPath: URL = SandboxAccessManager.defaultDirectory
    @State private var rightPath: URL = SandboxAccessManager.defaultDirectory
    @State private var leftSelection: Set<URL> = []
    @State private var rightSelection: Set<URL> = []
    @State private var leftSearchText: String = ""
    @State private var rightSearchText: String = ""
    @State private var leftIsSearching: Bool = false
    @State private var rightIsSearching: Bool = false
    @State private var showLeftTerminal: Bool = false
    @State private var showRightTerminal: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var filesToDelete: [URL] = []
    @State private var refreshTrigger: UUID = UUID()
    @State private var activePane: ActivePane = .left // Track which pane is currently active
    @State private var clipboardCheckTrigger: UUID = UUID() // To check clipboard state
    @State private var isCutOperation: Bool = false // Track if last operation was cut
    @State private var leftBackHistory: [URL] = []
    @State private var leftForwardHistory: [URL] = []
    @State private var rightBackHistory: [URL] = []
    @State private var rightForwardHistory: [URL] = []
    @State private var isNavigatingLeftHistory: Bool = false
    @State private var isNavigatingRightHistory: Bool = false
    @State private var quickAccessWidth: CGFloat = 220
    @State private var paneSplitRatio: CGFloat = 0.5
    @State private var leftTerminalHeight: CGFloat = 200
    @State private var rightTerminalHeight: CGFloat = 200
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var paneSplitDragStartLeftWidth: CGFloat?
    @State private var leftTerminalDragStartHeight: CGFloat?
    @State private var rightTerminalDragStartHeight: CGFloat?
    
    // Callback to notify parent of selection changes
    var onSelectionChange: ((Set<URL>) -> Void)?
    
    private var quickLocations: [QuickLocation] {
        let fileManager = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        
        func firstURL(_ directory: FileManager.SearchPathDirectory) -> URL {
            fileManager.urls(for: directory, in: .userDomainMask).first ?? home
        }
        
        return [
            QuickLocation(name: "Home", icon: "house", url: home),
            QuickLocation(name: "Desktop", icon: "desktopcomputer", url: firstURL(.desktopDirectory)),
            QuickLocation(name: "Documents", icon: "doc.text", url: firstURL(.documentDirectory)),
            QuickLocation(name: "Downloads", icon: "arrow.down.circle", url: firstURL(.downloadsDirectory)),
            QuickLocation(name: "Pictures", icon: "photo", url: firstURL(.picturesDirectory)),
            QuickLocation(name: "Music", icon: "music.note", url: firstURL(.musicDirectory)),
            QuickLocation(name: "Movies", icon: "film", url: firstURL(.moviesDirectory))
        ]
    }
    
    private var mountedVolumes: [QuickLocation] {
        let volumeURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey],
            options: [.skipHiddenVolumes]
        ) ?? []
        
        return volumeURLs.map { url in
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.lastPathComponent
            return QuickLocation(name: name, icon: "externaldrive", url: url)
        }
    }
    
    private var recentLocations: [QuickLocation] {
        let merged = (leftBackHistory + rightBackHistory + leftForwardHistory + rightForwardHistory).reversed()
        var seen = Set<String>()
        var result: [QuickLocation] = []
        
        for url in merged {
            if seen.contains(url.path) { continue }
            seen.insert(url.path)
            result.append(QuickLocation(name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, icon: "clock.arrow.circlepath", url: url))
            if result.count >= 6 { break }
        }
        
        return result
    }
    
    private var pinnedLocations: [QuickLocation] {
        pinnedPathsRaw
            .split(separator: "\n")
            .map(String.init)
            .compactMap { path in
                guard !path.isEmpty else { return nil }
                return QuickLocation(
                    name: URL(fileURLWithPath: path).lastPathComponent.isEmpty ? path : URL(fileURLWithPath: path).lastPathComponent,
                    icon: "pin",
                    url: URL(fileURLWithPath: path)
                )
            }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if windowsFamiliarMode && showWindowsOnboarding {
                HStack {
                    Image(systemName: "lightbulb")
                        .foregroundColor(.yellow)
                    Text("Windows Familiar Mode is on: use F2 to rename, Back/Forward/Up to navigate, and Explorer-style context menus.")
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") {
                        showWindowsOnboarding = false
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.12))
                
                Divider()
            }
            
            HStack(spacing: 8) {
                explorerToolbarButton("Open Left", systemImage: "folder.badge.plus") { selectFolder(for: .left) }
                explorerToolbarButton("Open Right", systemImage: "folder.badge.plus") { selectFolder(for: .right) }
                
                Divider().frame(height: 18)
                
                explorerToolbarButton("Copy", systemImage: "doc.on.doc") { copySelectedFiles() }
                    .disabled(leftSelection.isEmpty && rightSelection.isEmpty)
                explorerToolbarButton("Cut", systemImage: "scissors") { cutSelectedFiles() }
                    .disabled(leftSelection.isEmpty && rightSelection.isEmpty)
                explorerToolbarButton("Paste", systemImage: "doc.on.clipboard") { pasteFiles() }
                    .disabled(!hasFilesInClipboard())
                    .onChange(of: clipboardCheckTrigger) { _, _ in }
                
                Divider().frame(height: 18)
                
                explorerToolbarButton("Rename", systemImage: "pencil") { renameSelectedItem() }
                    .disabled((activePane == .left ? leftSelection : rightSelection).count != 1)
                explorerToolbarButton("Delete", systemImage: "trash") { deleteSelectedFiles() }
                    .disabled(leftSelection.isEmpty && rightSelection.isEmpty)
                explorerToolbarButton("Compress", systemImage: "archivebox") { compressSelectedFiles() }
                    .disabled(leftSelection.isEmpty && rightSelection.isEmpty)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            GeometryReader { geometry in
                let totalWidth = max(geometry.size.width, 500)
                let clampedSidebarWidth = min(max(quickAccessWidth, 170), totalWidth * 0.45)
                let remainingWidth = max(totalWidth - clampedSidebarWidth - 12, 300)
                let clampedPaneSplit = min(max(paneSplitRatio, 0.2), 0.8)
                let leftPaneWidth = max((remainingWidth - 6) * clampedPaneSplit, 150)
                let rightPaneWidth = max((remainingWidth - 6) - leftPaneWidth, 150)
                
                HStack(spacing: 0) {
                    quickAccessSidebar
                        .frame(width: clampedSidebarWidth)
                    
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(width: 6)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    if sidebarDragStartWidth == nil {
                                        sidebarDragStartWidth = clampedSidebarWidth
                                    }
                                    let base = sidebarDragStartWidth ?? clampedSidebarWidth
                                    let proposed = base + value.translation.width
                                    quickAccessWidth = min(max(proposed, 170), totalWidth * 0.45)
                                }
                                .onEnded { _ in
                                    sidebarDragStartWidth = nil
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                quickAccessWidth = defaultQuickAccessWidth
                            }
                        }
                    
                    VStack(spacing: 0) {
                        FilePaneView(
                            path: $leftPath,
                            selection: $leftSelection,
                            searchText: $leftSearchText,
                            isSearching: $leftIsSearching,
                            title: "Left Pane",
                            isActive: activePane == .left,
                            onTerminalToggle: { showLeftTerminal.toggle() },
                            onRefresh: { refreshTrigger = UUID() },
                            refreshTrigger: refreshTrigger,
                            onBulkCompress: compressSelectedFiles,
                            canNavigateBack: !leftBackHistory.isEmpty,
                            canNavigateForward: !leftForwardHistory.isEmpty,
                            onNavigateBack: { navigateBack(in: .left) },
                            onNavigateForward: { navigateForward(in: .left) },
                            onNavigateUp: { navigateUp(in: .left) },
                            onFocus: {
                                activePane = .left
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .onChange(of: leftSelection) { _, _ in
                            onSelectionChange?(leftSelection)
                        }
                        .onChange(of: leftPath) { oldValue, newValue in
                            recordHistoryIfNeeded(for: .left, oldValue: oldValue, newValue: newValue)
                        }
                        
                        if showLeftTerminal {
                            terminalResizeHandle(
                                height: $leftTerminalHeight,
                                dragStartHeight: $leftTerminalDragStartHeight,
                                maxHeight: geometry.size.height * 0.7,
                                defaultHeight: defaultTerminalHeight
                            )
                            RealTerminalView(currentDirectory: leftPath)
                                .frame(height: leftTerminalHeight)
                                .onTapGesture {
                                    activePane = .left
                                }
                        }
                    }
                    .frame(width: leftPaneWidth)
                    
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(width: 6)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    let usableWidth = max(remainingWidth - 6, 300)
                                    if paneSplitDragStartLeftWidth == nil {
                                        paneSplitDragStartLeftWidth = leftPaneWidth
                                    }
                                    let base = paneSplitDragStartLeftWidth ?? leftPaneWidth
                                    let proposedLeft = base + value.translation.width
                                    let clampedLeft = min(max(proposedLeft, 150), usableWidth - 150)
                                    paneSplitRatio = clampedLeft / usableWidth
                                }
                                .onEnded { _ in
                                    paneSplitDragStartLeftWidth = nil
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                paneSplitRatio = defaultPaneSplitRatio
                            }
                        }
                    
                    VStack(spacing: 0) {
                        FilePaneView(
                            path: $rightPath,
                            selection: $rightSelection,
                            searchText: $rightSearchText,
                            isSearching: $rightIsSearching,
                            title: "Right Pane",
                            isActive: activePane == .right,
                            onTerminalToggle: { showRightTerminal.toggle() },
                            onRefresh: { refreshTrigger = UUID() },
                            refreshTrigger: refreshTrigger,
                            onBulkCompress: compressSelectedFiles,
                            canNavigateBack: !rightBackHistory.isEmpty,
                            canNavigateForward: !rightForwardHistory.isEmpty,
                            onNavigateBack: { navigateBack(in: .right) },
                            onNavigateForward: { navigateForward(in: .right) },
                            onNavigateUp: { navigateUp(in: .right) },
                            onFocus: {
                                activePane = .right
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .onChange(of: rightSelection) { _, _ in
                            onSelectionChange?(rightSelection)
                        }
                        .onChange(of: rightPath) { oldValue, newValue in
                            recordHistoryIfNeeded(for: .right, oldValue: oldValue, newValue: newValue)
                        }
                        
                        if showRightTerminal {
                            terminalResizeHandle(
                                height: $rightTerminalHeight,
                                dragStartHeight: $rightTerminalDragStartHeight,
                                maxHeight: geometry.size.height * 0.7,
                                defaultHeight: defaultTerminalHeight
                            )
                            RealTerminalView(currentDirectory: rightPath)
                                .frame(height: rightTerminalHeight)
                                .onTapGesture {
                                    activePane = .right
                                }
                        }
                    }
                    .frame(width: rightPaneWidth)
                }
            }
        }
        .onKeyPress(.delete) {
            deleteSelectedFiles()
            return .handled
        }
        .onKeyPress(.space) {
            // Only handle space for compression if terminal is not focused
            if !showLeftTerminal && !showRightTerminal {
                compressSelectedFiles()
                return .handled
            }
            return .ignored
        }
        .alert("Delete Files", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                performDelete()
            }
        } message: {
            if filesToDelete.count == 1 {
                Text("Are you sure you want to permanently delete '\(filesToDelete.first?.lastPathComponent ?? "")'? This action cannot be undone.")
            } else {
                Text("Are you sure you want to permanently delete \(filesToDelete.count) files? This action cannot be undone.")
            }
        }
        .onAppear {
            if let restoredLeftPath = SandboxAccessManager.restoreBookmark(for: .left) {
                leftPath = restoredLeftPath
            }
            if let restoredRightPath = SandboxAccessManager.restoreBookmark(for: .right) {
                rightPath = restoredRightPath
            }
        }
    }
    
    @ViewBuilder
    private var quickAccessSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quick Access")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(quickLocations) { location in
                        Button {
                            navigateToLocation(location.url)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: location.icon)
                                    .foregroundColor(.accentColor)
                                Text(location.name)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider().padding(.vertical, 6)
                    
                    if !recentLocations.isEmpty {
                        Text("Recent")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 4)
                        
                        ForEach(recentLocations) { location in
                            Button {
                                navigateToLocation(location.url)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: location.icon)
                                        .foregroundColor(.accentColor)
                                    Text(location.name)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Divider().padding(.vertical, 6)
                    }
                    
                    if !pinnedLocations.isEmpty {
                        Text("Pinned")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 4)
                        
                        ForEach(pinnedLocations) { location in
                            Button {
                                navigateToLocation(location.url)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: location.icon)
                                        .foregroundColor(.accentColor)
                                    Text(location.name)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Divider().padding(.vertical, 6)
                    }
                    
                    if !mountedVolumes.isEmpty {
                        Text("Drives")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 4)
                        
                        ForEach(mountedVolumes) { location in
                            Button {
                                navigateToLocation(location.url)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: location.icon)
                                        .foregroundColor(.accentColor)
                                    Text(location.name)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Divider().padding(.vertical, 6)
                    }
                    
                    Button {
                        pinActiveFolder()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "pin")
                                .foregroundColor(.accentColor)
                            Text("Pin Active Folder")
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        selectFolder(for: activePane)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.accentColor)
                            Text("Choose Folder...")
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
            
            Spacer(minLength: 0)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    @ViewBuilder
    private func explorerToolbarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
    }
    
    @ViewBuilder
    private func terminalResizeHandle(
        height: Binding<CGFloat>,
        dragStartHeight: Binding<CGFloat?>,
        maxHeight: CGFloat,
        defaultHeight: CGFloat
    ) -> some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(height: 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragStartHeight.wrappedValue == nil {
                            dragStartHeight.wrappedValue = height.wrappedValue
                        }
                        let base = dragStartHeight.wrappedValue ?? height.wrappedValue
                        let proposed = base - value.translation.height
                        height.wrappedValue = min(max(proposed, 120), max(120, maxHeight))
                    }
                    .onEnded { _ in
                        dragStartHeight.wrappedValue = nil
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    height.wrappedValue = defaultHeight
                }
            }
    }
    
    private func selectFolder(for pane: ActivePane) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        panel.message = "Choose a folder to grant Folderium access."
        
        if panel.runModal() == .OK, let selectedURL = panel.url {
            let didAccess = selectedURL.startAccessingSecurityScopedResource()
            guard didAccess else {
                print("Failed to access security-scoped resource: \(selectedURL.path)")
                return
            }
            
            switch pane {
            case .left:
                leftPath = selectedURL
                SandboxAccessManager.saveBookmark(for: .left, url: selectedURL)
            case .right:
                rightPath = selectedURL
                SandboxAccessManager.saveBookmark(for: .right, url: selectedURL)
            }
        }
    }
    
    private func recordHistoryIfNeeded(for pane: ActivePane, oldValue: URL, newValue: URL) {
        guard oldValue != newValue else { return }
        
        switch pane {
        case .left:
            if isNavigatingLeftHistory {
                isNavigatingLeftHistory = false
                return
            }
            leftBackHistory.append(oldValue)
            leftForwardHistory.removeAll()
        case .right:
            if isNavigatingRightHistory {
                isNavigatingRightHistory = false
                return
            }
            rightBackHistory.append(oldValue)
            rightForwardHistory.removeAll()
        }
    }
    
    private func navigateToLocation(_ url: URL) {
        switch activePane {
        case .left:
            leftPath = url
        case .right:
            rightPath = url
        }
    }
    
    private func pinActiveFolder() {
        let current = (activePane == .left ? leftPath : rightPath).path
        var entries = Set(pinnedPathsRaw.split(separator: "\n").map(String.init))
        entries.insert(current)
        pinnedPathsRaw = entries.sorted().joined(separator: "\n")
    }
    
    private func navigateBack(in pane: ActivePane) {
        switch pane {
        case .left:
            guard let previous = leftBackHistory.popLast() else { return }
            isNavigatingLeftHistory = true
            leftForwardHistory.append(leftPath)
            leftPath = previous
        case .right:
            guard let previous = rightBackHistory.popLast() else { return }
            isNavigatingRightHistory = true
            rightForwardHistory.append(rightPath)
            rightPath = previous
        }
    }
    
    private func navigateForward(in pane: ActivePane) {
        switch pane {
        case .left:
            guard let next = leftForwardHistory.popLast() else { return }
            isNavigatingLeftHistory = true
            leftBackHistory.append(leftPath)
            leftPath = next
        case .right:
            guard let next = rightForwardHistory.popLast() else { return }
            isNavigatingRightHistory = true
            rightBackHistory.append(rightPath)
            rightPath = next
        }
    }
    
    private func navigateUp(in pane: ActivePane) {
        switch pane {
        case .left:
            let parent = leftPath.deletingLastPathComponent()
            guard parent.path != leftPath.path else { return }
            leftPath = parent
        case .right:
            let parent = rightPath.deletingLastPathComponent()
            guard parent.path != rightPath.path else { return }
            rightPath = parent
        }
    }
    
    private func renameSelectedItem() {
        let selection = activePane == .left ? leftSelection : rightSelection
        guard selection.count == 1, let selectedURL = selection.first else { return }
        
        let currentName = selectedURL.lastPathComponent
        let alert = NSAlert()
        alert.messageText = "Rename Item"
        alert.informativeText = "Enter new name for '\(currentName)':"
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = currentName
        textField.selectText(nil)
        alert.accessoryView = textField
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        
        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != currentName else { return }
        
        let newURL = selectedURL.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: selectedURL, to: newURL)
            refreshTrigger = UUID()
            if activePane == .left {
                leftSelection = [newURL]
            } else {
                rightSelection = [newURL]
            }
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Rename Failed"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.addButton(withTitle: "OK")
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        }
    }
    
    private func copySelectedFiles() {
            let selectedFiles = Array(leftSelection.union(rightSelection))
            print("Copy selected called with \(selectedFiles.count) files")
            
            if !selectedFiles.isEmpty {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                
                // Add file URLs to pasteboard
                let fileURLs = selectedFiles.map { $0 as NSURL }
                let success = pasteboard.writeObjects(fileURLs)
                
                print("Files copied to clipboard: \(selectedFiles.map { $0.lastPathComponent })")
                print("Clipboard write success: \(success)")
                
                // Also add as file paths for compatibility
                let filePaths = selectedFiles.map { $0.path }
                pasteboard.setString(filePaths.joined(separator: "\n"), forType: .string)
                print("Also added file paths to clipboard")
                
                // Mark as copy operation
                isCutOperation = false
                
                // Trigger clipboard state update
                clipboardCheckTrigger = UUID()
            } else {
                print("No files selected for copying")
            }
        }
        
        private func cutSelectedFiles() {
            let selectedFiles = Array(leftSelection.union(rightSelection))
            print("Cut selected called with \(selectedFiles.count) files")
            
            if !selectedFiles.isEmpty {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                
                // Add file URLs to pasteboard
                let fileURLs = selectedFiles.map { $0 as NSURL }
                let success = pasteboard.writeObjects(fileURLs)
                
                // Mark as cut operation using a custom pasteboard type
                pasteboard.setString("cut", forType: NSPasteboard.PasteboardType("public.folderium.cut"))
                
                print("Files cut to clipboard: \(selectedFiles.map { $0.lastPathComponent })")
                print("Clipboard write success: \(success)")
                
                // Also add as file paths for compatibility
                let filePaths = selectedFiles.map { $0.path }
                pasteboard.setString(filePaths.joined(separator: "\n"), forType: .string)
                print("Also added file paths to clipboard")
                
                // Mark as cut operation
                isCutOperation = true
                
                // Trigger clipboard state update
                clipboardCheckTrigger = UUID()
            } else {
                print("No files selected for cutting")
            }
        }
        
        private func pasteFiles() {
            let pasteboard = NSPasteboard.general
            
            print("Paste called - checking clipboard contents")
            
            // Check if there are file URLs in the clipboard
            if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] {
                let urls = fileURLs.compactMap { $0 as URL }
                print("Found \(urls.count) file URLs in clipboard")
                
                if !urls.isEmpty {
                    // Determine target directory (use the active pane)
                    let targetDirectory = activePane == .left ? leftPath : rightPath
                    
                    print("Pasting \(urls.count) files to \(targetDirectory.path)")
                    
                    Task {
                        do {
                            for url in urls {
                                let destinationURL = targetDirectory.appendingPathComponent(url.lastPathComponent)
                                let finalDestinationURL = await resolveConflictDestination(
                                    sourceURL: url,
                                    destinationURL: destinationURL,
                                    in: targetDirectory
                                )
                                guard let finalDestinationURL else { continue }
                                
                                if isCutOperation {
                                    // Move file
                                    try FileManager.default.moveItem(at: url, to: finalDestinationURL)
                                    print("Moved: \(url.lastPathComponent) to \(finalDestinationURL.lastPathComponent)")
                                } else {
                                    // Copy file
                                    try FileManager.default.copyItem(at: url, to: finalDestinationURL)
                                    print("Copied: \(url.lastPathComponent) to \(finalDestinationURL.lastPathComponent)")
                                }
                            }
                            
                            await MainActor.run {
                                // Refresh both panes
                                refreshTrigger = UUID()
                                
                                // Reset cut operation after paste
                                isCutOperation = false
                            }
                            
                            print("Paste operation completed successfully")
                        } catch {
                            print("Error pasting files: \(error)")
                        }
                    }
                } else {
                    print("No files found in clipboard")
                }
            } else {
                print("No file URLs found in clipboard")
                
                // Try to read as file paths as fallback
                if let filePaths = pasteboard.string(forType: .string) {
                    print("Found file paths in clipboard: \(filePaths)")
                    // This is a fallback - we could implement file path parsing here
                }
            }
        }
        
        private func hasFilesInClipboard() -> Bool {
            let pasteboard = NSPasteboard.general
            
            // Check if there are file URLs in the clipboard
            if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] {
                let hasFiles = !fileURLs.isEmpty
                print("hasFilesInClipboard: \(hasFiles) (\(fileURLs.count) files)")
                return hasFiles
            }
            
            // Also check for file paths as fallback
            if let filePaths = pasteboard.string(forType: .string), !filePaths.isEmpty {
                print("hasFilesInClipboard: found file paths in clipboard")
                return true
            }
            
            print("hasFilesInClipboard: no files found")
            return false
        }
        
        private func getUniqueDestinationURL(for url: URL, in directory: URL) -> URL {
            let fileManager = FileManager.default
            var destinationURL = url
            
            // If file doesn't exist, return original URL
            if !fileManager.fileExists(atPath: destinationURL.path) {
                return destinationURL
            }
            
            // File exists, create a unique name
            let filename = url.deletingPathExtension().lastPathComponent
            let fileExtension = url.pathExtension
            var counter = 1
            
            repeat {
                let newFilename: String
                if fileExtension.isEmpty {
                    newFilename = "\(filename) (\(counter))"
                } else {
                    newFilename = "\(filename) (\(counter)).\(fileExtension)"
                }
                destinationURL = directory.appendingPathComponent(newFilename)
                counter += 1
            } while fileManager.fileExists(atPath: destinationURL.path)
            
            print("File conflict resolved: \(url.lastPathComponent) -> \(destinationURL.lastPathComponent)")
            return destinationURL
        }
        
        private enum ConflictChoice {
            case replace
            case skip
            case keepBoth
        }
        
        private func resolveConflictDestination(sourceURL: URL, destinationURL: URL, in directory: URL) async -> URL? {
            guard FileManager.default.fileExists(atPath: destinationURL.path) else {
                return destinationURL
            }
            
            let choice = await askConflictChoice(sourceURL: sourceURL, destinationURL: destinationURL)
            switch choice {
            case .skip:
                return nil
            case .keepBoth:
                return getUniqueDestinationURL(for: destinationURL, in: directory)
            case .replace:
                do {
                    try FileManager.default.removeItem(at: destinationURL)
                    return destinationURL
                } catch {
                    print("Failed to replace destination \(destinationURL.path): \(error)")
                    return nil
                }
            }
        }
        
        @MainActor
        private func askConflictChoice(sourceURL: URL, destinationURL: URL) -> ConflictChoice {
            let alert = NSAlert()
            alert.messageText = "File Conflict"
            alert.informativeText = "'\(destinationURL.lastPathComponent)' already exists.\nChoose how to continue."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Keep Both")
            alert.addButton(withTitle: "Skip")
            alert.alertStyle = .warning
            
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                return .replace
            case .alertSecondButtonReturn:
                return .keepBoth
            default:
                return .skip
            }
        }
        
        
        
        private func compressSelectedFiles() {
            let selectedFiles = Array(leftSelection.union(rightSelection))
            print("Bulk compress called with \(selectedFiles.count) files")
            print("Left selection: \(leftSelection.count) files")
            print("Right selection: \(rightSelection.count) files")
            
            if !selectedFiles.isEmpty {
                Task {
                    do {
                        // Create a unique archive name based on the first file
                        let firstFile = selectedFiles.first!
                        let parentDirectory = firstFile.deletingLastPathComponent()
                        let archiveName = "Compressed_\(Date().timeIntervalSince1970).zip"
                        let archiveURL = parentDirectory.appendingPathComponent(archiveName)
                        
                        print("Compressing \(selectedFiles.count) files to \(archiveURL.path)")
                        for (index, file) in selectedFiles.enumerated() {
                            print("  File \(index + 1): \(file.lastPathComponent)")
                        }
                        
                        try await ArchiveManager.shared.compressFiles(selectedFiles, to: archiveURL, format: .zip)
                        
                        print("Bulk compression completed successfully")
                        
                        await MainActor.run {
                            // Refresh both panes
                            refreshTrigger = UUID()
                        }
                    } catch {
                        print("Error compressing files: \(error)")
                    }
                }
            } else {
                print("No files selected for compression")
            }
        }
    
    private func deleteSelectedFiles() {
        filesToDelete = Array(leftSelection.union(rightSelection))
        if !filesToDelete.isEmpty {
            showDeleteConfirmation = true
        }
    }
    
    private func performDelete() {
        for fileURL in filesToDelete {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                print("Error deleting file \(fileURL.lastPathComponent): \(error)")
            }
        }
        
        // Clear selections and refresh both panes
        leftSelection.removeAll()
        rightSelection.removeAll()
        onSelectionChange?(Set<URL>())
        
        // Trigger refresh of both panes
        refreshTrigger = UUID()
    }
}

struct FilePaneView: View {
    @Binding var path: URL
    @Binding var selection: Set<URL>
    @Binding var searchText: String
    @Binding var isSearching: Bool
    let title: String
    let isActive: Bool
    let onTerminalToggle: () -> Void
    let onRefresh: () -> Void
    let refreshTrigger: UUID
    let onBulkCompress: () -> Void
    let canNavigateBack: Bool
    let canNavigateForward: Bool
    let onNavigateBack: () -> Void
    let onNavigateForward: () -> Void
    let onNavigateUp: () -> Void
    let onFocus: () -> Void
    
    @State private var files: [FileItem] = []
    @State private var displayedFiles: [FileItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var sortOrder: SortOrder = .name
    @State private var sortDirection: SortDirection = .ascending
    @State private var pathInput: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    
    enum SortOrder: CaseIterable {
        case name, type, size, modified
        
        var displayName: String {
            switch self {
            case .name: return "Name"
            case .type: return "Type"
            case .size: return "Size"
            case .modified: return "Modified"
            }
        }
    }
    
    enum SortDirection {
        case ascending, descending
    }
    
        private func compareFiles(first: FileItem, second: FileItem) -> Bool {
            let comparison = getComparisonResult(first: first, second: second)
            return sortDirection == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        
        private func getComparisonResult(first: FileItem, second: FileItem) -> ComparisonResult {
            switch sortOrder {
            case .name:
                return first.name.localizedCaseInsensitiveCompare(second.name)
            case .type:
                return first.localizedType.localizedCaseInsensitiveCompare(second.localizedType)
            case .size:
                if first.size < second.size {
                    return .orderedAscending
                } else if first.size > second.size {
                    return .orderedDescending
                } else {
                    return .orderedSame
                }
            case .modified:
                let firstDate = first.modificationDate ?? Date.distantPast
                let secondDate = second.modificationDate ?? Date.distantPast
                return firstDate.compare(secondDate)
            }
        }
    
    var body: some View {
        VStack(spacing: 0) {
            searchBarView
            pathBarView
            fileListView
        }
        .overlay(
            // Blue border for focused pane
            RoundedRectangle(cornerRadius: 0)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .onAppear {
            pathInput = path.path
            loadFiles()
        }
        .onChange(of: path) { _, _ in
            // Clear selection when path changes
            selection = []
            pathInput = path.path
            loadFiles()
        }
        .onChange(of: searchText) { _, _ in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    applyFiltersAndSorting()
                }
            }
        }
        .onChange(of: refreshTrigger) { _, _ in
            loadFiles()
        }
        .onChange(of: sortOrder) { _, _ in
            applyFiltersAndSorting()
        }
        .onChange(of: sortDirection) { _, _ in
            applyFiltersAndSorting()
        }
        .onKeyPress(.downArrow) {
            moveSelectionByArrow(delta: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelectionByArrow(delta: -1)
            return .handled
        }
    }
    
    @ViewBuilder
    private var searchBarView: some View {
        HStack {
            searchFieldView
            Spacer()
            terminalButtonView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .onTapGesture {
            onFocus()
        }
    }
    
    @ViewBuilder
    private var searchFieldView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search in \(title.lowercased())...", text: $searchText, onEditingChanged: { isEditing in
                if isEditing {
                    onFocus()
                }
            })
                .textFieldStyle(.plain)
                .onSubmit {
                    performSearch()
                }
                .onChange(of: searchText) { _, _ in
                    onFocus()
                }
            
            if !searchText.isEmpty {
                Button("Clear") {
                    searchText = ""
                    isSearching = false
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .onTapGesture {
            onFocus()
        }
    }
    
    @ViewBuilder
    private var terminalButtonView: some View {
        Button("Terminal") {
            onTerminalToggle()
        }
        .buttonStyle(.bordered)
        .onTapGesture {
            onFocus()
        }
    }
    
    @ViewBuilder
    private var pathBarView: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    onNavigateBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(!canNavigateBack)
                
                Button {
                    onNavigateForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(!canNavigateForward)
                
                Button {
                    onNavigateUp()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.bordered)
                
                TextField("Enter path", text: $pathInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        commitPathInput()
                    }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                        Button(component) {
                            navigateToPath(at: index)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                        
                        if index < pathComponents.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .onTapGesture {
            onFocus()
        }
        
        Divider()
    }
    
    @ViewBuilder
    private var fileListView: some View {
        if isLoading {
            loadingView
        } else if let errorMessage = errorMessage {
            errorView(errorMessage)
        } else {
            fileTable
        }
    }
    
    @ViewBuilder
    private var loadingView: some View {
        VStack {
            ProgressView()
            Text("Loading...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            Text("Error")
                .font(.headline)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var fileTable: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider()
            tableContent
            statusBar
        }
    }
    
    @ViewBuilder
    private var tableHeader: some View {
        HStack {
            nameHeaderButton
            Spacer()
            typeHeaderButton
            sizeHeaderButton
            modifiedHeaderButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    @ViewBuilder
    private var typeHeaderButton: some View {
        Button(action: { sortBy(.type) }) {
            HStack {
                Text("Type")
                    .font(.caption)
                    .fontWeight(.medium)
                if sortOrder == .type {
                    Image(systemName: sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.borderless)
        .foregroundColor(.primary)
        .frame(width: 130, alignment: .leading)
        .onTapGesture {
            onFocus()
        }
    }
    
    @ViewBuilder
    private var nameHeaderButton: some View {
        Button(action: { sortBy(.name) }) {
            HStack {
                Text("Name")
                    .font(.caption)
                    .fontWeight(.medium)
                if sortOrder == .name {
                    Image(systemName: sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.borderless)
        .foregroundColor(.primary)
        .onTapGesture {
            print("Name header focus triggered")
            onFocus()
        }
    }
    
    @ViewBuilder
    private var sizeHeaderButton: some View {
        Button(action: { sortBy(.size) }) {
            HStack {
                Text("Size")
                    .font(.caption)
                    .fontWeight(.medium)
                if sortOrder == .size {
                    Image(systemName: sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.borderless)
        .foregroundColor(.primary)
        .frame(width: 80, alignment: .leading)
        .onTapGesture {
            print("Size header focus triggered")
            onFocus()
        }
    }
    
    @ViewBuilder
    private var modifiedHeaderButton: some View {
        Button(action: { sortBy(.modified) }) {
            HStack {
                Text("Modified")
                    .font(.caption)
                    .fontWeight(.medium)
                if sortOrder == .modified {
                    Image(systemName: sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.borderless)
        .foregroundColor(.primary)
        .frame(width: 120, alignment: .leading)
        .onTapGesture {
            print("Modified header focus triggered")
            onFocus()
        }
    }
    
    @ViewBuilder
    private var tableContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(displayedFiles.enumerated()), id: \.element.url) { index, file in
                    FileRowView(
                        file: file,
                        isSelected: selection.contains(file.url),
                        currentSelection: selection,
                        isStriped: index % 2 == 1,
                        onSelectWithModifiers: { isCommand, isShift in
                            toggleSelectionWithModifier(file.url, isCommandPressed: isCommand, isShiftPressed: isShift)
                        },
                        onDoubleClick: { handleDoubleClick(file) },
                        onFileOperation: { 
                            loadFiles()
                            onRefresh()
                        },
                        onBulkCompress: onBulkCompress,
                        onFocus: onFocus
                    )
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .modifier(DraggableModifier(selection: selection, dragPreview: createDragPreview))
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus()
        }
        .contextMenu {
            EmptyAreaContextMenu(
                currentPath: path,
                onFileOperation: { 
                    loadFiles()
                    onRefresh()
                }
            )
        }
    }
    
    @ViewBuilder
    private var statusBar: some View {
        StatusBarView(files: displayedFiles)
    }
    
    private var pathComponents: [String] {
        var components: [String] = []
        var currentPath = path
        
        while currentPath.path != "/" {
            components.insert(currentPath.lastPathComponent, at: 0)
            currentPath = currentPath.deletingLastPathComponent()
        }
        components.insert("/", at: 0)
        
        return components
    }
    
    private func navigateToPath(at index: Int) {
        guard index >= 0 && index < pathComponents.count else { return }
        
        if index == 0 {
            // Root directory
            path = URL(fileURLWithPath: "/")
        } else {
            // Build path up to the selected index from root
            var newPath = URL(fileURLWithPath: "/")
            for i in 1...index {
                newPath = newPath.appendingPathComponent(pathComponents[i])
            }
            path = newPath
        }
    }
    
    private func sortBy(_ order: SortOrder) {
        if sortOrder == order {
            sortDirection = sortDirection == .ascending ? .descending : .ascending
        } else {
            sortOrder = order
            sortDirection = .ascending
        }
    }
    
    private func toggleSelectionWithModifier(_ url: URL, isCommandPressed: Bool, isShiftPressed: Bool) {
        if isCommandPressed {
            // Command+click - toggle item in selection
            if selection.contains(url) {
                selection.remove(url)
            } else {
                selection.insert(url)
            }
        } else if isShiftPressed {
            // Shift+click - select range
            selectRange(to: url)
        } else {
            // Single click - clear and select only this item
            selection = [url]
        }
    }
    
    private func selectRange(to url: URL) {
        guard let firstSelected = selection.first else {
            selection = [url]
            return
        }
        
        // Get all files in current directory
        let allFiles = files.map { $0.url }
        guard let firstIndex = allFiles.firstIndex(of: firstSelected),
              let lastIndex = allFiles.firstIndex(of: url) else {
            selection = [url]
            return
        }
        
        // Select range from first to last
        let startIndex = min(firstIndex, lastIndex)
        let endIndex = max(firstIndex, lastIndex)
        let range = allFiles[startIndex...endIndex]
        selection = Set(range)
    }
    
    private func handleDoubleClick(_ file: FileItem) {
        print("Double-clicked on: \(file.name), isDirectory: \(file.isDirectory), URL: \(file.url)")
        
        if file.isDirectory {
            // Special handling for OneDrive and other cloud storage folders
            if file.name.lowercased().contains("onedrive") || 
               file.name.lowercased().contains("dropbox") || 
               file.name.lowercased().contains("google drive") ||
               file.name.lowercased().contains("icloud") {
                
                // Try to resolve symbolic links for cloud storage folders
                let fileManager = FileManager.default
                do {
                    let resolvedURL = try fileManager.destinationOfSymbolicLink(atPath: file.url.path)
                    let targetURL = URL(fileURLWithPath: resolvedURL)
                    
                    // Check if the resolved target is actually a directory
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDir) && isDir.boolValue {
                        print("Cloud storage folder resolved to: \(targetURL)")
                        selection = []
                        path = targetURL
                    } else {
                        print("Cloud storage folder resolved but target is not a directory, opening in Finder")
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    }
                } catch {
                    print("Could not resolve symbolic link for cloud storage folder: \(error)")
                    print("Opening in Finder instead")
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                }
            } else {
                // Clear selection when navigating to folder
                selection = []
                path = file.url
                print("Navigating to directory: \(file.url)")
            }
        } else {
            // Open file with default application
            print("Opening file with default application: \(file.url)")
            NSWorkspace.shared.open(file.url)
        }
    }
    
    private func loadFiles() {
        isLoading = true
        errorMessage = nil
        
        print("Loading files from: \(path)")
        
        Task {
            do {
                let fileManager = FileManager.default
                
                // Check if the path is accessible before trying to list contents
                var isDir: ObjCBool = false
                if !fileManager.fileExists(atPath: path.path, isDirectory: &isDir) {
                    throw NSError(domain: "FolderiumError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Path does not exist: \(path.path)"])
                }
                
                if !isDir.boolValue {
                    throw NSError(domain: "FolderiumError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Path is not a directory: \(path.path)"])
                }
                
                // Check if we have permission to read the directory
                if !fileManager.isReadableFile(atPath: path.path) {
                    throw NSError(domain: "FolderiumError", code: 3, userInfo: [NSLocalizedDescriptionKey: "No permission to read directory: \(path.path)"])
                }
                
                let contents = try fileManager.contentsOfDirectory(
                    at: path,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey],
                    options: [.skipsHiddenFiles]
                )
                
                let fileItems = contents.map { url in
                    FileItem(url: url)
                }.sorted { first, second in
                    if first.isDirectory && !second.isDirectory {
                        return true
                    } else if !first.isDirectory && second.isDirectory {
                        return false
                    } else {
                        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                    }
                }
                
                await MainActor.run {
                    self.files = fileItems
                    self.applyFiltersAndSorting()
                    self.isLoading = false
                    // Clear selection of files that no longer exist
                    self.selection = self.selection.filter { url in
                        fileItems.contains { $0.url == url }
                    }
                }
            } catch {
                print("Error loading files from \(path): \(error)")
                print("Error details: \(error.localizedDescription)")
                
                await MainActor.run {
                    self.errorMessage = "Cannot access folder: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func performSearch() {
        applyFiltersAndSorting()
    }
    
    private func applyFiltersAndSorting() {
        var result = files
        let searchTerm = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !searchTerm.isEmpty {
            result = result.filter { file in
                matchesSearch(file: file, query: searchTerm)
            }
        }
        
        result.sort { first, second in
            compareFiles(first: first, second: second)
        }
        
        displayedFiles = result
    }
    
    private func moveSelectionByArrow(delta: Int) {
        guard !displayedFiles.isEmpty else { return }
        
        let orderedURLs = displayedFiles.map(\.url)
        
        if let current = selection.first, let currentIndex = orderedURLs.firstIndex(of: current) {
            let nextIndex = min(max(currentIndex + delta, 0), orderedURLs.count - 1)
            selection = [orderedURLs[nextIndex]]
        } else {
            let initialIndex = delta > 0 ? 0 : orderedURLs.count - 1
            selection = [orderedURLs[initialIndex]]
        }
        
        onFocus()
    }
    
    private func matchesSearch(file: FileItem, query: String) -> Bool {
        let parts = query.split(separator: " ").map(String.init)
        var nameTerms: [String] = []
        var extFilter: String?
        var typeFilter: String?
        var minSize: Int64?
        var maxSize: Int64?
        
        for part in parts {
            let lowered = part.lowercased()
            if lowered.hasPrefix("ext:") {
                extFilter = String(lowered.dropFirst(4))
            } else if lowered.hasPrefix("type:") {
                typeFilter = String(lowered.dropFirst(5))
            } else if lowered.hasPrefix("size>") {
                if let value = Int64(lowered.dropFirst(5)) { minSize = value * 1024 }
            } else if lowered.hasPrefix("size<") {
                if let value = Int64(lowered.dropFirst(5)) { maxSize = value * 1024 }
            } else {
                nameTerms.append(part)
            }
        }
        
        if let extFilter, !file.fileExtension.lowercased().contains(extFilter) {
            return false
        }
        
        if let typeFilter, !file.localizedType.lowercased().contains(typeFilter) {
            return false
        }
        
        if let minSize, file.size < minSize {
            return false
        }
        
        if let maxSize, file.size > maxSize {
            return false
        }
        
        if nameTerms.isEmpty {
            return true
        }
        
        return nameTerms.allSatisfy { term in
            file.name.localizedCaseInsensitiveContains(term)
        }
    }
    
    private func commitPathInput() {
        let trimmedPath = pathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            pathInput = path.path
            return
        }
        
        let expandedPath = (trimmedPath as NSString).expandingTildeInPath
        let resolvedURL: URL
        
        if expandedPath.hasPrefix("/") {
            resolvedURL = URL(fileURLWithPath: expandedPath)
        } else {
            resolvedURL = path.appendingPathComponent(expandedPath)
        }
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            errorMessage = "Path is not a readable folder: \(resolvedURL.path)"
            return
        }
        
        path = resolvedURL
        errorMessage = nil
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        print("Drop received with \(providers.count) providers")
        
        Task {
            var sourceURLs: [URL] = []
            
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                    do {
                        if let data = try await provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) as? Data,
                           let url = URL(dataRepresentation: data, relativeTo: nil) {
                            sourceURLs.append(url)
                            print("Found file URL: \(url.lastPathComponent)")
                        }
                    } catch {
                        print("Error loading file URL: \(error)")
                    }
                }
            }
            
            if !sourceURLs.isEmpty {
                await MainActor.run {
                    // Determine if this is a move or copy operation
                    let isMoveOperation = NSEvent.modifierFlags.contains(.option) // Option key = move
                    print("Drop operation: \(isMoveOperation ? "Move" : "Copy")")
                    
                    // Perform the operation
                    performDropOperation(sourceURLs: sourceURLs, isMove: isMoveOperation)
                }
            }
        }
        
        return true
    }
    
    private func performDropOperation(sourceURLs: [URL], isMove: Bool) {
        print("Performing \(isMove ? "move" : "copy") operation with \(sourceURLs.count) files to \(path.path)")
        
        Task {
            do {
                for sourceURL in sourceURLs {
                    let destinationURL = path.appendingPathComponent(sourceURL.lastPathComponent)
                    guard let finalDestinationURL = await resolveDropConflict(sourceURL: sourceURL, destinationURL: destinationURL) else {
                        continue
                    }
                    
                    if isMove {
                        try FileManager.default.moveItem(at: sourceURL, to: finalDestinationURL)
                        print("Moved: \(sourceURL.lastPathComponent) to \(finalDestinationURL.lastPathComponent)")
                    } else {
                        try FileManager.default.copyItem(at: sourceURL, to: finalDestinationURL)
                        print("Copied: \(sourceURL.lastPathComponent) to \(finalDestinationURL.lastPathComponent)")
                    }
                }
                
                await MainActor.run {
                    // Refresh the file list
                    loadFiles()
                    onRefresh()
                }
                
                print("Drop operation completed successfully")
            } catch {
                print("Error during drop operation: \(error)")
            }
        }
    }
    
    private func getUniqueDestinationURL(for url: URL) -> URL {
        let fileManager = FileManager.default
        var destinationURL = url
        
        // If file doesn't exist, return original URL
        if !fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }
        
        // File exists, create a unique name
        let directory = url.deletingLastPathComponent()
        let filename = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension
        var counter = 1
        
        repeat {
            let newFilename: String
            if fileExtension.isEmpty {
                newFilename = "\(filename) (\(counter))"
            } else {
                newFilename = "\(filename) (\(counter)).\(fileExtension)"
            }
            destinationURL = directory.appendingPathComponent(newFilename)
            counter += 1
        } while fileManager.fileExists(atPath: destinationURL.path)
        
        print("File conflict resolved: \(url.lastPathComponent) -> \(destinationURL.lastPathComponent)")
        return destinationURL
    }
    
    private enum DropConflictChoice {
        case replace
        case skip
        case keepBoth
    }
    
    private func resolveDropConflict(sourceURL: URL, destinationURL: URL) async -> URL? {
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            return destinationURL
        }
        
        let choice = await askDropConflictChoice(sourceURL: sourceURL, destinationURL: destinationURL)
        switch choice {
        case .skip:
            return nil
        case .keepBoth:
            return getUniqueDestinationURL(for: destinationURL)
        case .replace:
            do {
                try FileManager.default.removeItem(at: destinationURL)
                return destinationURL
            } catch {
                print("Failed to replace dropped file destination: \(error)")
                return nil
            }
        }
    }
    
    @MainActor
    private func askDropConflictChoice(sourceURL: URL, destinationURL: URL) -> DropConflictChoice {
        let alert = NSAlert()
        alert.messageText = "File Conflict"
        alert.informativeText = "'\(destinationURL.lastPathComponent)' already exists.\nChoose how to continue."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Skip")
        alert.alertStyle = .warning
        
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .replace
        case .alertSecondButtonReturn:
            return .keepBoth
        default:
            return .skip
        }
    }
    
    private func createDragPreview() -> AnyView {
        if selection.count == 1 {
            guard let selectedURL = selection.first,
                  let file = files.first(where: { $0.url == selectedURL }) else {
                // Fallback if file is not found in current files list
                return AnyView(
                    HStack {
                        Image(systemName: "doc")
                            .foregroundColor(.secondary)
                        Text("File")
                            .font(.system(.body, design: .default))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                    .shadow(radius: 2)
                )
            }
            
            return AnyView(
                HStack {
                    Image(systemName: file.iconName)
                        .foregroundColor(file.iconColor)
                        .symbolRenderingMode(.hierarchical)
                    Text(file.name)
                        .font(.system(.body, design: .default))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .shadow(radius: 2)
            )
        } else {
            return AnyView(
                HStack {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                    Text("\(selection.count) items")
                        .font(.system(.body, design: .default))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .shadow(radius: 2)
            )
        }
    }
}

struct FileRowView: View {
    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    let file: FileItem
    let isSelected: Bool
    let currentSelection: Set<URL>
    let isStriped: Bool
    let onSelectWithModifiers: (Bool, Bool) -> Void
    let onDoubleClick: () -> Void
    let onFileOperation: () -> Void
    let onBulkCompress: () -> Void
    let onFocus: () -> Void
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.3)
        } else if isStriped {
            return Color(NSColor.controlBackgroundColor).opacity(0.5)
        } else {
            return Color.clear
        }
    }
    
    var body: some View {
        HStack {
            // Name column
            HStack {
                Image(systemName: file.iconName)
                    .foregroundColor(file.iconColor)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 16)
                
                Text(file.name)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Type column
            Text(file.localizedType)
                .font(.system(.body, design: .default))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
            
            // Size column
            Text(file.isDirectory ? "--" : file.sizeString)
                .font(.system(.body, design: .default))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            // Modified column
            Text(formatDate(file.modificationDate))
                .font(.system(.body, design: .default))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    onDoubleClick()
                }
        )
        .onTapGesture(count: 1) {
            // This handles both left and right clicks
            let isCommandPressed = NSEvent.modifierFlags.contains(.command)
            let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
            onSelectWithModifiers(isCommandPressed, isShiftPressed)
            onFocus()
        }
        .contextMenu {
            FileContextMenu(
                file: file, 
                currentSelection: currentSelection,
                onFileOperation: onFileOperation, 
                onSelect: {
                    onSelectWithModifiers(false, false)
                },
                onBulkCompress: onBulkCompress
            )
        }
        .draggable(file.url) {
            // Visual representation during drag
            HStack {
                Image(systemName: file.iconName)
                    .foregroundColor(file.iconColor)
                    .symbolRenderingMode(.hierarchical)
                Text(file.name)
                    .font(.system(.body, design: .default))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
            .shadow(radius: 2)
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "--" }
        return Self.rowDateFormatter.string(from: date)
    }
}

// MARK: - Sandbox Access

enum PaneBookmarkKey: String {
    case left, right
}

enum SandboxAccessManager {
    private static let leftBookmarkKey = "folderium.bookmark.left"
    private static let rightBookmarkKey = "folderium.bookmark.right"
    static let defaultDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory())
    
    static func saveBookmark(for pane: PaneBookmarkKey, url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey(for: pane))
        } catch {
            print("Failed to save bookmark for \(pane.rawValue): \(error)")
        }
    }
    
    static func restoreBookmark(for pane: PaneBookmarkKey) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey(for: pane)) else {
            return nil
        }
        
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                saveBookmark(for: pane, url: url)
            }
            
            guard url.startAccessingSecurityScopedResource() else {
                print("Failed to access restored bookmark for \(pane.rawValue)")
                return nil
            }
            
            return url
        } catch {
            print("Failed to restore bookmark for \(pane.rawValue): \(error)")
            return nil
        }
    }
    
    private static func bookmarkKey(for pane: PaneBookmarkKey) -> String {
        switch pane {
        case .left:
            return leftBookmarkKey
        case .right:
            return rightBookmarkKey
        }
    }
}

// MARK: - Data Models

class FileTab: ObservableObject, Identifiable, Equatable {
    let id = UUID()
    @Published var name: String
    @Published var leftPath: URL
    @Published var rightPath: URL
    
    init(
        name: String = "New Tab",
        leftPath: URL = SandboxAccessManager.defaultDirectory,
        rightPath: URL = SandboxAccessManager.defaultDirectory
    ) {
        self.name = name
        self.leftPath = leftPath
        self.rightPath = rightPath
    }
    
    static func == (lhs: FileTab, rhs: FileTab) -> Bool {
        return lhs.id == rhs.id
    }
}

class TabManager: ObservableObject {
    @Published var tabs: [FileTab] = []
    
    init() {
        // Add initial tab
        addTab()
    }
    
    func addTab() {
        let tab = FileTab()
        tabs.append(tab)
    }
    
    func closeTab(_ id: UUID) {
        tabs.removeAll { $0.id == id }
    }
}

struct FileItem {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let size: Int64
    let sizeString: String
    let modificationDate: Date?
    let fileExtension: String
    let localizedType: String
    
    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        self.fileExtension = url.pathExtension.lowercased()
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .localizedTypeDescriptionKey])
            var detectedIsDirectory = resourceValues.isDirectory ?? false
            let isSymbolicLink = resourceValues.isSymbolicLink ?? false
            
            // Special handling for OneDrive and other cloud storage folders
            // These are often symbolic links or special folders that don't report as directories
            if name.lowercased().contains("onedrive") || 
               name.lowercased().contains("dropbox") || 
               name.lowercased().contains("google drive") ||
               name.lowercased().contains("icloud") {
                
                // Force cloud storage folders to be treated as directories for display purposes
                // but they will be handled specially in double-click
                detectedIsDirectory = true
                print("Cloud storage folder detected: \(name), treating as directory for display")
            }
            
            self.isDirectory = detectedIsDirectory
            self.isSymbolicLink = isSymbolicLink
            self.size = Int64(resourceValues.fileSize ?? 0)
            self.modificationDate = resourceValues.contentModificationDate
            self.localizedType = resourceValues.localizedTypeDescription ?? Self.defaultTypeName(for: fileExtension, isDirectory: detectedIsDirectory)
        } catch {
            print("Error getting resource values for \(url): \(error)")
            self.isDirectory = false
            self.isSymbolicLink = false
            self.size = 0
            self.modificationDate = nil
            self.localizedType = Self.defaultTypeName(for: fileExtension, isDirectory: false)
        }
        
        if isDirectory {
            self.sizeString = ""
        } else {
            self.sizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }
    
    private static func defaultTypeName(for fileExtension: String, isDirectory: Bool) -> String {
        if isDirectory { return "Folder" }
        if fileExtension.isEmpty { return "File" }
        return fileExtension.uppercased() + " File"
    }
    
    var iconName: String {
        if isDirectory {
            return isSymbolicLink ? "folder.badge.plus" : "folder.fill"
        }
        
        switch fileExtension {
        // Images
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif":
            return "photo"
        case "svg":
            return "photo.artframe"
        
        // Documents
        case "pdf":
            return "doc.richtext"
        case "doc", "docx":
            return "doc.text"
        case "xls", "xlsx":
            return "tablecells"
        case "ppt", "pptx":
            return "rectangle.stack"
        case "txt", "rtf":
            return "doc.plaintext"
        case "md", "markdown":
            return "doc.text"
        
        // Code files
        case "swift":
            return "swift"
        case "py":
            return "p.circle"
        case "js", "jsx":
            return "j.circle"
        case "ts", "tsx":
            return "t.circle"
        case "html", "htm":
            return "globe"
        case "css":
            return "paintbrush"
        case "json":
            return "curlybraces"
        case "xml":
            return "doc.plaintext"
        case "yaml", "yml":
            return "y.circle"
        case "sh", "bash":
            return "terminal"
        case "c", "cpp", "h", "hpp":
            return "c.circle"
        case "java":
            return "j.circle"
        case "php":
            return "p.circle"
        case "rb":
            return "r.circle"
        case "go":
            return "g.circle"
        case "rs":
            return "r.circle"
        
        // Archives
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
            return "archivebox"
        
        // Audio
        case "mp3", "wav", "aac", "flac", "m4a", "ogg":
            return "music.note"
        
        // Video
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm":
            return "video"
        
        // System files
        case "dmg", "pkg", "app":
            return "app"
        case "exe", "msi":
            return "exclamationmark.triangle"
        
        // Default
        default:
            return "doc"
        }
    }
    
    var iconColor: Color {
        if isDirectory {
            return .blue
        }
        
        switch fileExtension {
        // Images
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif", "svg":
            return .green
        
        // Documents
        case "pdf":
            return .red
        case "doc", "docx", "txt", "rtf", "md", "markdown":
            return .blue
        case "xls", "xlsx":
            return .green
        case "ppt", "pptx":
            return .orange
        
        // Code files
        case "swift", "py", "js", "jsx", "ts", "tsx", "html", "htm", "css", "json", "xml", "yaml", "yml", "sh", "bash", "c", "cpp", "h", "hpp", "java", "php", "rb", "go", "rs":
            return .purple
        
        // Archives
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
            return .brown
        
        // Audio
        case "mp3", "wav", "aac", "flac", "m4a", "ogg":
            return .pink
        
        // Video
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm":
            return .purple
        
        // System files
        case "dmg", "pkg", "app":
            return .blue
        case "exe", "msi":
            return .red
        
        // Default
        default:
            return .secondary
        }
    }
}

struct FileContextMenu: View {
    let file: FileItem
    let currentSelection: Set<URL>
    let onFileOperation: () -> Void
    let onSelect: () -> Void
    let onBulkCompress: () -> Void
    
    enum ActionType {
        case delete, moveToTrash
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Open") {
                onSelect()
                openFile()
            }
            
            Button("Open in New Window") {
                openInNewWindow()
            }
            
            Divider()
            
            Button("Cut") {
                cutToClipboard()
            }
            
            Button("Copy") {
                copyToClipboard()
            }
            
            Button("Copy path") {
                copyPaths()
            }
            
            Divider()
            
            Button(currentSelection.count > 1 ? "Compress Selected (\(currentSelection.count))" : "Compress") {
                if currentSelection.count > 1 {
                    onBulkCompress()
                } else {
                    compressFile()
                }
            }
            
            if ArchiveManager.shared.isArchive(file.url) {
                Button("Extract") {
                    extractFile()
                }
            }
            
            Button("Reveal in Finder") {
                revealInFinder()
            }
            
            Divider()
            
            Button("Rename") {
                renameFile()
            }
            
            Button("Delete") {
                onSelect()
                showNSAlert(for: .moveToTrash)
            }
            
            Button("Delete Permanently") {
                onSelect()
                showNSAlert(for: .delete)
            }
            
            Divider()
            
            Button("Properties") {
                getInfo()
            }
        }
    }
    
    private func showNSAlert(for actionType: ActionType) {
        // Get the current file name from the URL to avoid issues with stale FileItem
        let currentFileName = file.url.lastPathComponent
        
        let alert = NSAlert()
        
        switch actionType {
        case .delete:
            alert.messageText = "Delete Permanently"
            alert.informativeText = "Are you sure you want to permanently delete '\(currentFileName)'? This action cannot be undone."
            alert.addButton(withTitle: "Delete")
        case .moveToTrash:
            alert.messageText = "Move to Trash"
            alert.informativeText = "Are you sure you want to move '\(currentFileName)' to Trash?"
            alert.addButton(withTitle: "Move to Trash")
        }
        
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            performAction(for: actionType)
        }
    }
    
    private func performAction(for actionType: ActionType) {
        switch actionType {
        case .delete:
            deleteFile()
        case .moveToTrash:
            moveToTrash()
        }
    }
    
    private func openFile() {
        NSWorkspace.shared.open(file.url)
    }
    
    private func openInNewWindow() {
        NSWorkspace.shared.open(file.url)
    }
    
    private func compressFile() {
        Task {
            do {
                let parentDirectory = file.url.deletingLastPathComponent()
                let archiveName = file.name + ".zip"
                let archiveURL = parentDirectory.appendingPathComponent(archiveName)
                
                print("Individual compress: Compressing \(file.name) to \(archiveURL.path)")
                
                try await ArchiveManager.shared.compressFiles([file.url], to: archiveURL, format: .zip)
                
                print("Individual compression completed successfully")
                
                await MainActor.run {
                    onFileOperation() // Refresh the file list
                }
            } catch {
                print("Error compressing file: \(error)")
            }
        }
    }
    
    private func extractFile() {
        Task {
            do {
                let fileManager = FileManager.default
                let parentDirectory = file.url.deletingLastPathComponent()
                let baseName = file.name.replacingOccurrences(of: file.url.pathExtension, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
                
                // Generate a unique folder name to avoid conflicts
                var extractedFolderName = baseName
                var counter = 1
                var extractedFolderURL = parentDirectory.appendingPathComponent(extractedFolderName)
                
                // Check if folder already exists and find a unique name
                while fileManager.fileExists(atPath: extractedFolderURL.path) {
                    extractedFolderName = "\(baseName) (\(counter))"
                    extractedFolderURL = parentDirectory.appendingPathComponent(extractedFolderName)
                    counter += 1
                }
                
                print("Extracting \(file.name) to \(extractedFolderURL.path)")
                
                // Create the extraction directory
                try fileManager.createDirectory(at: extractedFolderURL, withIntermediateDirectories: true)
                print("Created extraction directory: \(extractedFolderURL.path)")
                
                try await ArchiveManager.shared.extractArchive(at: file.url, to: extractedFolderURL)
                print("Extraction completed successfully")
                
                await MainActor.run {
                    onFileOperation() // Refresh the file list
                }
            } catch {
                print("Error extracting file: \(error)")
            }
        }
    }
    
    private func getInfo() {
        // Show file info dialog
        Task {
            do {
                let fileInfo = try await getFileInfo(for: file.url)
                await MainActor.run {
                    showFileInfoDialog(fileInfo: fileInfo)
                }
            } catch {
                print("Error getting file info: \(error)")
            }
        }
    }
    
    private func getFileInfo(for url: URL) async throws -> DetailedFileInfo {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let resourceValues = try url.resourceValues(forKeys: [
                        .nameKey,
                        .fileSizeKey,
                        .isDirectoryKey,
                        .creationDateKey,
                        .contentModificationDateKey,
                        .contentAccessDateKey,
                        .fileResourceTypeKey,
                        .localizedTypeDescriptionKey,
                        .isHiddenKey,
                        .isReadableKey,
                        .isWritableKey,
                        .isExecutableKey
                    ])
                    
                    let fileInfo = DetailedFileInfo(
                        name: resourceValues.name ?? url.lastPathComponent,
                        path: url.path,
                        size: resourceValues.fileSize ?? 0,
                        isDirectory: resourceValues.isDirectory ?? false,
                        creationDate: resourceValues.creationDate,
                        modificationDate: resourceValues.contentModificationDate,
                        accessDate: resourceValues.contentAccessDate,
                        fileType: resourceValues.fileResourceType?.rawValue ?? "Unknown",
                        localizedType: resourceValues.localizedTypeDescription ?? "Unknown",
                        isHidden: resourceValues.isHidden ?? false,
                        isReadable: resourceValues.isReadable ?? false,
                        isWritable: resourceValues.isWritable ?? false,
                        isExecutable: resourceValues.isExecutable ?? false
                    )
                    
                    continuation.resume(returning: fileInfo)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func showFileInfoDialog(fileInfo: DetailedFileInfo) {
        let alert = NSAlert()
        alert.messageText = "File Information"
        alert.informativeText = formatFileInfo(fileInfo)
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    private func formatFileInfo(_ info: DetailedFileInfo) -> String {
        let sizeString = info.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: Int64(info.size), countStyle: .file)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        var infoText = "Name: \(info.name)\n"
        infoText += "Path: \(info.path)\n"
        infoText += "Size: \(sizeString)\n"
        infoText += "Kind: \(info.localizedType)\n"
        infoText += "Type: \(info.fileType)\n"
        
        if let creationDate = info.creationDate {
            infoText += "Created: \(dateFormatter.string(from: creationDate))\n"
        }
        if let modificationDate = info.modificationDate {
            infoText += "Modified: \(dateFormatter.string(from: modificationDate))\n"
        }
        if let accessDate = info.accessDate {
            infoText += "Accessed: \(dateFormatter.string(from: accessDate))\n"
        }
        
        infoText += "\nPermissions:\n"
        infoText += "Readable: \(info.isReadable ? "Yes" : "No")\n"
        infoText += "Writable: \(info.isWritable ? "Yes" : "No")\n"
        infoText += "Executable: \(info.isExecutable ? "Yes" : "No")\n"
        infoText += "Hidden: \(info.isHidden ? "Yes" : "No")"
        
        return infoText
    }
    
    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([file.url as NSURL])
        pasteboard.setString(file.url.path, forType: .string)
    }
    
    private func cutToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([file.url as NSURL])
        pasteboard.setString("cut", forType: NSPasteboard.PasteboardType("public.folderium.cut"))
        pasteboard.setString(file.url.path, forType: .string)
    }
    
    private func copyPaths() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(file.url.path, forType: .string)
    }
    
    private func renameFile() {
        // Get the current file name from the URL to avoid issues with stale FileItem
        let currentFileName = file.url.lastPathComponent
        
        // Safety check
        guard !currentFileName.isEmpty else {
            print("Error: currentFileName is empty")
            return
        }
        
        // Show rename dialog
        let alert = NSAlert()
        alert.messageText = "Rename Item"
        alert.informativeText = "Enter new name for '\(currentFileName)':"
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = currentFileName
        textField.selectText(nil)
        
        alert.accessoryView = textField
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !newName.isEmpty && newName != currentFileName {
                let newURL = file.url.deletingLastPathComponent().appendingPathComponent(newName)
                
                do {
                    try FileManager.default.moveItem(at: file.url, to: newURL)
                    onFileOperation() // Refresh the file list
                } catch {
                    // Show error alert
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Rename Failed"
                    errorAlert.informativeText = "Could not rename '\(currentFileName)' to '\(newName)': \(error.localizedDescription)"
                    errorAlert.addButton(withTitle: "OK")
                    errorAlert.alertStyle = .warning
                    errorAlert.runModal()
                }
            }
        }
    }
    
    private func moveToTrash() {
        do {
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
            onFileOperation() // Refresh the file list
        } catch {
            print("Error moving to trash: \(error)")
        }
    }
    
    private func deleteFile() {
        do {
            try FileManager.default.removeItem(at: file.url)
            onFileOperation() // Refresh the file list
        } catch {
            print("Error deleting file: \(error)")
        }
    }
}

// MARK: - Real Terminal View

struct RealTerminalView: View {
    let currentDirectory: URL
    @State private var command: String = ""
    @State private var output: String = ""
    @State private var isExecuting: Bool = false
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int = -1
    @State private var currentWorkingDirectory: URL
    @FocusState private var isInputFocused: Bool
    
    init(currentDirectory: URL) {
        self.currentDirectory = currentDirectory
        self._currentWorkingDirectory = State(initialValue: currentDirectory)
    }
    
    var body: some View {
        VStack(spacing: 0) {
                // Terminal header
                HStack {
                    Image(systemName: "terminal")
                        .foregroundColor(.green)
                    
                    Text("Terminal")
                        .font(.headline)
                    
                    Spacer()
                    
                    Text("PWD: \(currentWorkingDirectory.path)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Terminal output
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(output)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
            }
            .background(Color.black)
            .foregroundColor(.green)
            
            Divider()
            
            // Command input
            HStack {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                
                TextField("Enter command...", text: $command)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
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
                    .onKeyPress { keyPress in
                        // Handle all key presses in the terminal input
                        switch keyPress.key {
                        case .space:
                            // Allow space key to be typed normally
                            return .ignored
                        case .upArrow:
                            navigateHistory(up: true)
                            return .handled
                        case .downArrow:
                            navigateHistory(up: false)
                            return .handled
                        case .return:
                            executeCommand()
                            return .handled
                        default:
                            // Allow all other keys to be typed normally
                            return .ignored
                        }
                    }
                
                if isExecuting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: .green))
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            output = "Terminal ready. Current directory: \(currentDirectory.path)\n"
            currentWorkingDirectory = currentDirectory
            // Focus the input field when terminal appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
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
                let result = try await executeCommandInTerminal(commandToExecute, in: currentWorkingDirectory)
                
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
                    
                    // Update working directory if it changed
                    if let newDir = result.newDirectory {
                        currentWorkingDirectory = newDir
                    }
                }
            } catch {
                await MainActor.run {
                    output += "Error executing command: \(error.localizedDescription)\n"
                    isExecuting = false
                }
            }
        }
    }
    
    private func executeCommandInTerminal(_ command: String, in directory: URL) async throws -> TerminalResult {
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
                    
                    // Check if the command was a cd command and update directory
                    var newDirectory: URL? = nil
                    if command.hasPrefix("cd ") {
                        let path = String(command.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if path == ".." {
                            newDirectory = directory.deletingLastPathComponent()
                        } else if path.hasPrefix("/") {
                            newDirectory = URL(fileURLWithPath: path)
                        } else if !path.isEmpty {
                            newDirectory = directory.appendingPathComponent(path)
                        }
                    }
                    
                    let result = TerminalResult(
                        command: command,
                        output: output,
                        error: error,
                        exitCode: process.terminationStatus,
                        newDirectory: newDirectory
                    )
                    
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
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

struct TerminalResult {
    let command: String
    let output: String
    let error: String
    let exitCode: Int32
    let newDirectory: URL?
}

struct DetailedFileInfo {
    let name: String
    let path: String
    let size: Int
    let isDirectory: Bool
    let creationDate: Date?
    let modificationDate: Date?
    let accessDate: Date?
    let fileType: String
    let localizedType: String
    let isHidden: Bool
    let isReadable: Bool
    let isWritable: Bool
    let isExecutable: Bool
}

// MARK: - Empty Area Context Menu

struct EmptyAreaContextMenu: View {
    let currentPath: URL
    let onFileOperation: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("New Folder") {
                createNewFolder()
            }
            
            Button("New File") {
                createNewFileWithDialog()
            }
            
            Divider()
            
            Button("Refresh") {
                onFileOperation()
            }
            
            Divider()
            
            Button("Reveal in Finder") {
                revealInFinder()
            }
            
            Button("Copy Path") {
                copyFolderPath()
            }
            
            Divider()
            
            Button("Analyze Disk Usage") {
                analyzeDiskUsage()
            }
            
            Divider()
            
            Button("Properties") {
                getInfo()
            }
        }
    }
    
    private func createNewFolder() {
        let folderName = "New Folder"
        var finalName = folderName
        var counter = 1
        
        // Find a unique name
        while FileManager.default.fileExists(atPath: currentPath.appendingPathComponent(finalName).path) {
            finalName = "\(folderName) \(counter)"
            counter += 1
        }
        
        do {
            try FileManager.default.createDirectory(
                at: currentPath.appendingPathComponent(finalName),
                withIntermediateDirectories: true
            )
            onFileOperation()
        } catch {
            print("Error creating folder: \(error)")
        }
    }
    
    private func createNewFile(named fileName: String = "New File.txt") {
        var finalName = fileName
        var counter = 1
        
        // If no extension provided, add .txt
        if !fileName.contains(".") {
            finalName = "\(fileName).txt"
        }
        
        // Find a unique name
        while FileManager.default.fileExists(atPath: currentPath.appendingPathComponent(finalName).path) {
            if let lastDotIndex = fileName.lastIndex(of: ".") {
                let nameWithoutExt = String(fileName[..<lastDotIndex])
                let ext = String(fileName[lastDotIndex...])
                finalName = "\(nameWithoutExt) \(counter)\(ext)"
            } else {
                finalName = "\(fileName) \(counter).txt"
            }
            counter += 1
        }
        
        do {
            try "".write(
                to: currentPath.appendingPathComponent(finalName),
                atomically: true,
                encoding: .utf8
            )
            onFileOperation()
        } catch {
            print("Error creating file: \(error)")
        }
    }
    
    private func createNewFileWithDialog() {
        // Show new file dialog using NSAlert (same approach as rename)
        let alert = NSAlert()
        alert.messageText = "New File"
        alert.informativeText = "Enter the name for the new file:"
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = ""
        textField.placeholderString = "File name (e.g., MyFile.txt)"
        textField.selectText(nil)
        
        alert.accessoryView = textField
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let fileName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fileName.isEmpty {
                createNewFile(named: fileName)
            }
        }
    }
    
    private func getInfo() {
        // Show folder info
        NSWorkspace.shared.activateFileViewerSelecting([currentPath])
    }
    
    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([currentPath])
    }
    
    private func copyFolderPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentPath.path, forType: .string)
    }
    
    private func analyzeDiskUsage() {
        // Open Disk Utility or show folder size
        Task {
            do {
                let size = try await calculateFolderSize(currentPath)
                await MainActor.run {
                    showDiskUsageAlert(size: size)
                }
            } catch {
                print("Error calculating folder size: \(error)")
            }
        }
    }
    
    private func calculateFolderSize(_ url: URL) async throws -> Int64 {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var totalSize: Int64 = 0
                
                let fileManager = FileManager.default
                let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
                
                while let fileURL = enumerator?.nextObject() as? URL {
                    do {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                        totalSize += Int64(resourceValues.fileSize ?? 0)
                    } catch {
                        // Skip files that can't be read
                        continue
                    }
                }
                
                continuation.resume(returning: totalSize)
            }
        }
    }
    
    private func showDiskUsageAlert(size: Int64) {
        let alert = NSAlert()
        alert.messageText = "Disk Usage Analysis"
        alert.informativeText = "Folder: \(currentPath.lastPathComponent)\nSize: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Status Bar View

struct StatusBarView: View {
    let files: [FileItem]
    
    private var folderCount: Int {
        files.filter { $0.isDirectory }.count
    }
    
    private var fileCount: Int {
        files.filter { !$0.isDirectory }.count
    }
    
    private var totalSize: Int64 {
        files.filter { !$0.isDirectory }.reduce(0) { $0 + $1.size }
    }
    
    private var totalSizeString: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack {
                // File and folder counts
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("\(folderCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("folders")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "doc")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(fileCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Total size
                HStack(spacing: 4) {
                    Image(systemName: "externaldrive")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(totalSizeString)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Bottom border
            Divider()
        }
    }
}

#Preview {
    DualPaneView()
}
