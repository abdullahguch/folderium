import SwiftUI

struct ContentView: View {
    private let defaultPreviewWidthRatio: CGFloat = 0.22
    @AppStorage("folderium.softDarkThemeEnabled") private var softDarkThemeEnabled: Bool = false
    @AppStorage("folderium.isPreviewVisible") private var isPreviewVisible: Bool = true
    @AppStorage("folderium.isNavigationPaneVisible") private var isNavigationPaneVisible: Bool = true
    @State private var selectedFiles: Set<URL> = []
    @State private var previewSelection: Set<URL> = []
    @State private var previewWidthRatio: CGFloat = 0.22
    @State private var previewDragStartWidth: CGFloat?
    @State private var previewUpdateTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(isNavigationPaneVisible ? "Hide Navigation" : "Show Navigation") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isNavigationPaneVisible.toggle()
                    }
                }
                .buttonStyle(.bordered)
                
                Button(isPreviewVisible ? "Hide Preview" : "Show Preview") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPreviewVisible.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(FolderiumTheme.controlBackground(isSoftDark: softDarkThemeEnabled))
            
            Divider()
            
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Dual pane content
                    DualPaneView(
                        onSelectionChange: { selection in
                            selectedFiles = selection
                        },
                        showNavigationPane: $isNavigationPaneVisible
                    )
                    .frame(width: isPreviewVisible ? geometry.size.width * (1 - previewWidthRatio) : geometry.size.width)
                    
                    if isPreviewVisible {
                        Rectangle()
                            .fill(FolderiumTheme.separator(isSoftDark: softDarkThemeEnabled))
                            .frame(width: 6)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 2)
                                    .onChanged { value in
                                        let totalWidth = geometry.size.width
                                        guard totalWidth > 0 else { return }
                                        let currentPreviewWidth = totalWidth * previewWidthRatio
                                        if previewDragStartWidth == nil {
                                            previewDragStartWidth = currentPreviewWidth
                                        }
                                        let baseWidth = previewDragStartWidth ?? currentPreviewWidth
                                        let proposedPreviewWidth = baseWidth - value.translation.width
                                        let minPreviewWidth = max(220, totalWidth * 0.15)
                                        let maxPreviewWidth = totalWidth * 0.45
                                        let clamped = min(max(proposedPreviewWidth, minPreviewWidth), maxPreviewWidth)
                                        previewWidthRatio = clamped / totalWidth
                                    }
                                    .onEnded { _ in
                                        previewDragStartWidth = nil
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    previewWidthRatio = defaultPreviewWidthRatio
                                }
                            }
                        
                        // Preview pane
                        FilePreviewView(selectedFiles: Array(previewSelection))
                            .frame(width: geometry.size.width * previewWidthRatio)
                            .id("preview-\(previewSelection.count)")
                    }
                }
            }
        }
        .onAppear {
            previewSelection = selectedFiles
        }
        .onChange(of: selectedFiles) { _, newValue in
            previewUpdateTask?.cancel()
            previewUpdateTask = Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    previewSelection = newValue
                }
            }
        }
        .background(FolderiumTheme.windowBackground(isSoftDark: softDarkThemeEnabled))
        .preferredColorScheme(softDarkThemeEnabled ? .dark : .light)
    }
}

struct TabView: View {
    let tab: FileTab
    let isSelected: Bool
    let onClose: () -> Void
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.caption)
            
            Text(tab.name)
                .font(.caption)
                .lineLimit(1)
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .opacity(0.6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(isSelected ? Color.accentColor : Color.clear)
        .foregroundColor(isSelected ? .white : .primary)
        .cornerRadius(4)
        .onTapGesture {
            onSelect()
        }
    }
}

struct FilePreviewView: View {
    let selectedFiles: [URL]
    @AppStorage("folderium.softDarkThemeEnabled") private var softDarkThemeEnabled: Bool = false
    
    var body: some View {
        VStack {
            if selectedFiles.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No file selected")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Select a file to view its preview")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(selectedFiles, id: \.self) { file in
                            FilePreviewItem(file: file)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FolderiumTheme.windowBackground(isSoftDark: softDarkThemeEnabled))
    }
}

struct FilePreviewItem: View {
    let file: URL
    @AppStorage("folderium.softDarkThemeEnabled") private var softDarkThemeEnabled: Bool = false
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // File name
            Text(file.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
            
            // File info
            HStack {
                Text(file.pathExtension.uppercased())
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
                
                Spacer()
                
                if let size = getFileSize() {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Preview content
            Group {
                if isLoading {
                    VStack {
                        ProgressView()
                        Text("Loading preview...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 200)
                } else if let errorMessage = errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundColor(.orange)
                        Text("Preview Error")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(height: 200)
                } else if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .cornerRadius(8)
                } else {
                    VStack {
                        Image(systemName: getFileIcon())
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No preview available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 200)
                }
            }
            .frame(maxWidth: .infinity)
            .background(FolderiumTheme.controlBackground(isSoftDark: softDarkThemeEnabled))
            .cornerRadius(8)
        }
        .padding()
        .background(FolderiumTheme.cardBackground(isSoftDark: softDarkThemeEnabled))
        .cornerRadius(12)
        .onAppear {
            loadPreview()
        }
    }
    
    private func getFileSize() -> Int64? {
        do {
            let attributes = try file.resourceValues(forKeys: [.fileSizeKey])
            return Int64(attributes.fileSize ?? 0)
        } catch {
            return nil
        }
    }
    
    private func getFileIcon() -> String {
        let pathExtension = file.pathExtension.lowercased()
        switch pathExtension {
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg", "webp":
            return "photo"
        case "mp4", "avi", "mov", "wmv", "flv", "webm", "mkv":
            return "video"
        case "mp3", "wav", "aac", "flac", "ogg", "m4a":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "txt", "md", "rtf":
            return "doc.text"
        case "zip", "rar", "7z", "tar", "gz":
            return "archivebox"
        case "app":
            return "app"
        default:
            return "doc"
        }
    }
    
    private func loadPreview() {
        let pathExtension = file.pathExtension.lowercased()
        
        // Only load image previews for now
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg", "webp"].contains(pathExtension) {
            isLoading = true
            errorMessage = nil
            
            DispatchQueue.global(qos: .userInitiated).async {
                let loadedImage = NSImage(contentsOf: file)
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let loadedImage = loadedImage {
                        self.image = loadedImage
                    } else {
                        self.errorMessage = "Could not load image"
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
