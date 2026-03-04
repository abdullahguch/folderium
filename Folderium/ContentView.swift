import SwiftUI
import AVKit
import PDFKit

struct ContentView: View {
    private let defaultPreviewWidthRatio: CGFloat = 0.34
    @AppStorage("folderium.softDarkThemeEnabled") private var softDarkThemeEnabled: Bool = false
    @AppStorage("folderium.globalFontSize") private var globalFontSize: Double = 12
    @AppStorage("folderium.isPreviewVisible") private var isPreviewVisible: Bool = false
    @AppStorage("folderium.isNavigationPaneVisible") private var isNavigationPaneVisible: Bool = true
    @State private var selectedFiles: Set<URL> = []
    @State private var previewSelection: Set<URL> = []
    @State private var previewWidthRatio: CGFloat = 0.34
    @State private var previewDragStartWidth: CGFloat?
    @State private var previewUpdateTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(isNavigationPaneVisible ? "Hide Navigation" : "Show Navigation") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isNavigationPaneVisible.toggle()
                    }
                }
                .buttonStyle(.bordered)
                
                Button(isPreviewVisible ? "Hide Preview" : "Show Preview") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isPreviewVisible {
                            isPreviewVisible = false
                        } else {
                            previewWidthRatio = max(previewWidthRatio, defaultPreviewWidthRatio)
                            isPreviewVisible = true
                        }
                    }
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FolderiumTheme.controlBackground(isSoftDark: softDarkThemeEnabled))
            
            Divider()
            
            GeometryReader { geometry in
                let previewDividerWidth: CGFloat = isPreviewVisible ? 6 : 0
                let availableContentWidth = max(geometry.size.width - previewDividerWidth, 0)
                let dualPaneWidth = isPreviewVisible
                    ? availableContentWidth * (1 - previewWidthRatio)
                    : availableContentWidth
                let previewPaneWidth = availableContentWidth * previewWidthRatio

                HStack(spacing: 0) {
                    // Dual pane content
                    DualPaneView(
                        onSelectionChange: { selection in
                            if isPreviewVisible {
                                selectedFiles = selection
                            } else if !selectedFiles.isEmpty {
                                selectedFiles = []
                            }
                        },
                        showNavigationPane: $isNavigationPaneVisible,
                        isSinglePaneMode: isPreviewVisible
                    )
                    .frame(width: dualPaneWidth)
                    
                    if isPreviewVisible {
                        Rectangle()
                            .fill(FolderiumTheme.separator(isSoftDark: softDarkThemeEnabled))
                            .frame(width: previewDividerWidth)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 2)
                                    .onChanged { value in
                                        let totalWidth = availableContentWidth
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
                            .frame(width: previewPaneWidth)
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
        .font(.system(size: globalFontSize))
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
    @State private var pdfDocument: PDFDocument?
    @State private var textPreview: String?
    @State private var mediaPlayer: AVPlayer?
    @State private var mediaKindLabel: String?
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
                } else if let pdfDocument = pdfDocument {
                    PDFPreviewView(document: pdfDocument)
                        .frame(height: 360)
                        .cornerRadius(8)
                } else if let textPreview = textPreview {
                    ScrollView {
                        Text(textPreview)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .frame(height: 300)
                    .background(FolderiumTheme.windowBackground(isSoftDark: softDarkThemeEnabled))
                    .cornerRadius(8)
                } else if let mediaPlayer = mediaPlayer {
                    VStack(spacing: 8) {
                        if let mediaKindLabel {
                            Text(mediaKindLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        VideoPlayer(player: mediaPlayer)
                            .frame(height: 220)
                            .cornerRadius(8)
                    }
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
        .onDisappear {
            mediaPlayer?.pause()
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
        clearPreviewState()
        
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg", "webp"].contains(pathExtension) {
            isLoading = true
            
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
            return
        }
        
        if pathExtension == "pdf" {
            isLoading = true
            DispatchQueue.global(qos: .userInitiated).async {
                let document = PDFDocument(url: file)
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let document {
                        self.pdfDocument = document
                    } else {
                        self.errorMessage = "Could not load PDF preview"
                    }
                }
            }
            return
        }
        
        if ["txt", "md", "json", "xml", "yaml", "yml", "csv", "log", "swift", "js", "ts", "tsx", "jsx", "py", "java", "c", "cpp", "h", "hpp", "rs", "go", "sh", "html", "css"].contains(pathExtension) {
            isLoading = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let rawData = try Data(contentsOf: file, options: .mappedIfSafe)
                    let maxBytes = min(rawData.count, 220_000)
                    let sliced = rawData.prefix(maxBytes)
                    let decoded = String(data: Data(sliced), encoding: .utf8)
                        ?? String(decoding: sliced, as: UTF8.self)
                    let limited = decoded.count > 16_000 ? String(decoded.prefix(16_000)) + "\n\n... (truncated)" : decoded
                    
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.textPreview = limited
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "Could not load text preview"
                    }
                }
            }
            return
        }
        
        if ["mp4", "mov", "m4v", "avi", "mkv", "webm", "mp3", "wav", "aac", "flac", "m4a", "ogg"].contains(pathExtension) {
            mediaPlayer = AVPlayer(url: file)
            mediaKindLabel = ["mp3", "wav", "aac", "flac", "m4a", "ogg"].contains(pathExtension) ? "Audio Preview" : "Video Preview"
            return
        }
    }
    
    private func clearPreviewState() {
        image = nil
        pdfDocument = nil
        textPreview = nil
        mediaPlayer?.pause()
        mediaPlayer = nil
        mediaKindLabel = nil
        errorMessage = nil
        isLoading = false
    }
}

struct PDFPreviewView: NSViewRepresentable {
    let document: PDFDocument
    
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displaysPageBreaks = true
        view.displayMode = .singlePageContinuous
        return view
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
    }
}

#Preview {
    ContentView()
}
