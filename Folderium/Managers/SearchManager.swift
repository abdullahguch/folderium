import Foundation
import CoreServices
import CoreSpotlight
import SwiftUI

class SearchManager: ObservableObject {
    static let shared = SearchManager()
    
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching: Bool = false
    @Published var searchError: String?
    
    private init() {}
    
    // MARK: - Spotlight Search
    
    func performSpotlightSearch(query: String, scope: SearchScope = .all) async {
        await MainActor.run {
            isSearching = true
            searchError = nil
            searchResults = []
        }
        
        do {
            let results = try await searchSpotlight(query: query, scope: scope)
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        } catch {
            await MainActor.run {
                searchError = error.localizedDescription
                isSearching = false
            }
        }
    }
    
    private func searchSpotlight(query: String, scope: SearchScope) async throws -> [SearchResult] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let queryContext = CSSearchQueryContext()
                let searchQuery = CSSearchQuery(queryString: query, queryContext: queryContext)
                
                var results: [SearchResult] = []
                
                searchQuery.foundItemsHandler = { items in
                    for item in items {
                        if let result = SearchManager.shared.createSearchResult(from: item) {
                            results.append(result)
                        }
                    }
                }
                
                searchQuery.completionHandler = { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: results)
                    }
                }
                
                // Note: CSSearchQuery scope filtering would need to be implemented differently
                // For now, we'll search globally and filter results if needed
                searchQuery.start()
            }
        }
    }
    
    private func createSearchResult(from item: CSSearchableItem) -> SearchResult? {
        let attributes = item.attributeSet
        guard let path = attributes.path,
              let displayName = attributes.displayName else {
            return nil
        }
        
        let url = URL(fileURLWithPath: path)
        // CSSearchableItemAttributeSet doesn't have these properties directly
        // We need to determine from the file path or use default values
        let isDirectory = path.hasSuffix("/")
        let size = Int64(truncating: attributes.fileSize ?? 0)
        let modificationDate = attributes.contentModificationDate
        let creationDate = attributes.contentCreationDate
        let contentType = attributes.contentType
        
        return SearchResult(
            url: url,
            name: displayName,
            isDirectory: isDirectory,
            size: size,
            modificationDate: modificationDate,
            creationDate: creationDate,
            contentType: contentType
        )
    }
    
    // MARK: - Local File Search
    
    func performLocalSearch(query: String, in directory: URL, options: SearchOptions = SearchOptions()) async {
        await MainActor.run {
            isSearching = true
            searchError = nil
            searchResults = []
        }
        
        do {
            let results = try await searchLocalFiles(query: query, in: directory, options: options)
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        } catch {
            await MainActor.run {
                searchError = error.localizedDescription
                isSearching = false
            }
        }
    }
    
    private func searchLocalFiles(query: String, in directory: URL, options: SearchOptions) async throws -> [SearchResult] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fileManager = FileManager.default
                    var results: [SearchResult] = []
                    
                    let enumerator = fileManager.enumerator(
                        at: directory,
                        includingPropertiesForKeys: [
                            .isDirectoryKey,
                            .fileSizeKey,
                            .contentModificationDateKey,
                            .creationDateKey,
                            .typeIdentifierKey
                        ],
                        options: [.skipsHiddenFiles]
                    )
                    
                    while let url = enumerator?.nextObject() as? URL {
                        let fileName = url.lastPathComponent
                        
                        // Check if file matches search criteria
                        if SearchManager.shared.matchesSearch(fileName: fileName, query: query, options: options) {
                        let resourceValues = try url.resourceValues(forKeys: [
                            .isDirectoryKey,
                            .fileSizeKey,
                            .contentModificationDateKey,
                            .creationDateKey,
                            .typeIdentifierKey
                        ])
                            
                            let result = SearchResult(
                                url: url,
                                name: fileName,
                                isDirectory: resourceValues.isDirectory ?? false,
                                size: Int64(resourceValues.fileSize ?? 0),
                                modificationDate: resourceValues.contentModificationDate,
                                creationDate: resourceValues.creationDate,
                                contentType: resourceValues.typeIdentifier
                            )
                            
                            results.append(result)
                        }
                        
                        // Limit results if specified
                        if options.maxResults > 0 && results.count >= options.maxResults {
                            break
                        }
                    }
                    
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func matchesSearch(fileName: String, query: String, options: SearchOptions) -> Bool {
        let searchText = options.caseSensitive ? fileName : fileName.lowercased()
        let searchQuery = options.caseSensitive ? query : query.lowercased()
        
        switch options.searchType {
        case .contains:
            return searchText.contains(searchQuery)
        case .startsWith:
            return searchText.hasPrefix(searchQuery)
        case .endsWith:
            return searchText.hasSuffix(searchQuery)
        case .exactMatch:
            return searchText == searchQuery
        case .regex:
            do {
                let regex = try NSRegularExpression(pattern: searchQuery, options: options.caseSensitive ? [] : .caseInsensitive)
                let range = NSRange(location: 0, length: searchText.utf16.count)
                return regex.firstMatch(in: searchText, options: [], range: range) != nil
            } catch {
                return false
            }
        }
    }
    
    // MARK: - Content Search
    
    func searchInFileContents(query: String, in directory: URL, fileTypes: [String] = [], options: SearchOptions = SearchOptions()) async {
        await MainActor.run {
            isSearching = true
            searchError = nil
            searchResults = []
        }
        
        do {
            let results = try await searchFileContents(query: query, in: directory, fileTypes: fileTypes, options: options)
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        } catch {
            await MainActor.run {
                searchError = error.localizedDescription
                isSearching = false
            }
        }
    }
    
    private func searchFileContents(query: String, in directory: URL, fileTypes: [String], options: SearchOptions) async throws -> [SearchResult] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fileManager = FileManager.default
                    var results: [SearchResult] = []
                    
                    let enumerator = fileManager.enumerator(
                        at: directory,
                        includingPropertiesForKeys: [
                            .isDirectoryKey,
                            .fileSizeKey,
                            .contentModificationDateKey,
                            .creationDateKey,
                            .typeIdentifierKey
                        ],
                        options: [.skipsHiddenFiles]
                    )
                    
                    while let url = enumerator?.nextObject() as? URL {
                        let resourceValues = try url.resourceValues(forKeys: [
                            .isDirectoryKey,
                            .fileSizeKey,
                            .contentModificationDateKey,
                            .creationDateKey,
                            .typeIdentifierKey
                        ])
                        
                        // Skip directories
                        guard !(resourceValues.isDirectory ?? false) else { continue }
                        
                        // Check file type filter
                        if !fileTypes.isEmpty {
                            let fileExtension = url.pathExtension.lowercased()
                            if !fileTypes.contains(fileExtension) {
                                continue
                            }
                        }
                        
                        // Search in file contents
                        if SearchManager.shared.searchInFile(url: url, query: query, options: options) {
                            let result = SearchResult(
                                url: url,
                                name: url.lastPathComponent,
                                isDirectory: false,
                                size: Int64(resourceValues.fileSize ?? 0),
                                modificationDate: resourceValues.contentModificationDate,
                                creationDate: resourceValues.creationDate,
                                contentType: resourceValues.typeIdentifier
                            )
                            
                            results.append(result)
                        }
                        
                        // Limit results if specified
                        if options.maxResults > 0 && results.count >= options.maxResults {
                            break
                        }
                    }
                    
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func searchInFile(url: URL, query: String, options: SearchOptions) -> Bool {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let searchText = options.caseSensitive ? content : content.lowercased()
            let searchQuery = options.caseSensitive ? query : query.lowercased()
            
            switch options.searchType {
            case .contains:
                return searchText.contains(searchQuery)
            case .startsWith:
                return searchText.hasPrefix(searchQuery)
            case .endsWith:
                return searchText.hasSuffix(searchQuery)
            case .exactMatch:
                return searchText == searchQuery
            case .regex:
                do {
                    let regex = try NSRegularExpression(pattern: searchQuery, options: options.caseSensitive ? [] : .caseInsensitive)
                    let range = NSRange(location: 0, length: searchText.utf16.count)
                    return regex.firstMatch(in: searchText, options: [], range: range) != nil
                } catch {
                    return false
                }
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Clear Results
    
    func clearResults() {
        searchResults = []
        searchError = nil
    }
}

// MARK: - Data Models

struct SearchResult: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date?
    let creationDate: Date?
    let contentType: String?
    
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
}

enum SearchScope {
    case all
    case home
    case currentDirectory(URL)
    case custom([URL])
}

enum SearchType {
    case contains
    case startsWith
    case endsWith
    case exactMatch
    case regex
}

struct SearchOptions {
    var searchType: SearchType = .contains
    var caseSensitive: Bool = false
    var maxResults: Int = 1000
    var includeHidden: Bool = false
    var fileSizeLimit: Int64 = 100 * 1024 * 1024 // 100MB default limit for content search
}
