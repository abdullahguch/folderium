import Foundation
import AppKit
import SwiftUI

class FolderiumFileManager: ObservableObject {
    static let shared = FolderiumFileManager()
    
    private init() {}
    
    // MARK: - File Operations
    
    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try Foundation.FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }
    
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try Foundation.FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }
    
    func removeItem(at URL: URL) throws {
        try Foundation.FileManager.default.removeItem(at: URL)
    }
    
    func createDirectory(at URL: URL) throws {
        try Foundation.FileManager.default.createDirectory(at: URL, withIntermediateDirectories: true)
    }
    
    func createFile(at URL: URL, contents: Data? = nil) throws {
        Foundation.FileManager.default.createFile(atPath: URL.path, contents: contents)
    }
    
    // MARK: - File Information
    
    func getFileInfo(for url: URL) -> FileInfo? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .isHiddenKey,
                .isExecutableKey,
                .typeIdentifierKey
            ])
            
            return FileInfo(
                url: url,
                isDirectory: resourceValues.isDirectory ?? false,
                size: Int64(resourceValues.fileSize ?? 0),
                creationDate: resourceValues.creationDate,
                modificationDate: resourceValues.contentModificationDate,
                isHidden: resourceValues.isHidden ?? false,
                isExecutable: resourceValues.isExecutable ?? false,
                typeIdentifier: resourceValues.typeIdentifier
            )
        } catch {
            print("Error getting file info for \(url): \(error)")
            return nil
        }
    }
    
    func getDirectoryContents(at url: URL) -> [FileInfo] {
        do {
            let contents = try Foundation.FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .fileSizeKey,
                    .creationDateKey,
                    .contentModificationDateKey,
                    .isHiddenKey,
                    .isExecutableKey,
                    .typeIdentifierKey
                ],
                options: [.skipsHiddenFiles]
            )
            
            return contents.compactMap { getFileInfo(for: $0) }
                .sorted { first, second in
                    // Directories first, then files
                    if first.isDirectory && !second.isDirectory {
                        return true
                    } else if !first.isDirectory && second.isDirectory {
                        return false
                    } else {
                        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                    }
                }
        } catch {
            print("Error getting directory contents for \(url): \(error)")
            return []
        }
    }
    
    // MARK: - File Type Detection
    
    func getFileType(for url: URL) -> FileType {
        let pathExtension = url.pathExtension.lowercased()
        
        switch pathExtension {
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "lz", "lzma", "z", "cab", "iso":
            return .archive
        case "dmg":
            return .application
        case "txt", "md", "rtf", "doc", "docx", "pdf":
            return .document
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg", "webp":
            return .image
        case "mp4", "avi", "mov", "wmv", "flv", "webm", "mkv":
            return .video
        case "mp3", "wav", "aac", "flac", "ogg", "m4a":
            return .audio
        case "app", "exe", "deb", "pkg":
            return .application
        case "swift", "py", "js", "html", "css", "json", "xml", "yaml", "yml":
            return .code
        default:
            return .unknown
        }
    }
    
    // MARK: - File Operations with UI
    
    func showInFinder(_ url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
    
    func openWithDefaultApplication(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
    
    func openWithApplication(_ url: URL, application: String) {
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: application)
        if let appURL = appURL {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { (urls, error) in
                if let error = error {
                    print("Error opening file with application: \(error)")
                }
            }
        }
    }
    
    // MARK: - Trash Operations
    
    func moveToTrash(_ url: URL) throws {
        NSWorkspace.shared.recycle([url]) { (urls, error) in
            if let error = error {
                print("Error moving to trash: \(error)")
            }
        }
    }
    
    func emptyTrash() {
        NSWorkspace.shared.recycle([], completionHandler: { (urls, error) in
            if let error = error {
                print("Error emptying trash: \(error)")
            }
        })
    }
}

// MARK: - Data Models

struct FileInfo: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let creationDate: Date?
    let modificationDate: Date?
    let isHidden: Bool
    let isExecutable: Bool
    let typeIdentifier: String?
    
    var sizeString: String {
        if isDirectory {
            return ""
        } else {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }
    
    var fileType: FileType {
        let pathExtension = url.pathExtension.lowercased()
        
        switch pathExtension {
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "lz", "lzma", "z", "cab", "iso":
            return .archive
        case "dmg":
            return .application
        case "txt", "md", "rtf", "doc", "docx", "pdf":
            return .document
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg", "webp":
            return .image
        case "mp4", "avi", "mov", "wmv", "flv", "webm", "mkv":
            return .video
        case "mp3", "wav", "aac", "flac", "ogg", "m4a":
            return .audio
        case "app", "exe", "deb", "pkg":
            return .application
        case "swift", "py", "js", "html", "css", "json", "xml", "yaml", "yml":
            return .code
        default:
            return .unknown
        }
    }
    
    init(url: URL, isDirectory: Bool, size: Int64, creationDate: Date?, modificationDate: Date?, isHidden: Bool, isExecutable: Bool, typeIdentifier: String?) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.size = size
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.isHidden = isHidden
        self.isExecutable = isExecutable
        self.typeIdentifier = typeIdentifier
    }
}

enum FileType: String, CaseIterable {
    case archive = "Archive"
    case document = "Document"
    case image = "Image"
    case video = "Video"
    case audio = "Audio"
    case application = "Application"
    case code = "Code"
    case unknown = "Unknown"
    
    var systemImage: String {
        switch self {
        case .archive:
            return "archivebox.fill"
        case .document:
            return "doc.fill"
        case .image:
            return "photo.fill"
        case .video:
            return "video.fill"
        case .audio:
            return "music.note"
        case .application:
            return "app.fill"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .unknown:
            return "doc"
        }
    }
    
    var color: NSColor {
        switch self {
        case .archive:
            return .systemOrange
        case .document:
            return .systemBlue
        case .image:
            return .systemGreen
        case .video:
            return .systemPurple
        case .audio:
            return .systemPink
        case .application:
            return .systemIndigo
        case .code:
            return .systemTeal
        case .unknown:
            return .systemGray
        }
    }
}
