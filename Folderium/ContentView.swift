import SwiftUI

struct ContentView: View {
    @State private var selectedFiles: Set<URL> = []
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Dual pane content - takes 4/5 of the width
                DualPaneView(onSelectionChange: { selection in
                    selectedFiles = selection
                })
                .frame(width: geometry.size.width * 0.8) // 4/5 of the width
                
                Divider()
                
                // Preview pane - takes 1/5 of the width
                FilePreviewView(selectedFiles: Array(selectedFiles))
                    .frame(width: geometry.size.width * 0.2) // 1/5 of the width
                    .id("preview-\(selectedFiles.count)")
            }
        }
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
    }
}

struct FilePreviewItem: View {
    let file: URL
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
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
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
