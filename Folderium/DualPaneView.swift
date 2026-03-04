import SwiftUI
import Darwin
import UniformTypeIdentifiers

enum ActivePane {
    case left, right
}

struct QuickLocation: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let url: URL
}

struct DualPaneView: View {
    private let defaultQuickAccessWidth: CGFloat = 190
    private let defaultPaneSplitRatio: CGFloat = 0.5
    @AppStorage("folderium.pinnedPaths") private var pinnedPathsRaw: String = ""
    @AppStorage("folderium.leftCurrentPath") private var leftCurrentPathRaw: String = ""
    @AppStorage("folderium.rightCurrentPath") private var rightCurrentPathRaw: String = ""
    @AppStorage("folderium.filePaneColumnsLayout") private var columnLayoutRaw: String = ""
    @AppStorage(ShortcutStore.storageKey) private var shortcutsRaw: String = ""
    @AppStorage("folderium.softDarkThemeEnabled") private var softDarkThemeEnabled: Bool = false
    @AppStorage("folderium.showHiddenFiles") private var showHiddenFiles: Bool = false
    @State private var leftPath: URL = SandboxAccessManager.defaultDirectory
    @State private var rightPath: URL = SandboxAccessManager.defaultDirectory
    @State private var leftSelection: Set<URL> = []
    @State private var rightSelection: Set<URL> = []
    @State private var leftSearchText: String = ""
    @State private var rightSearchText: String = ""
    @State private var leftIsSearching: Bool = false
    @State private var rightIsSearching: Bool = false
    @Binding var showNavigationPane: Bool
    @State private var showDeleteConfirmation: Bool = false
    @State private var filesToDelete: [URL] = []
    @State private var deleteIntent: DeleteIntent = .permanent
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
    @State private var quickAccessWidth: CGFloat = 190
    @State private var paneSplitRatio: CGFloat = 0.5
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var paneSplitDragStartLeftWidth: CGFloat?
    @State private var leftDisplayedURLs: [URL] = []
    @State private var rightDisplayedURLs: [URL] = []
    @State private var shortcutMonitor: Any?
    @State private var hostingWindow: NSWindow?
    @State private var activeShortcutBindings: [ShortcutBinding] = ShortcutStore.defaultBindings
    @State private var pinnedPaths: [String] = []
    @State private var draggedPinnedPath: String?
    @State private var undoStack: [FileMoveBatch] = []
    @State private var redoStack: [FileMoveBatch] = []
    @State private var paneLayoutEpoch: Int = 0
    let isSinglePaneMode: Bool
    
    private enum DeleteIntent {
        case trash
        case permanent
    }
    
    private struct FileMoveEntry: Hashable {
        let from: URL
        let to: URL
    }
    
    private struct FileMoveBatch: Identifiable {
        let id = UUID()
        let title: String
        let entries: [FileMoveEntry]
    }
    
    private var activePaneSelection: Set<URL> {
        activePane == .left ? leftSelection : rightSelection
    }
    
    private var activePanePath: URL {
        activePane == .left ? leftPath : rightPath
    }
    
    private var canCreateFolderInActivePane: Bool {
        FileManager.default.isWritableFile(atPath: activePanePath.path)
    }
    
    // Callback to notify parent of selection changes
    var onSelectionChange: ((Set<URL>) -> Void)?
    
    init(
        onSelectionChange: ((Set<URL>) -> Void)? = nil,
        showNavigationPane: Binding<Bool> = .constant(true),
        isSinglePaneMode: Bool = false
    ) {
        self.onSelectionChange = onSelectionChange
        self._showNavigationPane = showNavigationPane
        self.isSinglePaneMode = isSinglePaneMode
    }
    
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

    private struct ToolbarColumnsLayout: Codable {
        var order: [String]
        var hidden: [String]
        var widths: [String: Double]
    }

    private var defaultToolbarLayout: ToolbarColumnsLayout {
        ToolbarColumnsLayout(
            order: FilePaneView.FileColumn.defaultOrder.map(\.rawValue),
            hidden: FilePaneView.FileColumn.defaultHidden.map(\.rawValue),
            widths: Dictionary(
                uniqueKeysWithValues: FilePaneView.FileColumn.defaultWidths.map { ($0.key.rawValue, Double($0.value)) }
            )
        )
    }

    private func loadToolbarColumnsLayout() -> ToolbarColumnsLayout {
        guard !columnLayoutRaw.isEmpty, let data = columnLayoutRaw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ToolbarColumnsLayout.self, from: data) else {
            return defaultToolbarLayout
        }
        return decoded
    }

    private func saveToolbarColumnsLayout(_ layout: ToolbarColumnsLayout) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        columnLayoutRaw = String(data: data, encoding: .utf8) ?? ""
    }

    private func toolbarColumnHidden(_ column: FilePaneView.FileColumn) -> Bool {
        loadToolbarColumnsLayout().hidden.contains(column.rawValue)
    }

    private func toggleToolbarColumnVisibility(_ column: FilePaneView.FileColumn) {
        var layout = loadToolbarColumnsLayout()
        var hidden = Set(layout.hidden)
        if hidden.contains(column.rawValue) {
            hidden.remove(column.rawValue)
        } else {
            hidden.insert(column.rawValue)
        }
        layout.hidden = Array(hidden)
        saveToolbarColumnsLayout(layout)
    }

    private func resetToolbarColumns() {
        saveToolbarColumnsLayout(defaultToolbarLayout)
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
        pinnedPaths.compactMap { path in
            guard !path.isEmpty else { return nil }
            let url = URL(fileURLWithPath: path)
            return QuickLocation(
                name: url.lastPathComponent.isEmpty ? path : url.lastPathComponent,
                icon: "pin",
                url: url
            )
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                explorerToolbarButton("Open Left", systemImage: "folder.badge.plus") { selectFolder(for: .left) }
                explorerToolbarButton("Open Right", systemImage: "folder.badge.plus") { selectFolder(for: .right) }
                
                Divider().frame(height: 18)
                
                explorerToolbarButton("Copy", systemImage: "doc.on.doc", shortcutHint: toolbarShortcutText(for: .copySelected)) { copySelectedFiles() }
                    .disabled(activePaneSelection.isEmpty)
                explorerToolbarButton("Cut", systemImage: "scissors", shortcutHint: toolbarShortcutText(for: .cutSelected)) { cutSelectedFiles() }
                    .disabled(activePaneSelection.isEmpty)
                explorerToolbarButton("Paste", systemImage: "doc.on.clipboard", shortcutHint: toolbarShortcutText(for: .pasteIntoActivePane)) { pasteFiles() }
                    .disabled(!hasFilesInClipboard())
                    .onChange(of: clipboardCheckTrigger) { _, _ in }
                explorerToolbarButton("New Folder", systemImage: "folder.badge.plus", shortcutHint: toolbarShortcutText(for: .newFolderInActivePane)) {
                    createNewFolderInActivePane()
                }
                .disabled(!canCreateFolderInActivePane)
                
                Divider().frame(height: 18)
                
                explorerToolbarButton("Rename", systemImage: "pencil", shortcutHint: toolbarShortcutText(for: .renameSelected)) { renameSelectedItem() }
                    .disabled(activePaneSelection.count != 1)
                explorerToolbarButton("Trash", systemImage: "trash", shortcutHint: toolbarShortcutText(for: .deleteSelected)) { trashSelectedFiles() }
                    .disabled(activePaneSelection.isEmpty)
                explorerToolbarButton("Compress", systemImage: "archivebox") { compressSelectedFiles() }
                    .disabled(activePaneSelection.isEmpty)
                explorerToolbarButton("Undo", systemImage: "arrow.uturn.backward", shortcutHint: toolbarShortcutText(for: .undoLastOperation)) { undoLastOperation() }
                    .disabled(undoStack.isEmpty)
                explorerToolbarButton("Redo", systemImage: "arrow.uturn.forward", shortcutHint: toolbarShortcutText(for: .redoLastOperation)) { redoLastOperation() }
                    .disabled(redoStack.isEmpty)

                Divider().frame(height: 18)

                explorerToolbarButton(showHiddenFiles ? "Hide Hidden" : "Show Hidden", systemImage: showHiddenFiles ? "eye.slash" : "eye") {
                    showHiddenFiles.toggle()
                }

                Menu {
                    Section("Show / Hide Columns") {
                        ForEach(FilePaneView.FileColumn.allCases, id: \.self) { column in
                            Button {
                                toggleToolbarColumnVisibility(column)
                            } label: {
                                HStack {
                                    Image(systemName: toolbarColumnHidden(column) ? "square" : "checkmark.square.fill")
                                    Text(column.title)
                                }
                            }
                        }
                    }

                    Divider()

                    Button("Reset Columns") {
                        resetToolbarColumns()
                    }
                } label: {
                    Label("Columns", systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(FolderiumTheme.controlBackground(isSoftDark: softDarkThemeEnabled))
            
            Divider()
            
            GeometryReader { geometry in
                let totalWidth = max(geometry.size.width, 500)
                let clampedSidebarWidth = min(max(quickAccessWidth, 150), totalWidth * 0.45)
                let sidebarWidth = showNavigationPane ? clampedSidebarWidth : 0
                let sidebarSplitterWidth: CGFloat = showNavigationPane ? 6 : 0
                let paneSplitterWidth: CGFloat = isSinglePaneMode ? 0 : 6
                let remainingWidth = max(totalWidth - sidebarWidth - sidebarSplitterWidth - paneSplitterWidth, 300)
                let clampedPaneSplit = min(max(paneSplitRatio, 0.2), 0.8)
                let minPaneWidth: CGFloat = 150
                let leftPaneWidth = min(max(remainingWidth * clampedPaneSplit, minPaneWidth), remainingWidth - minPaneWidth)
                let rightPaneWidth = remainingWidth - leftPaneWidth
                
                HStack(spacing: 0) {
                    if showNavigationPane {
                        quickAccessSidebar
                            .frame(width: clampedSidebarWidth)
                        
                        Rectangle()
                            .fill(FolderiumTheme.separator(isSoftDark: softDarkThemeEnabled))
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
                                        quickAccessWidth = min(max(proposed, 150), totalWidth * 0.45)
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
                    }
                    
                    if !isSinglePaneMode || activePane == .left {
                        VStack(spacing: 0) {
                            FilePaneView(
                                path: $leftPath,
                                selection: $leftSelection,
                                searchText: $leftSearchText,
                                isSearching: $leftIsSearching,
                                showHiddenFiles: showHiddenFiles,
                                title: "Left Pane",
                                isActive: activePane == .left,
                                onOpenInTerminal: { openInTerminal(leftPath) },
                                onRefresh: { refreshTrigger = UUID() },
                                refreshTrigger: refreshTrigger,
                                onBulkCompress: compressSelectedFiles,
                                canNavigateBack: !leftBackHistory.isEmpty,
                                canNavigateForward: !leftForwardHistory.isEmpty,
                                onNavigateBack: { navigateBack(in: .left) },
                                onNavigateForward: { navigateForward(in: .left) },
                                onNavigateUp: { navigateUp(in: .left) },
                                canPasteFromClipboard: { hasFilesInClipboard() },
                                onPasteIntoPath: { destination in
                                    activePane = .left
                                    pasteFiles(destinationOverride: destination ?? leftPath)
                                },
                                onRecordMoveBatch: { title, pairs in
                                    recordMovedItemsBatch(title: title, pairs: pairs)
                                },
                                onDisplayedURLsChange: { urls in
                                    leftDisplayedURLs = urls
                                },
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
                                leftCurrentPathRaw = newValue.path
                            }
                            
                        }
                        .id("left-pane-\(paneLayoutEpoch)")
                        .frame(width: isSinglePaneMode ? remainingWidth : leftPaneWidth, alignment: .leading)
                        .clipped()
                    }
                    
                    if !isSinglePaneMode {
                        Rectangle()
                            .fill(FolderiumTheme.separator(isSoftDark: softDarkThemeEnabled))
                            .frame(width: 6)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 2)
                                    .onChanged { value in
                                        let usableWidth = remainingWidth
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
                    }
                    
                    if !isSinglePaneMode || activePane == .right {
                        VStack(spacing: 0) {
                            FilePaneView(
                                path: $rightPath,
                                selection: $rightSelection,
                                searchText: $rightSearchText,
                                isSearching: $rightIsSearching,
                                showHiddenFiles: showHiddenFiles,
                                title: "Right Pane",
                                isActive: activePane == .right,
                                onOpenInTerminal: { openInTerminal(rightPath) },
                                onRefresh: { refreshTrigger = UUID() },
                                refreshTrigger: refreshTrigger,
                                onBulkCompress: compressSelectedFiles,
                                canNavigateBack: !rightBackHistory.isEmpty,
                                canNavigateForward: !rightForwardHistory.isEmpty,
                                onNavigateBack: { navigateBack(in: .right) },
                                onNavigateForward: { navigateForward(in: .right) },
                                onNavigateUp: { navigateUp(in: .right) },
                                canPasteFromClipboard: { hasFilesInClipboard() },
                                onPasteIntoPath: { destination in
                                    activePane = .right
                                    pasteFiles(destinationOverride: destination ?? rightPath)
                                },
                                onRecordMoveBatch: { title, pairs in
                                    recordMovedItemsBatch(title: title, pairs: pairs)
                                },
                                onDisplayedURLsChange: { urls in
                                    rightDisplayedURLs = urls
                                },
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
                                rightCurrentPathRaw = newValue.path
                            }
                            
                        }
                        .id("right-pane-\(paneLayoutEpoch)")
                        .frame(width: isSinglePaneMode ? remainingWidth : rightPaneWidth, alignment: .leading)
                        .clipped()
                    }
                }
                .clipped()
            }
        }
        .background(FolderiumTheme.windowBackground(isSoftDark: softDarkThemeEnabled))
        .background(WindowAccessor(window: $hostingWindow).frame(width: 0, height: 0))
        .alert(deleteIntent == .trash ? "Move to Trash" : "Delete Files", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(deleteIntent == .trash ? "Move to Trash" : "Delete", role: .destructive) {
                performSelectedDelete()
            }
        } message: {
            if filesToDelete.count == 1 {
                if deleteIntent == .trash {
                    Text("Move '\(filesToDelete.first?.lastPathComponent ?? "")' to Trash?")
                } else {
                    Text("Are you sure you want to permanently delete '\(filesToDelete.first?.lastPathComponent ?? "")'? This action cannot be undone.")
                }
            } else {
                if deleteIntent == .trash {
                    Text("Move \(filesToDelete.count) selected items to Trash?")
                } else {
                    Text("Are you sure you want to permanently delete \(filesToDelete.count) files? This action cannot be undone.")
                }
            }
        }
        .onAppear {
            var didRestoreAnyBookmark = false
            if let restoredLeftPath = SandboxAccessManager.restoreBookmark(for: .left) {
                leftPath = resolveRestoredPath(savedPathRaw: leftCurrentPathRaw, fallbackRoot: restoredLeftPath)
                didRestoreAnyBookmark = true
            }
            if let restoredRightPath = SandboxAccessManager.restoreBookmark(for: .right) {
                rightPath = resolveRestoredPath(savedPathRaw: rightCurrentPathRaw, fallbackRoot: restoredRightPath)
                didRestoreAnyBookmark = true
            }
            if !didRestoreAnyBookmark {
                promptForInitialDownloadsAccess()
            }
            pinnedPaths = sanitizePinnedPaths(from: pinnedPathsRaw)
            persistPinnedPaths()
            activeShortcutBindings = ShortcutStore.load(from: shortcutsRaw)
            startShortcutMonitor()
        }
        .onDisappear {
            stopShortcutMonitor()
        }
        .onChange(of: shortcutsRaw) { _, _ in
            activeShortcutBindings = ShortcutStore.load(from: shortcutsRaw)
            // Reload monitor so updated shortcut bindings apply immediately.
            restartShortcutMonitor()
        }
        .onChange(of: pinnedPaths) { _, _ in
            persistPinnedPaths()
        }
        .onChange(of: pinnedPathsRaw) { _, newValue in
            let sanitized = sanitizePinnedPaths(from: newValue)
            if sanitized != pinnedPaths {
                pinnedPaths = sanitized
            }
        }
        .onChange(of: isSinglePaneMode) { _, _ in
            // Returning from preview mode should restore balanced dual-pane layout.
            if !isSinglePaneMode {
                paneSplitRatio = defaultPaneSplitRatio
            }
            paneLayoutEpoch += 1
            refreshTrigger = UUID()
        }
        .onChange(of: showNavigationPane) { _, _ in
            // Apply the same stable-reset approach as preview toggling.
            paneLayoutEpoch += 1
            refreshTrigger = UUID()
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
                        
                        ForEach(pinnedLocations, id: \.url.path) { location in
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
                            .contextMenu {
                                Button("Unpin") {
                                    unpinLocation(location.url)
                                }
                            }
                            .onDrag {
                                draggedPinnedPath = location.url.path
                                return NSItemProvider(object: location.url.path as NSString)
                            }
                            .onDrop(of: [UTType.plainText], delegate: PinnedLocationDropDelegate(
                                targetPath: location.url.path,
                                pinnedPaths: $pinnedPaths,
                                draggedPath: $draggedPinnedPath
                            ))
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
                            HStack(spacing: 8) {
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
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    unmountVolume(location.url)
                                } label: {
                                    Image(systemName: "eject.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("Unmount \(location.name)")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
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
        .background(FolderiumTheme.windowBackground(isSoftDark: softDarkThemeEnabled))
    }
    
    @ViewBuilder
    private func explorerToolbarButton(
        _ title: String,
        systemImage: String,
        shortcutHint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                    if let shortcutHint, !shortcutHint.isEmpty {
                        Text(shortcutHint)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private func toolbarShortcutText(for action: ShortcutAction) -> String {
        guard let binding = activeShortcutBindings.first(where: { $0.action == action && $0.isEnabled }),
              let normalized = ShortcutParser.normalizedCombo(binding.combo) else {
            return ""
        }

        return normalized
            .split(separator: "+")
            .map { token in
                switch token {
                case "cmd": return "Cmd"
                case "shift": return "Shift"
                case "opt": return "Opt"
                case "ctrl": return "Ctrl"
                case "fn": return "Fn"
                default: return token.uppercased()
                }
            }
            .joined(separator: "+")
    }
    
    private func openInTerminal(_ directory: URL) {
        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            NSWorkspace.shared.open(directory)
            return
        }
        
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([directory], withApplicationAt: terminalURL, configuration: configuration) { _, error in
            if let error {
                print("Failed to open Terminal for directory \(directory.path): \(error.localizedDescription)")
                NSWorkspace.shared.open(directory)
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
                leftCurrentPathRaw = selectedURL.path
                SandboxAccessManager.saveBookmark(for: .left, url: selectedURL)
            case .right:
                rightPath = selectedURL
                rightCurrentPathRaw = selectedURL.path
                SandboxAccessManager.saveBookmark(for: .right, url: selectedURL)
            }
        }
    }

    private func resolveRestoredPath(savedPathRaw: String, fallbackRoot: URL) -> URL {
        guard !savedPathRaw.isEmpty else { return fallbackRoot }
        let candidate = URL(fileURLWithPath: savedPathRaw)
        guard candidate.path == fallbackRoot.path || candidate.path.hasPrefix(fallbackRoot.path + "/") else {
            return fallbackRoot
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: candidate.path) else {
            return fallbackRoot
        }
        return candidate
    }

    private func promptForInitialDownloadsAccess() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = downloads
        panel.prompt = "Allow Access"
        panel.message = "Grant Folderium access to your Downloads folder."

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        guard selectedURL.startAccessingSecurityScopedResource() else {
            print("Failed to access initial startup folder: \(selectedURL.path)")
            return
        }

        leftPath = selectedURL
        rightPath = selectedURL
        leftCurrentPathRaw = selectedURL.path
        rightCurrentPathRaw = selectedURL.path
        SandboxAccessManager.saveBookmark(for: .left, url: selectedURL)
        SandboxAccessManager.saveBookmark(for: .right, url: selectedURL)
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
        guard !current.isEmpty else { return }
        if !pinnedPaths.contains(current) {
            pinnedPaths.append(current)
        }
        persistPinnedPaths()
    }
    
    private func unpinLocation(_ url: URL) {
        pinnedPaths.removeAll { $0 == url.path }
        persistPinnedPaths()
    }
    
    private func persistPinnedPaths() {
        let sanitized = sanitizePinnedPaths(pinnedPaths)
        if sanitized != pinnedPaths {
            pinnedPaths = sanitized
            return
        }
        let encoded = sanitized.joined(separator: "\n")
        if pinnedPathsRaw != encoded {
            pinnedPathsRaw = encoded
        }
    }
    
    private func sanitizePinnedPaths(from rawValue: String) -> [String] {
        sanitizePinnedPaths(rawValue.split(separator: "\n").map(String.init))
    }
    
    private func sanitizePinnedPaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in paths {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  FileManager.default.isReadableFile(atPath: trimmed) else {
                continue
            }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    private func unmountVolume(_ url: URL) {
        Task {
            do {
                try await FileManager.default.unmountVolume(at: url, options: [])
                await MainActor.run {
                    refreshTrigger = UUID()
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Unable to Unmount Drive"
                    alert.informativeText = "Could not unmount '\(url.lastPathComponent)': \(error.localizedDescription)"
                    alert.addButton(withTitle: "OK")
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
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
            recordMovedItemsBatch(title: "Rename", pairs: [(from: selectedURL, to: newURL)])
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
            let selectedFiles = Array(activePaneSelection)
            print("Copy selected called with \(selectedFiles.count) files from \(activePane == .left ? "left" : "right") pane")
            
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
            let selectedFiles = Array(activePaneSelection)
            print("Cut selected called with \(selectedFiles.count) files from \(activePane == .left ? "left" : "right") pane")
            
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
        
        private func pasteFiles(destinationOverride: URL? = nil) {
            let pasteboard = NSPasteboard.general
            
            print("Paste called - checking clipboard contents")
            
            // Check if there are file URLs in the clipboard
            if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] {
                let urls = fileURLs.compactMap { $0 as URL }
                print("Found \(urls.count) file URLs in clipboard")
                
                if !urls.isEmpty {
                    // Determine target directory (explicit destination or active pane)
                    let targetDirectory = destinationOverride ?? (activePane == .left ? leftPath : rightPath)
                    
                    print("Pasting \(urls.count) files to \(targetDirectory.path)")
                    
                    Task {
                        do {
                            var movedPairs: [(from: URL, to: URL)] = []
                            for url in urls {
                                let destinationURL = targetDirectory.appendingPathComponent(url.lastPathComponent)
                                let finalDestinationURL = resolveConflictDestination(
                                    sourceURL: url,
                                    destinationURL: destinationURL,
                                    in: targetDirectory
                                )
                                guard let finalDestinationURL else { continue }
                                
                                if isCutOperation {
                                    // Move file
                                    try FileManager.default.moveItem(at: url, to: finalDestinationURL)
                                    movedPairs.append((from: url, to: finalDestinationURL))
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
                                if isCutOperation, !movedPairs.isEmpty {
                                    recordMovedItemsBatch(title: "Move via Paste", pairs: movedPairs)
                                }
                                
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
        
        private func resolveConflictDestination(sourceURL: URL, destinationURL: URL, in directory: URL) -> URL? {
            guard FileManager.default.fileExists(atPath: destinationURL.path) else {
                return destinationURL
            }
            
            let choice = askConflictChoice(sourceURL: sourceURL, destinationURL: destinationURL)
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
            let selectedFiles = Array(activePaneSelection)
            print("Bulk compress called with \(selectedFiles.count) files from \(activePane == .left ? "left" : "right") pane")
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
    
    private func trashSelectedFiles() {
        deleteIntent = .trash
        filesToDelete = Array(activePaneSelection)
        if !filesToDelete.isEmpty {
            showDeleteConfirmation = true
        }
    }
    
    private func deleteSelectedFilesPermanently() {
        deleteIntent = .permanent
        filesToDelete = Array(activePaneSelection)
        if !filesToDelete.isEmpty {
            showDeleteConfirmation = true
        }
    }
    
    private func performSelectedDelete() {
        for fileURL in filesToDelete {
            do {
                switch deleteIntent {
                case .trash:
                    try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                case .permanent:
                    try FileManager.default.removeItem(at: fileURL)
                }
            } catch {
                print("Error deleting file \(fileURL.lastPathComponent): \(error)")
            }
        }
        
        // Clear selection in active pane only (operations are scoped to active pane).
        if activePane == .left {
            leftSelection.removeAll()
            onSelectionChange?(leftSelection)
        } else {
            rightSelection.removeAll()
            onSelectionChange?(rightSelection)
        }
        
        // Trigger refresh of both panes
        refreshTrigger = UUID()
    }
    
    private func recordMovedItemsBatch(title: String, pairs: [(from: URL, to: URL)]) {
        let entries = pairs
            .filter { $0.from != $0.to }
            .map { FileMoveEntry(from: $0.from, to: $0.to) }
        guard !entries.isEmpty else { return }
        undoStack.append(FileMoveBatch(title: title, entries: entries))
        redoStack.removeAll()
    }
    
    private func undoLastOperation() {
        guard let batch = undoStack.popLast() else { return }
        Task {
            var reversedPairs: [(from: URL, to: URL)] = []
            for entry in batch.entries.reversed() {
                do {
                    try FileManager.default.moveItem(at: entry.to, to: entry.from)
                    reversedPairs.append((from: entry.to, to: entry.from))
                } catch {
                    print("Undo failed for \(entry.to.lastPathComponent): \(error)")
                }
            }
            
            await MainActor.run {
                if !reversedPairs.isEmpty {
                    redoStack.append(batch)
                    refreshTrigger = UUID()
                } else {
                    // Keep user action recoverable even if filesystem state changed unexpectedly.
                    undoStack.append(batch)
                }
            }
        }
    }
    
    private func redoLastOperation() {
        guard let batch = redoStack.popLast() else { return }
        Task {
            var reappliedPairs: [(from: URL, to: URL)] = []
            for entry in batch.entries {
                do {
                    try FileManager.default.moveItem(at: entry.from, to: entry.to)
                    reappliedPairs.append((from: entry.from, to: entry.to))
                } catch {
                    print("Redo failed for \(entry.from.lastPathComponent): \(error)")
                }
            }
            
            await MainActor.run {
                if !reappliedPairs.isEmpty {
                    undoStack.append(batch)
                    refreshTrigger = UUID()
                } else {
                    // Keep user action recoverable even if filesystem state changed unexpectedly.
                    redoStack.append(batch)
                }
            }
        }
    }

    private func restartShortcutMonitor() {
        stopShortcutMonitor()
        startShortcutMonitor()
    }

    private func startShortcutMonitor() {
        guard shortcutMonitor == nil else { return }

        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard hostingWindow?.isKeyWindow == true else {
                return event
            }

            guard let eventCombo = ShortcutParser.comboFromEvent(event) else {
                return event
            }

            guard let binding = activeShortcutBindings.first(where: {
                $0.isEnabled && ShortcutParser.normalizedCombo($0.combo) == eventCombo
            }) else {
                return event
            }

            if let responder = NSApp.keyWindow?.firstResponder as? NSTextView,
               responder.isEditable {
                if !event.modifierFlags.contains(.command) {
                    return event
                }
                if shouldBypassShortcutInEditableContext(binding.action) {
                    return event
                }
            }

            performShortcutAction(binding.action)
            return nil
        }
    }

    private func stopShortcutMonitor() {
        if let monitor = shortcutMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutMonitor = nil
        }
    }

    private func performShortcutAction(_ action: ShortcutAction) {
        switch action {
        case .newWindow:
            (NSApp.delegate as? AppDelegate)?.openNewWindow()
        case .selectAllInActivePane:
            selectAllInActivePane()
        case .newFolderInActivePane:
            createNewFolderInActivePane()
        case .renameSelected:
            renameSelectedItem()
        case .copySelected:
            copySelectedFiles()
        case .cutSelected:
            cutSelectedFiles()
        case .pasteIntoActivePane:
            pasteFiles()
        case .deleteSelected:
            trashSelectedFiles()
        case .deleteSelectedPermanently:
            deleteSelectedFilesPermanently()
        case .undoLastOperation:
            undoLastOperation()
        case .redoLastOperation:
            redoLastOperation()
        case .compressSelected:
            compressSelectedFiles()
        case .refreshActivePane:
            refreshTrigger = UUID()
        case .openTerminalActivePane:
            openInTerminal(activePane == .left ? leftPath : rightPath)
        case .navigateBackActivePane:
            navigateBack(in: activePane)
        case .navigateForwardActivePane:
            navigateForward(in: activePane)
        case .navigateUpActivePane:
            navigateUp(in: activePane)
        }
    }
    
    private func shouldBypassShortcutInEditableContext(_ action: ShortcutAction) -> Bool {
        switch action {
        case .copySelected,
             .cutSelected,
             .pasteIntoActivePane,
             .undoLastOperation,
             .redoLastOperation:
            return true
        default:
            return false
        }
    }
    
    private func selectAllInActivePane() {
        let urls = activePane == .left ? leftDisplayedURLs : rightDisplayedURLs
        let selected = Set(urls)
        if activePane == .left {
            leftSelection = selected
            onSelectionChange?(leftSelection)
        } else {
            rightSelection = selected
            onSelectionChange?(rightSelection)
        }
    }
    
    private func createNewFolderInActivePane() {
        let targetDirectory = activePane == .left ? leftPath : rightPath
        let baseName = "New Folder"
        var candidateName = baseName
        var counter = 1
        
        while FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent(candidateName).path) {
            candidateName = "\(baseName) \(counter)"
            counter += 1
        }
        
        let newFolderURL = targetDirectory.appendingPathComponent(candidateName)
        do {
            try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: false)
            if activePane == .left {
                leftSelection = [newFolderURL]
                onSelectionChange?(leftSelection)
            } else {
                rightSelection = [newFolderURL]
                onSelectionChange?(rightSelection)
            }
            refreshTrigger = UUID()
        } catch {
            print("Error creating folder in active pane: \(error)")
        }
    }
}

struct FilePaneView: View {
    @AppStorage("folderium.softDarkThemeEnabled") private var softDarkThemeEnabled: Bool = false
    @AppStorage("folderium.globalFontSize") private var globalFontSize: Double = 12
    @AppStorage("folderium.filePaneColumnsLayout") private var columnLayoutRaw: String = ""
    @Binding var path: URL
    @Binding var selection: Set<URL>
    @Binding var searchText: String
    @Binding var isSearching: Bool
    let showHiddenFiles: Bool
    let title: String
    let isActive: Bool
    let onOpenInTerminal: () -> Void
    let onRefresh: () -> Void
    let refreshTrigger: UUID
    let onBulkCompress: () -> Void
    let canNavigateBack: Bool
    let canNavigateForward: Bool
    let onNavigateBack: () -> Void
    let onNavigateForward: () -> Void
    let onNavigateUp: () -> Void
    let canPasteFromClipboard: () -> Bool
    let onPasteIntoPath: (URL?) -> Void
    let onRecordMoveBatch: (_ title: String, _ pairs: [(from: URL, to: URL)]) -> Void
    let onDisplayedURLsChange: ([URL]) -> Void
    let onFocus: () -> Void
    
    @State private var files: [FileItem] = []
    @State private var displayedFiles: [FileItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var sortOrder: SortOrder = .name
    @State private var sortDirection: SortDirection = .ascending
    @State private var columnOrder: [FileColumn] = FileColumn.defaultOrder
    @State private var hiddenColumns: Set<FileColumn> = []
    @State private var columnWidths: [FileColumn: CGFloat] = FileColumn.defaultWidths
    @State private var resizingColumn: FileColumn?
    @State private var resizeStartWidth: CGFloat?
    @State private var draggedColumn: FileColumn?
    @State private var dragOverColumn: FileColumn?
    @State private var tableWidth: CGFloat = 0
    @State private var isEditingPathBar: Bool = false
    @FocusState private var isPathFieldFocused: Bool
    @State private var pathInput: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var directoryWatcher: DirectoryWatcher?
    @State private var watcherDebounceTask: Task<Void, Never>?
    @State private var inlineRenamingURL: URL?
    @State private var inlineRenameText: String = ""
    @State private var lastPlainClickURL: URL?
    @State private var lastPlainClickTimestamp: Date?
    @State private var keyboardSelectionAnchor: URL?
    @State private var keyboardSelectionFocus: URL?
    @State private var isAdvancedSearchEnabled: Bool = false
    @State private var advancedSearchQuery: String = ""
    @State private var advancedSearchInContents: Bool = false
    @State private var advancedSearchRegex: Bool = false
    @State private var advancedSearchCaseSensitive: Bool = false
    @State private var advancedSearchFileTypes: String = ""
    @State private var advancedSearchResults: [SearchResult] = []
    @State private var advancedSearchIsRunning: Bool = false
    @State private var advancedSearchError: String?
    @State private var advancedSearchTask: Task<Void, Never>?
    @State private var advancedSelectedResult: URL?
    private static let internalDragPrefix = "folderium-internal-drag-v1"
    
    private enum DragFileOperation: Equatable {
        case move
        case copy
    }
    
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

    enum FileColumn: String, CaseIterable, Hashable {
        case name, type, size, modified

        static let defaultOrder: [FileColumn] = [.name, .type, .size, .modified]
        static let defaultHidden: Set<FileColumn> = [.type]
        static let defaultWidths: [FileColumn: CGFloat] = [
            .name: 360,
            .type: 130,
            .size: 70,
            .modified: 124
        ]

        var title: String {
            switch self {
            case .name: return "Name"
            case .type: return "Type"
            case .size: return "Size"
            case .modified: return "Modified"
            }
        }

        var minWidth: CGFloat {
            switch self {
            case .name: return 180
            case .type: return 120
            case .size: return 64
            case .modified: return 110
            }
        }
    }

    private struct PersistedColumnsLayout: Codable {
        let order: [String]
        let hidden: [String]
        let widths: [String: Double]
    }

    private var paneBaseFont: Font {
        .system(size: CGFloat(globalFontSize))
    }

    private var paneSmallFont: Font {
        .system(size: CGFloat(max(globalFontSize - 2, 10)))
    }

    private var paneTinyFont: Font {
        .system(size: CGFloat(max(globalFontSize - 3, 9)))
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
                .allowsHitTesting(false)
        )
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        tableWidth = geometry.size.width
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        tableWidth = newWidth
                    }
            }
        )
        .clipped()
        .onAppear {
            pathInput = path.path
            loadColumnLayout()
            loadFiles()
            startDirectoryWatcher()
        }
        .onChange(of: path) { _, _ in
            // Clear selection when path changes
            selection = []
            keyboardSelectionAnchor = nil
            keyboardSelectionFocus = nil
            advancedSelectedResult = nil
            if isAdvancedSearchEnabled {
                advancedSearchResults = []
                advancedSearchError = nil
            }
            pathInput = path.path
            cancelInlineRename()
            loadFiles()
            startDirectoryWatcher()
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
        .onChange(of: showHiddenFiles) { _, _ in
            loadFiles()
        }
        .onChange(of: sortOrder) { _, _ in
            applyFiltersAndSorting()
        }
        .onChange(of: sortDirection) { _, _ in
            applyFiltersAndSorting()
        }
        .onChange(of: isAdvancedSearchEnabled) { _, _ in
            publishVisibleURLsForShortcuts()
        }
        .onChange(of: advancedSearchResults) { _, _ in
            if isAdvancedSearchEnabled {
                publishVisibleURLsForShortcuts()
            }
        }
        .onChange(of: columnLayoutRaw) { _, _ in
            loadColumnLayout()
        }
        .onKeyPress(.downArrow) {
            moveSelectionByArrow(delta: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelectionByArrow(delta: -1)
            return .handled
        }
        .onDisappear {
            stopDirectoryWatcher()
            searchDebounceTask?.cancel()
            watcherDebounceTask?.cancel()
            advancedSearchTask?.cancel()
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
        .background(FolderiumTheme.windowBackground(isSoftDark: softDarkThemeEnabled))
        .onTapGesture {
            onFocus()
        }
    }
    
    @ViewBuilder
    private var searchFieldView: some View {
        let activeSearchBinding = Binding<String>(
            get: { isAdvancedSearchEnabled ? advancedSearchQuery : searchText },
            set: { newValue in
                if isAdvancedSearchEnabled {
                    advancedSearchQuery = newValue
                } else {
                    searchText = newValue
                }
            }
        )
        
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(
                isAdvancedSearchEnabled ? "Advanced search in \(path.lastPathComponent.isEmpty ? title.lowercased() : path.lastPathComponent)..." : "Search in \(title.lowercased())...",
                text: activeSearchBinding,
                onEditingChanged: { isEditing in
                if isEditing {
                    onFocus()
                }
            })
                .textFieldStyle(.plain)
                .onSubmit {
                    if isAdvancedSearchEnabled {
                        runAdvancedSearch()
                    } else {
                        performSearch()
                    }
                }
                .onChange(of: activeSearchBinding.wrappedValue) { _, _ in
                    onFocus()
                }
            
            Button(isAdvancedSearchEnabled ? "Basic" : "Advanced") {
                isAdvancedSearchEnabled.toggle()
                if isAdvancedSearchEnabled {
                    advancedSearchQuery = searchText
                    advancedSearchResults = []
                    advancedSearchError = nil
                } else {
                    advancedSearchTask?.cancel()
                    advancedSearchIsRunning = false
                }
            }
            .buttonStyle(.borderless)
            
            if !(isAdvancedSearchEnabled ? advancedSearchQuery : searchText).isEmpty {
                Button("Clear") {
                    if isAdvancedSearchEnabled {
                        advancedSearchQuery = ""
                        advancedSearchResults = []
                        advancedSearchError = nil
                        advancedSelectedResult = nil
                    } else {
                        searchText = ""
                        isSearching = false
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(FolderiumTheme.controlBackground(isSoftDark: softDarkThemeEnabled))
        .cornerRadius(6)
        .onTapGesture {
            onFocus()
        }
    }
    
    @ViewBuilder
    private var terminalButtonView: some View {
        Button("Open in Terminal") {
            onOpenInTerminal()
        }
        .buttonStyle(.bordered)
        .onTapGesture {
            onFocus()
        }
    }
    
    @ViewBuilder
    private var pathBarView: some View {
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
            
            if isEditingPathBar {
                TextField("Enter path", text: $pathInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: CGFloat(globalFontSize), design: .monospaced))
                    .focused($isPathFieldFocused)
                    .onSubmit {
                        if commitPathInput() {
                            isEditingPathBar = false
                        }
                    }
                
                Button {
                    if commitPathInput() {
                        isEditingPathBar = false
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.bordered)
                
                Button {
                    pathInput = path.path
                    isEditingPathBar = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
            } else {
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
                                    .font(paneTinyFont)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Button {
                    pathInput = path.path
                    isEditingPathBar = true
                    DispatchQueue.main.async {
                        isPathFieldFocused = true
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .help("Edit full path")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(FolderiumTheme.controlBackground(isSoftDark: softDarkThemeEnabled))
        .onTapGesture {
            onFocus()
        }
        
        Divider()
    }
    
    @ViewBuilder
    private var fileListView: some View {
        if isAdvancedSearchEnabled {
            advancedSearchResultsView
        } else if isLoading {
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
    private var advancedSearchResultsView: some View {
        VStack(spacing: 0) {
            advancedSearchControls
            Divider()
            
            if advancedSearchIsRunning {
                VStack {
                    ProgressView()
                    Text("Searching...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let advancedSearchError {
                errorView(advancedSearchError)
            } else if advancedSearchResults.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary)
                    Text("No search results")
                        .foregroundColor(.secondary)
                    Text("Try a different query or toggle content search.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(advancedSearchResults) { result in
                            SearchResultRowView(
                                result: result,
                                isSelected: advancedSelectedResult == result.url,
                                onSelect: {
                                    advancedSelectedResult = result.url
                                },
                                onOpen: {
                                    openSearchResult(result)
                                }
                            )
                        }
                    }
                }
            }
            
            HStack {
                Text("\(advancedSearchResults.count) result(s)")
                    .font(paneTinyFont)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(FolderiumTheme.controlBackground(isSoftDark: softDarkThemeEnabled))
        }
    }
    
    @ViewBuilder
    private var advancedSearchControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Toggle("Contents", isOn: $advancedSearchInContents)
                Toggle("Regex", isOn: $advancedSearchRegex)
                Toggle("Case Sensitive", isOn: $advancedSearchCaseSensitive)
                Spacer()
            }
            .font(paneTinyFont)
            
            HStack(spacing: 8) {
                TextField("File types (csv,txt,swift)", text: $advancedSearchFileTypes)
                    .textFieldStyle(.roundedBorder)
                    .font(paneTinyFont)
                
                Button("Search") {
                    runAdvancedSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(advancedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(FolderiumTheme.windowBackground(isSoftDark: softDarkThemeEnabled))
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
        HStack(spacing: 0) {
            ForEach(Array(visibleColumns.enumerated()), id: \.element) { index, column in
                columnHeaderButton(for: column)
                    .frame(width: effectiveColumnWidth(for: column), alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FolderiumTheme.controlBackground(isSoftDark: softDarkThemeEnabled))
        .clipped()
    }

    private var visibleColumns: [FileColumn] {
        columnOrder.filter { !hiddenColumns.contains($0) }
    }

    private func columnWidth(for column: FileColumn) -> CGFloat {
        let base = columnWidths[column] ?? FileColumn.defaultWidths[column] ?? 120
        return max(base, column.minWidth)
    }

    private func effectiveColumnWidth(for column: FileColumn) -> CGFloat {
        resolvedColumnWidths()[column] ?? columnWidth(for: column)
    }

    private func availableWidthForColumns() -> CGFloat {
        guard tableWidth > 0 else {
            // During layout transitions (e.g. toggling navigation/preview), tableWidth can
            // be temporarily zero. Returning a huge value here causes oversized columns that
            // visually clip from pane edges. Keep this bounded to minimum viable width.
            let minVisibleWidth = visibleColumns.reduce(CGFloat(0)) { partial, column in
                partial + column.minWidth
            }
            return max(minVisibleWidth, 120)
        }
        let separators = CGFloat(max(visibleColumns.count - 1, 0)) * 5
        let reservedHorizontalPadding: CGFloat = 24 // 12 left + 12 right
        return max(tableWidth - reservedHorizontalPadding - separators, 120)
    }

    private func maxAllowedWidth(for column: FileColumn) -> CGFloat {
        let otherVisible = visibleColumns.filter { $0 != column }
        let otherMinWidths = otherVisible.reduce(CGFloat(0)) { $0 + $1.minWidth }
        let maxForCurrent = availableWidthForColumns() - otherMinWidths
        return max(column.minWidth, maxForCurrent)
    }

    private func resolvedColumnWidths() -> [FileColumn: CGFloat] {
        guard !visibleColumns.isEmpty else { return [:] }
        
        let available = availableWidthForColumns()
        let weightBase: [FileColumn: CGFloat] = [
            .name: 6.0,
            .type: 2.1,
            .size: 1.4,
            .modified: 2.5
        ]
        let floorBase: [FileColumn: CGFloat] = [
            .name: 120,
            .type: 80,
            .size: 58,
            .modified: 102
        ]

        let weightSum = visibleColumns.reduce(CGFloat(0)) { $0 + (weightBase[$1] ?? 1) }
        guard weightSum > 0 else { return [:] }

        var resolved: [FileColumn: CGFloat] = [:]
        for column in visibleColumns {
            let proportional = available * (weightBase[column] ?? 1) / weightSum
            let floor = floorBase[column] ?? 48
            resolved[column] = max(proportional, floor)
        }

        var total = visibleColumns.reduce(CGFloat(0)) { $0 + (resolved[$1] ?? 0) }

        if total > available {
            var overflow = total - available
            let shrinkOrder = visibleColumns.sorted { lhs, rhs in
                (resolved[lhs] ?? 0) > (resolved[rhs] ?? 0)
            }

            for column in shrinkOrder where overflow > 0 {
                let floor = floorBase[column] ?? 48
                let current = resolved[column] ?? floor
                let reducible = max(current - floor, 0)
                guard reducible > 0 else { continue }
                let reduction = min(reducible, overflow)
                resolved[column] = current - reduction
                overflow -= reduction
            }

            total = visibleColumns.reduce(CGFloat(0)) { $0 + (resolved[$1] ?? 0) }
        }

        if total > available, total > 0 {
            let hardFloor: CGFloat = 40
            let scale = max(available / total, 0)
            for column in visibleColumns {
                resolved[column] = max((resolved[column] ?? hardFloor) * scale, hardFloor)
            }
            total = visibleColumns.reduce(CGFloat(0)) { $0 + (resolved[$1] ?? hardFloor) }
        }

        if total < available {
            let fillColumn = visibleColumns.contains(.name) ? FileColumn.name : visibleColumns.first!
            resolved[fillColumn, default: floorBase[fillColumn] ?? 48] += (available - total)
        }

        return resolved
    }

    private func sortOrder(for column: FileColumn) -> SortOrder {
        switch column {
        case .name: return .name
        case .type: return .type
        case .size: return .size
        case .modified: return .modified
        }
    }

    @ViewBuilder
    private func columnHeaderButton(for column: FileColumn) -> some View {
        Button(action: { sortBy(sortOrder(for: column)) }) {
            HStack(spacing: 4) {
                Text(column.title)
                    .font(paneSmallFont)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if sortOrder == sortOrder(for: column) {
                    Image(systemName: sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(paneTinyFont)
                }
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.borderless)
        .foregroundColor(.primary)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(dragOverColumn == column ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .onDrag {
            draggedColumn = column
            return NSItemProvider(object: column.rawValue as NSString)
        }
        .onDrop(of: [UTType.plainText], delegate: ColumnReorderDropDelegate(
            target: column,
            order: $columnOrder,
            dragged: $draggedColumn,
            dragOver: $dragOverColumn,
            onSave: saveColumnLayout
        ))
        .onTapGesture {
            onFocus()
        }
    }

    @ViewBuilder
    private func columnResizeHandle(for column: FileColumn) -> some View {
        Rectangle()
            .fill(FolderiumTheme.separator(isSoftDark: softDarkThemeEnabled))
            .frame(width: 5, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if resizingColumn == nil {
                            resizingColumn = column
                            resizeStartWidth = columnWidth(for: column)
                        }

                        guard resizingColumn == column else { return }
                        let start = resizeStartWidth ?? columnWidth(for: column)
                        let proposed = start + value.translation.width
                        let clamped = min(max(proposed, column.minWidth), maxAllowedWidth(for: column))
                        columnWidths[column] = clamped
                    }
                    .onEnded { _ in
                        resizingColumn = nil
                        resizeStartWidth = nil
                        saveColumnLayout()
                    }
            )
            .onTapGesture(count: 2) {
                columnWidths[column] = FileColumn.defaultWidths[column] ?? columnWidth(for: column)
                saveColumnLayout()
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
                        selectionCount: selection.count,
                        isPartOfSelection: selection.contains(file.url),
                        isStriped: index % 2 == 1,
                        isInlineRenaming: inlineRenamingURL == file.url,
                        inlineRenameText: Binding(
                            get: { inlineRenameText },
                            set: { inlineRenameText = $0 }
                        ),
                        visibleColumns: visibleColumns,
                        columnWidths: columnWidths,
                        resolvedColumnWidths: resolvedColumnWidths(),
                        onSelectWithModifiers: { isCommand, isShift in
                            handleRowClick(file.url, isCommandPressed: isCommand, isShiftPressed: isShift)
                        },
                        onDoubleClick: { handleDoubleClick(file) },
                        onCommitInlineRename: commitInlineRename,
                        onCancelInlineRename: cancelInlineRename,
                        onFileOperation: { 
                            loadFiles()
                            onRefresh()
                        },
                        onRecordMoveBatch: onRecordMoveBatch,
                        canPasteFromClipboard: canPasteFromClipboard(),
                        onPasteIntoFolder: { folderURL in
                            onPasteIntoPath(folderURL)
                        },
                        onBulkCompress: onBulkCompress,
                        onDropToFolder: { folderURL, providers in
                            handleDrop(providers: providers, destinationFolder: folderURL)
                        },
                        selectedURLsProvider: {
                            Array(selection).sorted { $0.path < $1.path }
                        },
                        onFocus: onFocus
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { providers in
            handleDrop(providers: providers, destinationFolder: nil)
        }
        .contentShape(Rectangle())
        .clipped()
        // Keep pane focus behavior without stealing first-click selection from rows.
        .simultaneousGesture(
            TapGesture().onEnded {
                onFocus()
            }
        )
        .contextMenu {
            EmptyAreaContextMenu(
                currentPath: path,
                canPasteFromClipboard: canPasteFromClipboard(),
                onPaste: {
                    onPasteIntoPath(nil)
                },
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

    private func toggleColumnVisibility(_ column: FileColumn) {
        if hiddenColumns.contains(column) {
            hiddenColumns.remove(column)
        } else {
            hiddenColumns.insert(column)
        }
        saveColumnLayout()
    }

    private func resetColumnsToDefault() {
        columnOrder = FileColumn.defaultOrder
        hiddenColumns = FileColumn.defaultHidden
        columnWidths = FileColumn.defaultWidths
        saveColumnLayout()
    }

    private func loadColumnLayout() {
        guard !columnLayoutRaw.isEmpty, let data = columnLayoutRaw.data(using: .utf8) else {
            columnOrder = FileColumn.defaultOrder
            hiddenColumns = FileColumn.defaultHidden
            columnWidths = FileColumn.defaultWidths
            return
        }

        guard let persisted = try? JSONDecoder().decode(PersistedColumnsLayout.self, from: data) else {
            columnOrder = FileColumn.defaultOrder
            hiddenColumns = FileColumn.defaultHidden
            columnWidths = FileColumn.defaultWidths
            return
        }

        var decodedOrder = persisted.order.compactMap(FileColumn.init(rawValue:))
        for column in FileColumn.defaultOrder where !decodedOrder.contains(column) {
            decodedOrder.append(column)
        }
        columnOrder = decodedOrder

        hiddenColumns = Set(persisted.hidden.compactMap(FileColumn.init(rawValue:)))

        var newWidths = FileColumn.defaultWidths
        for (key, width) in persisted.widths {
            if let column = FileColumn(rawValue: key) {
                newWidths[column] = max(CGFloat(width), column.minWidth)
            }
        }
        columnWidths = newWidths
    }

    private func saveColumnLayout() {
        let persisted = PersistedColumnsLayout(
            order: columnOrder.map(\.rawValue),
            hidden: hiddenColumns.map(\.rawValue),
            widths: Dictionary(uniqueKeysWithValues: columnWidths.map { ($0.key.rawValue, Double($0.value)) })
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        columnLayoutRaw = String(data: data, encoding: .utf8) ?? ""
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

    private func handleRowClick(_ url: URL, isCommandPressed: Bool, isShiftPressed: Bool) {
        let wasSingleSelected = selection.count == 1 && selection.contains(url)

        if inlineRenamingURL != nil && inlineRenamingURL != url {
            cancelInlineRename()
        }

        toggleSelectionWithModifier(url, isCommandPressed: isCommandPressed, isShiftPressed: isShiftPressed)
        keyboardSelectionFocus = url
        if !isCommandPressed && !isShiftPressed {
            keyboardSelectionAnchor = url
        } else if isShiftPressed, keyboardSelectionAnchor == nil {
            keyboardSelectionAnchor = url
        }

        guard !isCommandPressed, !isShiftPressed else {
            lastPlainClickURL = nil
            lastPlainClickTimestamp = nil
            return
        }

        guard wasSingleSelected else {
            lastPlainClickURL = url
            lastPlainClickTimestamp = Date()
            return
        }

        let now = Date()
        let interval = now.timeIntervalSince(lastPlainClickTimestamp ?? .distantPast)
        let minSlowSecondClickInterval: TimeInterval = 0.45
        let maxSlowSecondClickInterval: TimeInterval = 2.0

        if lastPlainClickURL == url,
           interval >= minSlowSecondClickInterval,
           interval <= maxSlowSecondClickInterval {
            beginInlineRename(for: url)
            lastPlainClickURL = nil
            lastPlainClickTimestamp = nil
        } else {
            lastPlainClickURL = url
            lastPlainClickTimestamp = now
        }
    }

    private func beginInlineRename(for url: URL) {
        inlineRenamingURL = url
        inlineRenameText = url.lastPathComponent
    }

    private func commitInlineRename() {
        guard let sourceURL = inlineRenamingURL else { return }
        let newName = inlineRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            cancelInlineRename()
            return
        }

        let destinationURL = sourceURL.deletingLastPathComponent().appendingPathComponent(newName)
        guard destinationURL != sourceURL else {
            cancelInlineRename()
            return
        }

        do {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            onRecordMoveBatch("Rename", [(from: sourceURL, to: destinationURL)])
            selection = [destinationURL]
            cancelInlineRename()
            loadFiles()
            onRefresh()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Rename Failed"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .warning
            alert.runModal()
            cancelInlineRename()
        }
    }

    private func cancelInlineRename() {
        inlineRenamingURL = nil
        inlineRenameText = ""
    }
    
    private func selectRange(to url: URL) {
        guard let anchorURL = keyboardSelectionAnchor ?? selection.first else {
            selection = [url]
            keyboardSelectionAnchor = url
            keyboardSelectionFocus = url
            return
        }
        
        // Get all files in current directory
        let allFiles = files.map { $0.url }
        guard let firstIndex = allFiles.firstIndex(of: anchorURL),
              let lastIndex = allFiles.firstIndex(of: url) else {
            selection = [url]
            keyboardSelectionAnchor = url
            keyboardSelectionFocus = url
            return
        }
        
        // Select range from first to last
        let startIndex = min(firstIndex, lastIndex)
        let endIndex = max(firstIndex, lastIndex)
        let range = allFiles[startIndex...endIndex]
        selection = Set(range)
        keyboardSelectionAnchor = anchorURL
        keyboardSelectionFocus = url
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
                    options: showHiddenFiles ? [] : [.skipsHiddenFiles]
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
    
    private func runAdvancedSearch() {
        let query = advancedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            advancedSearchResults = []
            advancedSearchError = nil
            return
        }
        
        advancedSearchTask?.cancel()
        advancedSearchIsRunning = true
        advancedSearchError = nil
        advancedSearchResults = []
        advancedSelectedResult = nil
        
        let options = SearchOptions(
            searchType: advancedSearchRegex ? .regex : .contains,
            caseSensitive: advancedSearchCaseSensitive,
            maxResults: 1000,
            includeHidden: showHiddenFiles
        )
        
        let fileTypes = advancedSearchFileTypes
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        
        advancedSearchTask = Task {
            do {
                let results: [SearchResult]
                if advancedSearchInContents {
                    results = try await SearchManager.shared.runContentSearch(
                        query: query,
                        in: path,
                        fileTypes: fileTypes,
                        options: options
                    )
                } else {
                    results = try await SearchManager.shared.runLocalSearch(
                        query: query,
                        in: path,
                        options: options
                    )
                }
                
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    advancedSearchResults = results.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    advancedSearchIsRunning = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    advancedSearchError = error.localizedDescription
                    advancedSearchIsRunning = false
                }
            }
        }
    }
    
    private func openSearchResult(_ result: SearchResult) {
        onFocus()
        if result.isDirectory {
            path = result.url
            selection = []
            advancedSelectedResult = result.url
            return
        }
        
        path = result.url.deletingLastPathComponent()
        selection = [result.url]
        keyboardSelectionAnchor = result.url
        keyboardSelectionFocus = result.url
        advancedSelectedResult = result.url
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
        publishVisibleURLsForShortcuts()
    }
    
    private func publishVisibleURLsForShortcuts() {
        if isAdvancedSearchEnabled {
            onDisplayedURLsChange(advancedSearchResults.map(\.url))
        } else {
            onDisplayedURLsChange(displayedFiles.map(\.url))
        }
    }
    
    private func moveSelectionByArrow(delta: Int) {
        guard !displayedFiles.isEmpty else { return }
        
        let orderedURLs = displayedFiles.map(\.url)
        let isShiftPressed = NSEvent.modifierFlags.contains(.shift)

        let fallbackCurrent: URL = {
            if let focus = keyboardSelectionFocus {
                return focus
            }
            if let selected = selection.first {
                return selected
            }
            return delta > 0 ? orderedURLs.first! : orderedURLs.last!
        }()

        guard let currentIndex = orderedURLs.firstIndex(of: fallbackCurrent) else {
            let initial = delta > 0 ? orderedURLs.first! : orderedURLs.last!
            selection = [initial]
            keyboardSelectionAnchor = initial
            keyboardSelectionFocus = initial
            onFocus()
            return
        }

        let nextIndex = min(max(currentIndex + delta, 0), orderedURLs.count - 1)
        let nextURL = orderedURLs[nextIndex]

        if isShiftPressed {
            let anchor = keyboardSelectionAnchor ?? fallbackCurrent
            if let anchorIndex = orderedURLs.firstIndex(of: anchor) {
                let startIndex = min(anchorIndex, nextIndex)
                let endIndex = max(anchorIndex, nextIndex)
                selection = Set(orderedURLs[startIndex...endIndex])
                keyboardSelectionAnchor = anchor
                keyboardSelectionFocus = nextURL
            } else {
                selection = [nextURL]
                keyboardSelectionAnchor = nextURL
                keyboardSelectionFocus = nextURL
            }
        } else {
            selection = [nextURL]
            keyboardSelectionAnchor = nextURL
            keyboardSelectionFocus = nextURL
        }
        
        onFocus()
    }
    
    private func startDirectoryWatcher() {
        stopDirectoryWatcher()
        
        directoryWatcher = DirectoryWatcher(directoryURL: path) {
            Task { @MainActor in
                scheduleFilesystemRefresh()
            }
        }
        directoryWatcher?.start()
    }
    
    private func stopDirectoryWatcher() {
        directoryWatcher?.stop()
        directoryWatcher = nil
    }
    
    private func scheduleFilesystemRefresh() {
        watcherDebounceTask?.cancel()
        watcherDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            loadFiles()
        }
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
    
    private func commitPathInput() -> Bool {
        let trimmedPath = pathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            pathInput = path.path
            return false
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
            return false
        }
        
        path = resolvedURL
        errorMessage = nil
        return true
    }
    
    private func handleDrop(providers: [NSItemProvider], destinationFolder: URL?) -> Bool {
        print("Drop received with \(providers.count) providers")
        let destinationURL = destinationFolder ?? path
        
        Task {
            var sourceURLs = Set<URL>()
            var hasInternalPayload = false
            
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    do {
                        let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil)
                        if let text = plainText(from: item),
                           let decodedURLs = decodeInternalDragPayload(text) {
                            decodedURLs.forEach { sourceURLs.insert($0) }
                            hasInternalPayload = true
                            continue
                        }
                    } catch {
                        print("Error loading plain-text drop payload: \(error)")
                    }
                }
                
                if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                    do {
                        if let data = try await provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) as? Data,
                           let url = URL(dataRepresentation: data, relativeTo: nil) {
                            sourceURLs.insert(url)
                            print("Found file URL: \(url.lastPathComponent)")
                        }
                    } catch {
                        print("Error loading file URL: \(error)")
                    }
                }
            }
            
            if !sourceURLs.isEmpty {
                await MainActor.run {
                    let optionPressed = NSEvent.modifierFlags.contains(.option)
                    // Internal drags default to move; external file drags default to copy.
                    let operation: DragFileOperation
                    if optionPressed {
                        operation = hasInternalPayload ? .copy : .move
                    } else {
                        operation = hasInternalPayload ? .move : .copy
                    }
                    performDropOperation(
                        sourceURLs: Array(sourceURLs),
                        destinationFolder: destinationURL,
                        operation: operation
                    )
                }
            }
        }
        
        return true
    }

    private func plainText(from item: NSSecureCoding) -> String? {
        if let string = item as? String {
            return string
        }
        if let attributed = item as? NSAttributedString {
            return attributed.string
        }
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func decodeInternalDragPayload(_ text: String) -> [URL]? {
        let lines = text.split(separator: "\n").map(String.init)
        guard lines.first == Self.internalDragPrefix else { return nil }
        let paths = lines.dropFirst().filter { !$0.isEmpty }
        guard !paths.isEmpty else { return [] }
        return paths.map { URL(fileURLWithPath: $0) }
    }
    
    private func performDropOperation(sourceURLs: [URL], destinationFolder: URL, operation: DragFileOperation) {
        print("Performing \(operation == .move ? "move" : "copy") operation with \(sourceURLs.count) files to \(destinationFolder.path)")
        
        Task {
            do {
                var movedPairs: [(from: URL, to: URL)] = []
                for sourceURL in sourceURLs {
                    let destinationURL = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
                    
                    // Prevent invalid no-op/self/descendant moves.
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) {
                        if destinationURL.path == sourceURL.path {
                            print("Skipping no-op move for \(sourceURL.lastPathComponent)")
                            continue
                        }
                        if isDirectory.boolValue && destinationURL.path.hasPrefix(sourceURL.path + "/") {
                            print("Skipping invalid move into descendant for \(sourceURL.lastPathComponent)")
                            continue
                        }
                    }
                    
                    guard let finalDestinationURL = await resolveDropConflict(sourceURL: sourceURL, destinationURL: destinationURL) else {
                        continue
                    }
                    
                    switch operation {
                    case .move:
                        try FileManager.default.moveItem(at: sourceURL, to: finalDestinationURL)
                        movedPairs.append((from: sourceURL, to: finalDestinationURL))
                        print("Moved: \(sourceURL.lastPathComponent) to \(finalDestinationURL.lastPathComponent)")
                    case .copy:
                        try FileManager.default.copyItem(at: sourceURL, to: finalDestinationURL)
                        print("Copied: \(sourceURL.lastPathComponent) to \(finalDestinationURL.lastPathComponent)")
                    }
                }
                
                await MainActor.run {
                    // Refresh the file list
                    loadFiles()
                    onRefresh()
                    if operation == .move, !movedPairs.isEmpty {
                        onRecordMoveBatch("Move via Drag and Drop", movedPairs)
                    }
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
                            .font(paneBaseFont)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(FolderiumTheme.controlBackground(isSoftDark: softDarkThemeEnabled))
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
                        .font(paneBaseFont)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(FolderiumTheme.controlBackground(isSoftDark: softDarkThemeEnabled))
                .cornerRadius(4)
                .shadow(radius: 2)
            )
        } else {
            return AnyView(
                HStack {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                    Text("\(selection.count) items")
                        .font(paneBaseFont)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(FolderiumTheme.controlBackground(isSoftDark: softDarkThemeEnabled))
                .cornerRadius(4)
                .shadow(radius: 2)
            )
        }
    }
}

private struct ColumnReorderDropDelegate: DropDelegate {
    let target: FilePaneView.FileColumn
    @Binding var order: [FilePaneView.FileColumn]
    @Binding var dragged: FilePaneView.FileColumn?
    @Binding var dragOver: FilePaneView.FileColumn?
    let onSave: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target,
              let from = order.firstIndex(of: dragged),
              let to = order.firstIndex(of: target) else { return }

        dragOver = target

        if order[to] != dragged {
            withAnimation(.easeInOut(duration: 0.12)) {
                order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dragOver == target {
            dragOver = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let didDrop = dragged != nil
        dragged = nil
        dragOver = nil
        if didDrop {
            onSave()
        }
        return didDrop
    }
}

private struct PinnedLocationDropDelegate: DropDelegate {
    let targetPath: String
    @Binding var pinnedPaths: [String]
    @Binding var draggedPath: String?

    func dropEntered(info: DropInfo) {
        guard let draggedPath,
              draggedPath != targetPath,
              let fromIndex = pinnedPaths.firstIndex(of: draggedPath),
              let toIndex = pinnedPaths.firstIndex(of: targetPath) else { return }

        if pinnedPaths[toIndex] != draggedPath {
            withAnimation(.easeInOut(duration: 0.12)) {
                pinnedPaths.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let dropped = draggedPath != nil
        draggedPath = nil
        return dropped
    }

    func dropExited(info: DropInfo) {}
}

struct FileRowView: View {
    @AppStorage("folderium.softDarkThemeEnabled") private var softDarkThemeEnabled: Bool = false
    @AppStorage("folderium.globalFontSize") private var globalFontSize: Double = 12
    @FocusState private var inlineRenameFieldFocused: Bool
    @State private var isNameTooltipVisible: Bool = false
    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    let file: FileItem
    let isSelected: Bool
    let selectionCount: Int
    let isPartOfSelection: Bool
    let isStriped: Bool
    let isInlineRenaming: Bool
    @Binding var inlineRenameText: String
    let visibleColumns: [FilePaneView.FileColumn]
    let columnWidths: [FilePaneView.FileColumn: CGFloat]
    let resolvedColumnWidths: [FilePaneView.FileColumn: CGFloat]
    let onSelectWithModifiers: (Bool, Bool) -> Void
    let onDoubleClick: () -> Void
    let onCommitInlineRename: () -> Void
    let onCancelInlineRename: () -> Void
    let onFileOperation: () -> Void
    let onRecordMoveBatch: (_ title: String, _ pairs: [(from: URL, to: URL)]) -> Void
    let canPasteFromClipboard: Bool
    let onPasteIntoFolder: (URL) -> Void
    let onBulkCompress: () -> Void
    let onDropToFolder: (URL?, [NSItemProvider]) -> Bool
    let selectedURLsProvider: () -> [URL]
    let onFocus: () -> Void
    private static let internalDragPrefix = "folderium-internal-drag-v1"
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.3)
        } else if isStriped {
            return FolderiumTheme.stripedRowBackground(isSoftDark: softDarkThemeEnabled)
        } else {
            return Color.clear
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleColumns, id: \.self) { column in
                columnValueView(for: column)
                    .frame(width: width(for: column), alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .contentShape(Rectangle())
        .clipped()
        .overlay {
            RowMouseCaptureView { event in
                let modifierFlags = event.modifierFlags
                let isCommandPressed = modifierFlags.contains(.command)
                let isShiftPressed = modifierFlags.contains(.shift)
                let shouldPreserveMultiSelection =
                    !isCommandPressed &&
                    !isShiftPressed &&
                    selectionCount > 1 &&
                    isPartOfSelection

                if !shouldPreserveMultiSelection {
                    onSelectWithModifiers(isCommandPressed, isShiftPressed)
                }
                onFocus()

                if event.clickCount >= 2 {
                    onDoubleClick()
                }
            }
        }
        .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { providers in
            // If dropped over a non-folder row, fall back to pane's current path.
            onDropToFolder(file.isDirectory ? file.url : nil, providers)
        }
        .contextMenu {
            FileContextMenu(
                file: file, 
                currentSelectionCount: selectionCount,
                onFileOperation: onFileOperation, 
                onSelect: {
                    onSelectWithModifiers(false, false)
                },
                onRecordMoveBatch: onRecordMoveBatch,
                canPasteFromClipboard: canPasteFromClipboard,
                onPasteIntoFolder: onPasteIntoFolder,
                onBulkCompress: onBulkCompress
            )
        }
        .onDrag {
            let draggedURLs = dragSelectionURLs()
            let payload = Self.internalDragPrefix + "\n" + draggedURLs.map(\.path).joined(separator: "\n")
            return NSItemProvider(object: payload as NSString)
        } preview: {
            dragPreview
        }
        .onAppear {
            if isInlineRenaming {
                inlineRenameFieldFocused = true
            }
        }
        .onChange(of: isInlineRenaming) { _, newValue in
            inlineRenameFieldFocused = newValue
            if newValue {
                isNameTooltipVisible = false
            }
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "--" }
        return Self.rowDateFormatter.string(from: date)
    }

    private func width(for column: FilePaneView.FileColumn) -> CGFloat {
        if let resolved = resolvedColumnWidths[column] {
            return max(resolved, column.minWidth)
        }
        let defaultWidth = FilePaneView.FileColumn.defaultWidths[column] ?? 120
        return max(columnWidths[column] ?? defaultWidth, column.minWidth)
    }

    @ViewBuilder
    private func columnValueView(for column: FilePaneView.FileColumn) -> some View {
        switch column {
        case .name:
            HStack {
                Image(systemName: file.iconName)
                    .foregroundColor(file.iconColor)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 16)

                if isInlineRenaming {
                    TextField("", text: $inlineRenameText)
                        .textFieldStyle(.roundedBorder)
                        .focused($inlineRenameFieldFocused)
                        .onSubmit {
                            onCommitInlineRename()
                        }
                        .onExitCommand {
                            onCancelInlineRename()
                        }
                } else {
                    Text(file.name)
                        .font(.system(size: CGFloat(globalFontSize)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .onHover { hovering in
                            isNameTooltipVisible = hovering
                        }
                        .popover(isPresented: $isNameTooltipVisible, arrowEdge: .bottom) {
                            Text(file.url.lastPathComponent)
                                .font(.system(size: max(globalFontSize - 1, 10)))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                }
            }
        case .type:
            Text(file.localizedType)
                .font(.system(size: CGFloat(globalFontSize)))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        case .size:
            Text(file.isDirectory ? "--" : file.sizeString)
                .font(.system(size: CGFloat(globalFontSize)))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .modified:
            Text(formatDate(file.modificationDate))
                .font(.system(size: CGFloat(globalFontSize)))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func dragSelectionURLs() -> [URL] {
        if isPartOfSelection, selectionCount > 0 {
            return selectedURLsProvider()
        }
        return [file.url]
    }

    @ViewBuilder
    private var dragPreview: some View {
        let draggedURLs = dragSelectionURLs()
        HStack(spacing: 8) {
            Image(systemName: draggedURLs.count > 1 ? "doc.on.doc.fill" : file.iconName)
                .foregroundColor(draggedURLs.count > 1 ? .blue : file.iconColor)
                .symbolRenderingMode(.hierarchical)

            if draggedURLs.count > 1 {
                Text("\(draggedURLs.count) items")
                    .font(.system(size: max(globalFontSize - 1, 11), weight: .semibold))
            } else {
                Text(file.name)
                    .font(.system(size: max(globalFontSize - 1, 11), weight: .semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(FolderiumTheme.controlBackground(isSoftDark: softDarkThemeEnabled))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
    }
}

private struct SearchResultRowView: View {
    @AppStorage("folderium.softDarkThemeEnabled") private var softDarkThemeEnabled: Bool = false
    @AppStorage("folderium.globalFontSize") private var globalFontSize: Double = 12
    let result: SearchResult
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: result.isDirectory ? "folder.fill" : "doc")
                    .foregroundColor(result.isDirectory ? .blue : .secondary)
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.name)
                        .font(.system(size: CGFloat(globalFontSize)))
                        .lineLimit(1)
                    
                    Text(result.url.path)
                        .font(.system(size: CGFloat(max(globalFontSize - 2, 10))))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if !result.isDirectory {
                    Text(result.sizeString)
                        .font(.system(size: CGFloat(max(globalFontSize - 2, 10))))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            .contentShape(Rectangle())
            .overlay {
                RowMouseCaptureView { event in
                    onSelect()
                    if event.clickCount >= 2 {
                        onOpen()
                    }
                }
            }
            
            Divider()
                .background(FolderiumTheme.separator(isSoftDark: softDarkThemeEnabled))
        }
    }
}

private struct RowMouseCaptureView: NSViewRepresentable {
    let onMouseDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> MouseCaptureNSView {
        let view = MouseCaptureNSView()
        view.onMouseDown = onMouseDown
        return view
    }

    func updateNSView(_ nsView: MouseCaptureNSView, context: Context) {
        nsView.onMouseDown = onMouseDown
    }

    final class MouseCaptureNSView: NSView {
        var onMouseDown: ((NSEvent) -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            self
        }

        override func mouseDown(with event: NSEvent) {
            onMouseDown?(event)
        }

        // Let right-click pass through so SwiftUI context menus still work.
        override func rightMouseDown(with event: NSEvent) {
            nextResponder?.rightMouseDown(with: event)
        }
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
    let currentSelectionCount: Int
    let onFileOperation: () -> Void
    let onSelect: () -> Void
    let onRecordMoveBatch: (_ title: String, _ pairs: [(from: URL, to: URL)]) -> Void
    let canPasteFromClipboard: Bool
    let onPasteIntoFolder: (URL) -> Void
    let onBulkCompress: () -> Void
    
    enum ActionType {
        case delete, moveToTrash
    }
    
    private var openWithApplications: [URL] {
        guard !file.isDirectory else { return [] }
        return NSWorkspace.shared
            .urlsForApplications(toOpen: file.url)
            .filter { $0.pathExtension.lowercased() == "app" }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Open") {
                onSelect()
                openFile()
            }
            
            if !file.isDirectory {
                Menu("Open With") {
                    if openWithApplications.isEmpty {
                        Text("No compatible apps found")
                    } else {
                        ForEach(Array(openWithApplications.prefix(12)), id: \.path) { appURL in
                            Button(displayName(for: appURL)) {
                                onSelect()
                                openFile(with: appURL)
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button("Other...") {
                        onSelect()
                        openFileWithOtherAppPicker()
                    }
                }
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
            
            if file.isDirectory {
                Button("Paste Into Folder") {
                    onPasteIntoFolder(file.url)
                }
                .disabled(!canPasteFromClipboard)
            }
            
            Divider()
            
            Button(currentSelectionCount > 1 ? "Compress Selected (\(currentSelectionCount))" : "Compress") {
                if currentSelectionCount > 1 {
                    onBulkCompress()
                } else {
                    compressFile()
                }
            }
            
            let archiveSupport = ArchiveManager.shared.archiveSupportInfo(for: file.url)
            if archiveSupport.isArchive {
                Button(archiveSupport.canExtract
                    ? "Extract (\(archiveSupport.formatLabel) - Supported)"
                    : "Extract (\(archiveSupport.formatLabel) - Unsupported)") {
                    extractFile()
                }
                .disabled(!archiveSupport.canExtract)
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
    
    private func openFile(with applicationURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([file.url], withApplicationAt: applicationURL, configuration: configuration) { _, error in
            if let error {
                print("Error opening file with selected app: \(error)")
            }
        }
    }
    
    private func openFileWithOtherAppPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose an application to open this file."
        panel.prompt = "Open"
        
        if panel.runModal() == .OK, let appURL = panel.url {
            openFile(with: appURL)
        }
    }
    
    private func displayName(for appURL: URL) -> String {
        FileManager.default.displayName(atPath: appURL.path)
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
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Extraction Failed"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "OK")
                    alert.alertStyle = .warning
                    alert.runModal()
                }
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
                    onRecordMoveBatch("Rename", [(from: file.url, to: newURL)])
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

final class DirectoryWatcher {
    private let directoryURL: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    
    init(directoryURL: URL, onChange: @escaping () -> Void) {
        self.directoryURL = directoryURL
        self.onChange = onChange
    }
    
    func start() {
        stop()
        
        fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        
        let queue = DispatchQueue(label: "folderium.directory-watcher", qos: .utility)
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: queue
        )
        
        source?.setEventHandler { [weak self] in
            self?.onChange()
        }
        
        source?.setCancelHandler { [fileDescriptor] in
            if fileDescriptor >= 0 {
                close(fileDescriptor)
            }
        }
        
        source?.resume()
    }
    
    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }
    
    deinit {
        stop()
    }
}

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.window = nsView.window
        }
    }
}

// MARK: - Empty Area Context Menu

struct EmptyAreaContextMenu: View {
    let currentPath: URL
    let canPasteFromClipboard: Bool
    let onPaste: () -> Void
    let onFileOperation: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("New Folder") {
                createNewFolder()
            }
            
            Button("New File") {
                createNewFileWithDialog()
            }
            
            Button("Paste") {
                onPaste()
            }
            .disabled(!canPasteFromClipboard)
            
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
    @AppStorage("folderium.softDarkThemeEnabled") private var softDarkThemeEnabled: Bool = false
    @AppStorage("folderium.globalFontSize") private var globalFontSize: Double = 12
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

    private var statusFont: Font {
        .system(size: CGFloat(max(globalFontSize - 2, 10)))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack {
                // File and folder counts
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(statusFont)
                            .foregroundColor(.blue)
                        Text("\(folderCount)")
                            .font(statusFont)
                            .fontWeight(.medium)
                        Text("folders")
                            .font(statusFont)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "doc")
                            .font(statusFont)
                            .foregroundColor(.secondary)
                        Text("\(fileCount)")
                            .font(statusFont)
                            .fontWeight(.medium)
                        Text("files")
                            .font(statusFont)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Total size
                HStack(spacing: 4) {
                    Image(systemName: "externaldrive")
                        .font(statusFont)
                        .foregroundColor(.orange)
                    Text(totalSizeString)
                        .font(statusFont)
                        .fontWeight(.medium)
                    Text("total")
                        .font(statusFont)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(FolderiumTheme.controlBackground(isSoftDark: softDarkThemeEnabled))
            
            // Bottom border
            Divider()
        }
    }
}

#Preview {
    DualPaneView()
}
