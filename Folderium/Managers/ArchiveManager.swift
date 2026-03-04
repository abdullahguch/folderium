import Foundation
import Compression
import SwiftUI

class ArchiveManager: ObservableObject {
    static let shared = ArchiveManager()
    
    private init() {}
    
    // MARK: - Archive Detection
    
    func isArchive(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return ArchiveFormat.allCases.contains { $0.fileExtensions.contains(pathExtension) }
    }
    
    func getArchiveFormat(for url: URL) -> ArchiveFormat? {
        let lowerName = url.lastPathComponent.lowercased()
        if lowerName.hasSuffix(".tar.gz") || lowerName.hasSuffix(".tgz") {
            return .gzip
        }
        if lowerName.hasSuffix(".tar.bz2") || lowerName.hasSuffix(".tbz2") || lowerName.hasSuffix(".tbz") {
            return .bzip2
        }

        let pathExtension = url.pathExtension.lowercased()
        return ArchiveFormat.allCases.first { $0.fileExtensions.contains(pathExtension) }
    }

    func archiveSupportInfo(for url: URL) -> ArchiveSupportInfo {
        guard let format = getArchiveFormat(for: url) else {
            return ArchiveSupportInfo(isArchive: false, formatLabel: "Not Archive", canExtract: false, detail: "Not an archive")
        }

        switch format {
        case .zip, .tar, .gzip, .bzip2:
            return ArchiveSupportInfo(isArchive: true, formatLabel: format.rawValue, canExtract: true, detail: "Supported")
        case .sevenZip:
            let available = Self.sevenZipExecutable() != nil || Self.bsdtarExecutable() != nil
            return ArchiveSupportInfo(
                isArchive: true,
                formatLabel: format.rawValue,
                canExtract: available,
                detail: available ? "Supported" : "Install p7zip (7z/7zz) to extract"
            )
        case .rar:
            let available = Self.unrarExecutable() != nil || Self.sevenZipExecutable() != nil || Self.bsdtarExecutable() != nil
            return ArchiveSupportInfo(
                isArchive: true,
                formatLabel: format.rawValue,
                canExtract: available,
                detail: available ? "Supported" : "Install unrar or p7zip to extract"
            )
        case .iso, .cab, .lzh:
            return ArchiveSupportInfo(isArchive: true, formatLabel: format.rawValue, canExtract: false, detail: "Unsupported")
        }
    }
    
    // MARK: - Archive Operations
    
    func compressFiles(_ fileURLs: [URL], to destinationURL: URL, format: ArchiveFormat = .zip) async throws {
        switch format {
        case .zip:
            try await createZIP(from: fileURLs, to: destinationURL)
        case .tar:
            try await createTAR(from: fileURLs, to: destinationURL)
        case .gzip:
            try await createGZIP(from: fileURLs, to: destinationURL)
        case .bzip2:
            try await createBZIP2(from: fileURLs, to: destinationURL)
        case .sevenZip:
            try await create7Z(from: fileURLs, to: destinationURL)
        case .rar:
            throw ArchiveError.unsupportedFormat // RAR creation requires proprietary tools
        case .iso:
            throw ArchiveError.unsupportedFormat // ISO creation is complex
        case .cab:
            throw ArchiveError.unsupportedFormat // CAB creation requires Windows tools
        case .lzh:
            throw ArchiveError.unsupportedFormat // LZH creation requires special tools
        }
    }
    
    func extractArchive(at archiveURL: URL, to destinationURL: URL) async throws {
        guard let format = getArchiveFormat(for: archiveURL) else {
            throw ArchiveError.unsupportedFormat
        }
        
        switch format {
        case .zip:
            try await extractZIP(archiveURL, to: destinationURL)
        case .tar:
            try await extractTAR(archiveURL, to: destinationURL)
        case .gzip:
            try await extractGZIP(archiveURL, to: destinationURL)
        case .bzip2:
            try await extractBZIP2(archiveURL, to: destinationURL)
        case .sevenZip:
            try await extract7Z(archiveURL, to: destinationURL)
        case .rar:
            try await extractRAR(archiveURL, to: destinationURL)
        case .iso:
            try await extractISO(archiveURL, to: destinationURL)
        case .cab:
            try await extractCAB(archiveURL, to: destinationURL)
        case .lzh:
            try await extractLZH(archiveURL, to: destinationURL)
        }
    }
    
    func createArchive(from sourceURL: URL, to destinationURL: URL, format: ArchiveFormat = .zip) async throws {
        switch format {
        case .zip:
            try await createZIP(from: [sourceURL], to: destinationURL)
        case .tar:
            try await createTAR(from: [sourceURL], to: destinationURL)
        case .gzip:
            try await createGZIP(from: [sourceURL], to: destinationURL)
        case .bzip2:
            try await createBZIP2(from: [sourceURL], to: destinationURL)
        default:
            throw ArchiveError.unsupportedFormat
        }
    }
    
    func listArchiveContents(at archiveURL: URL) async throws -> [ArchiveItem] {
        guard let format = getArchiveFormat(for: archiveURL) else {
            throw ArchiveError.unsupportedFormat
        }
        
        switch format {
        case .zip:
            return try await listZIPContents(archiveURL)
        case .tar:
            return try await listTARContents(archiveURL)
        case .gzip:
            return try await listGZIPContents(archiveURL)
        case .bzip2:
            return try await listBZIP2Contents(archiveURL)
        case .sevenZip:
            return try await list7ZContents(archiveURL)
        case .rar:
            return try await listRARContents(archiveURL)
        case .iso:
            return try await listISOContents(archiveURL)
        case .cab:
            return try await listCABContents(archiveURL)
        case .lzh:
            return try await listLZHContents(archiveURL)
        }
    }
    
    // MARK: - ZIP Operations
    
    private func extractZIP(_ archiveURL: URL, to destinationURL: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fileManager = FileManager.default
                    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                    
                    print("Running unzip command: unzip -o \(archiveURL.path) -d \(destinationURL.path)")
                    
                    // Use system unzip command for better compatibility
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    process.arguments = ["-o", archiveURL.path, "-d", destinationURL.path]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    print("Unzip process finished with status: \(process.terminationStatus)")
                    
                    if process.terminationStatus == 0 {
                        print("ZIP extraction successful")
                        continuation.resume()
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                        print("ZIP extraction failed: \(errorString)")
                        continuation.resume(throwing: ArchiveError.extractionFailed(errorString))
                    }
                } catch {
                    print("Error in ZIP extraction: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    private func listZIPContents(_ archiveURL: URL) async throws -> [ArchiveItem] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    process.arguments = ["-l", archiveURL.path]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? ""
                        let items = ArchiveManager.shared.parseZIPListOutput(output)
                        continuation.resume(returning: items)
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: ArchiveError.listingFailed(errorString))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - TAR Operations
    
    private func extractTAR(_ archiveURL: URL, to destinationURL: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fileManager = FileManager.default
                    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                    
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                    process.arguments = ["-xf", archiveURL.path, "-C", destinationURL.path]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: ArchiveError.extractionFailed(errorString))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    private func listTARContents(_ archiveURL: URL) async throws -> [ArchiveItem] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                    process.arguments = ["-tf", archiveURL.path]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? ""
                        let items = ArchiveManager.shared.parseTARListOutput(output)
                        continuation.resume(returning: items)
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: ArchiveError.listingFailed(errorString))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - GZIP Operations
    
    private func extractGZIP(_ archiveURL: URL, to destinationURL: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fileManager = FileManager.default
                    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                    
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
                    process.arguments = ["-c", archiveURL.path]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    let outputFile = destinationURL.appendingPathComponent(archiveURL.deletingPathExtension().lastPathComponent)
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        try data.write(to: outputFile)
                        if Self.isTarGzipArchive(archiveURL) {
                            _ = try Self.runProcess(executablePath: "/usr/bin/tar", arguments: ["-xf", outputFile.path, "-C", destinationURL.path])
                            try? FileManager.default.removeItem(at: outputFile)
                        }
                        continuation.resume()
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: ArchiveError.extractionFailed(errorString))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    private func listGZIPContents(_ archiveURL: URL) async throws -> [ArchiveItem] {
        // GZIP is typically used for single files, so we'll return the compressed file info
        let fileInfo = FolderiumFileManager.shared.getFileInfo(for: archiveURL)
        if let fileInfo = fileInfo {
            return [ArchiveItem(
                name: archiveURL.deletingPathExtension().lastPathComponent,
                size: fileInfo.size,
                isDirectory: false,
                modificationDate: fileInfo.modificationDate
            )]
        }
        return []
    }
    
    // MARK: - BZIP2 Operations
    
    private func extractBZIP2(_ archiveURL: URL, to destinationURL: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fileManager = FileManager.default
                    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                    
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/bunzip2")
                    process.arguments = ["-c", archiveURL.path]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    let outputFile = destinationURL.appendingPathComponent(archiveURL.deletingPathExtension().lastPathComponent)
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        try data.write(to: outputFile)
                        if Self.isTarBzip2Archive(archiveURL) {
                            _ = try Self.runProcess(executablePath: "/usr/bin/tar", arguments: ["-xf", outputFile.path, "-C", destinationURL.path])
                            try? FileManager.default.removeItem(at: outputFile)
                        }
                        continuation.resume()
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: ArchiveError.extractionFailed(errorString))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    private func listBZIP2Contents(_ archiveURL: URL) async throws -> [ArchiveItem] {
        // BZIP2 is typically used for single files, so we'll return the compressed file info
        let fileInfo = FolderiumFileManager.shared.getFileInfo(for: archiveURL)
        if let fileInfo = fileInfo {
            return [ArchiveItem(
                name: archiveURL.deletingPathExtension().lastPathComponent,
                size: fileInfo.size,
                isDirectory: false,
                modificationDate: fileInfo.modificationDate
            )]
        }
        return []
    }
    
    // MARK: - Placeholder implementations for other formats
    
    private func extract7Z(_ archiveURL: URL, to destinationURL: URL) async throws {
        if let sevenZip = Self.sevenZipExecutable() {
            _ = try Self.runProcess(executablePath: sevenZip, arguments: ["x", archiveURL.path, "-o\(destinationURL.path)", "-y"])
            return
        }
        if let bsdtar = Self.bsdtarExecutable() {
            _ = try Self.runProcess(executablePath: bsdtar, arguments: ["-xf", archiveURL.path, "-C", destinationURL.path])
            return
        }
        throw ArchiveError.unsupportedFormatWithHint("7Z extraction requires p7zip (7z/7zz).")
    }
    
    private func extractRAR(_ archiveURL: URL, to destinationURL: URL) async throws {
        if let unrar = Self.unrarExecutable() {
            let destinationWithSlash = destinationURL.path.hasSuffix("/") ? destinationURL.path : destinationURL.path + "/"
            _ = try Self.runProcess(executablePath: unrar, arguments: ["x", "-o+", archiveURL.path, destinationWithSlash])
            return
        }
        if let sevenZip = Self.sevenZipExecutable() {
            _ = try Self.runProcess(executablePath: sevenZip, arguments: ["x", archiveURL.path, "-o\(destinationURL.path)", "-y"])
            return
        }
        if let bsdtar = Self.bsdtarExecutable() {
            _ = try Self.runProcess(executablePath: bsdtar, arguments: ["-xf", archiveURL.path, "-C", destinationURL.path])
            return
        }
        throw ArchiveError.unsupportedFormatWithHint("RAR extraction requires unrar or p7zip (7z/7zz).")
    }
    
    private func extractISO(_ archiveURL: URL, to destinationURL: URL) async throws {
        throw ArchiveError.unsupportedFormat
    }
    
    private func extractCAB(_ archiveURL: URL, to destinationURL: URL) async throws {
        throw ArchiveError.unsupportedFormat
    }
    
    private func extractLZH(_ archiveURL: URL, to destinationURL: URL) async throws {
        throw ArchiveError.unsupportedFormat
    }
    
    private func list7ZContents(_ archiveURL: URL) async throws -> [ArchiveItem] {
        if let sevenZip = Self.sevenZipExecutable() {
            let output = try Self.runProcess(executablePath: sevenZip, arguments: ["l", "-slt", archiveURL.path])
            return parse7zStructuredListOutput(output)
        }
        if let bsdtar = Self.bsdtarExecutable() {
            let output = try Self.runProcess(executablePath: bsdtar, arguments: ["-tf", archiveURL.path])
            return parseTARListOutput(output)
        }
        throw ArchiveError.unsupportedFormatWithHint("7Z listing requires p7zip (7z/7zz).")
    }
    
    private func listRARContents(_ archiveURL: URL) async throws -> [ArchiveItem] {
        if let unrar = Self.unrarExecutable() {
            let output = try Self.runProcess(executablePath: unrar, arguments: ["lb", archiveURL.path])
            return parseSimpleFileListOutput(output)
        }
        if let sevenZip = Self.sevenZipExecutable() {
            let output = try Self.runProcess(executablePath: sevenZip, arguments: ["l", "-slt", archiveURL.path])
            return parse7zStructuredListOutput(output)
        }
        if let bsdtar = Self.bsdtarExecutable() {
            let output = try Self.runProcess(executablePath: bsdtar, arguments: ["-tf", archiveURL.path])
            return parseTARListOutput(output)
        }
        throw ArchiveError.unsupportedFormatWithHint("RAR listing requires unrar or p7zip (7z/7zz).")
    }
    
    private func listISOContents(_ archiveURL: URL) async throws -> [ArchiveItem] {
        throw ArchiveError.unsupportedFormat
    }
    
    private func listCABContents(_ archiveURL: URL) async throws -> [ArchiveItem] {
        throw ArchiveError.unsupportedFormat
    }
    
    private func listLZHContents(_ archiveURL: URL) async throws -> [ArchiveItem] {
        throw ArchiveError.unsupportedFormat
    }
    
    // MARK: - Helper Methods
    
    private func parseZIPListOutput(_ output: String) -> [ArchiveItem] {
        let lines = output.components(separatedBy: .newlines)
        var items: [ArchiveItem] = []
        
        for line in lines {
            if line.contains("Length") && line.contains("Date") && line.contains("Time") {
                continue // Skip header
            }
            if line.contains("----") {
                continue // Skip separator
            }
            if line.isEmpty {
                continue
            }
            
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if components.count >= 4 {
                let sizeString = components[0]
                let dateString = components[1]
                let timeString = components[2]
                let name = components.dropFirst(3).joined(separator: " ")
                
                if let size = Int64(sizeString) {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MM-dd-yy HH:mm"
                    let dateTimeString = "\(dateString) \(timeString)"
                    let modificationDate = formatter.date(from: dateTimeString)
                    
                    items.append(ArchiveItem(
                        name: name,
                        size: size,
                        isDirectory: name.hasSuffix("/"),
                        modificationDate: modificationDate
                    ))
                }
            }
        }
        
        return items
    }
    
    private func parseTARListOutput(_ output: String) -> [ArchiveItem] {
        let lines = output.components(separatedBy: .newlines)
        var items: [ArchiveItem] = []
        
        for line in lines {
            if line.isEmpty {
                continue
            }
            
            // TAR list output is just the file names
            let name = line.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                items.append(ArchiveItem(
                    name: name,
                    size: 0, // Size not available in tar -t output
                    isDirectory: name.hasSuffix("/"),
                    modificationDate: nil
                ))
            }
        }
        
        return items
    }

    private func parseSimpleFileListOutput(_ output: String) -> [ArchiveItem] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { name in
                ArchiveItem(name: name, size: 0, isDirectory: name.hasSuffix("/"), modificationDate: nil)
            }
    }

    private func parse7zStructuredListOutput(_ output: String) -> [ArchiveItem] {
        var items: [ArchiveItem] = []
        let lines = output.components(separatedBy: .newlines)
        var currentPath: String?
        var currentSize: Int64 = 0
        var currentAttributes: String = ""
        var currentModified: Date?
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func flush() {
            guard let path = currentPath, !path.isEmpty else { return }
            let isDirectory = currentAttributes.contains("D_")
            items.append(ArchiveItem(name: path, size: currentSize, isDirectory: isDirectory, modificationDate: currentModified))
            currentPath = nil
            currentSize = 0
            currentAttributes = ""
            currentModified = nil
        }

        for line in lines {
            if line.hasPrefix("Path = ") {
                flush()
                currentPath = String(line.dropFirst("Path = ".count))
            } else if line.hasPrefix("Size = ") {
                currentSize = Int64(String(line.dropFirst("Size = ".count))) ?? 0
            } else if line.hasPrefix("Attributes = ") {
                currentAttributes = String(line.dropFirst("Attributes = ".count))
            } else if line.hasPrefix("Modified = ") {
                let value = String(line.dropFirst("Modified = ".count))
                currentModified = formatter.date(from: value)
            }
        }
        flush()

        return items
    }

    private static func runProcess(executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw ArchiveError.extractionFailed(output.isEmpty ? "Command failed with exit code \(process.terminationStatus)" : output)
        }
        return output
    }

    private static func isTarGzipArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz")
    }

    private static func isTarBzip2Archive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz2") || name.hasSuffix(".tbz")
    }

    private static func firstAvailableExecutable(_ candidates: [String]) -> String? {
        candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private static func sevenZipExecutable() -> String? {
        firstAvailableExecutable(["/opt/homebrew/bin/7zz", "/opt/homebrew/bin/7z", "/usr/local/bin/7z", "/usr/bin/7z"])
    }

    private static func unrarExecutable() -> String? {
        firstAvailableExecutable(["/opt/homebrew/bin/unrar", "/usr/local/bin/unrar", "/usr/bin/unrar"])
    }

    private static func bsdtarExecutable() -> String? {
        firstAvailableExecutable(["/usr/bin/bsdtar"])
    }
}

// MARK: - Data Models

enum ArchiveFormat: String, CaseIterable {
    case zip = "ZIP"
    case tar = "TAR"
    case gzip = "GZIP"
    case bzip2 = "BZIP2"
    case sevenZip = "7Z"
    case rar = "RAR"
    case iso = "ISO"
    case cab = "CAB"
    case lzh = "LZH"
    
    var fileExtensions: [String] {
        switch self {
        case .zip:
            return ["zip"]
        case .tar:
            return ["tar"]
        case .gzip:
            return ["gz", "gzip"]
        case .bzip2:
            return ["bz2", "bzip2"]
        case .sevenZip:
            return ["7z"]
        case .rar:
            return ["rar"]
        case .iso:
            return ["iso"]
        case .cab:
            return ["cab"]
        case .lzh:
            return ["lzh", "lha"]
        }
    }
    
    var systemImage: String {
        switch self {
        case .zip:
            return "archivebox.fill"
        case .tar:
            return "archivebox.fill"
        case .gzip:
            return "archivebox.fill"
        case .bzip2:
            return "archivebox.fill"
        case .sevenZip:
            return "archivebox.fill"
        case .rar:
            return "archivebox.fill"
        case .iso:
            return "opticaldisc.fill"
        case .cab:
            return "archivebox.fill"
        case .lzh:
            return "archivebox.fill"
        }
    }
}

struct ArchiveItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let size: Int64
    let isDirectory: Bool
    let modificationDate: Date?
    
    var sizeString: String {
        if isDirectory {
            return ""
        } else {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }
}

struct ArchiveSupportInfo {
    let isArchive: Bool
    let formatLabel: String
    let canExtract: Bool
    let detail: String
}

// MARK: - Compression Methods

extension ArchiveManager {
    private func createZIP(from fileURLs: [URL], to destinationURL: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    let fileManager = FileManager.default
                    
                    // Create the destination directory if it doesn't exist
                    try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    
                    // Use zip command line tool
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    
                    // Set working directory to the parent directory of the first file
                    let firstFile = fileURLs.first!
                    let workingDirectory = firstFile.deletingLastPathComponent()
                    process.currentDirectoryPath = workingDirectory.path
                    
                    // Use relative paths for the zip command
                    var arguments = ["-r", destinationURL.path]
                    for fileURL in fileURLs {
                        // Use relative path from the working directory
                        let relativePath = fileURL.lastPathComponent
                        arguments.append(relativePath)
                    }
                    process.arguments = arguments
                    
                    print("Running zip command: zip \(arguments.joined(separator: " "))")
                    print("Working directory: \(workingDirectory.path)")
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    print("Zip process finished with status: \(process.terminationStatus)")
                    
                    if process.terminationStatus == 0 {
                        print("ZIP compression successful")
                        continuation.resume()
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                        print("ZIP compression failed: \(errorString)")
                        continuation.resume(throwing: ArchiveError.creationFailed(errorString))
                    }
                } catch {
                    print("Error in ZIP compression: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func createTAR(from fileURLs: [URL], to destinationURL: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    let fileManager = FileManager.default
                    
                    // Create the destination directory if it doesn't exist
                    try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    
                    // Use tar command line tool
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                    
                    var arguments = ["-cf", destinationURL.path]
                    for fileURL in fileURLs {
                        arguments.append(fileURL.path)
                    }
                    process.arguments = arguments
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: ArchiveError.creationFailed(errorString))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func createGZIP(from fileURLs: [URL], to destinationURL: URL) async throws {
        // For GZIP, we'll create a TAR.GZ file
        let tarURL = destinationURL.appendingPathExtension("tar")
        try await createTAR(from: fileURLs, to: tarURL)
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
                    process.arguments = ["-c", tarURL.path]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    let outputFile = FileHandle(forWritingAtPath: destinationURL.path)
                    process.standardOutput = outputFile
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    outputFile?.closeFile()
                    
                    if process.terminationStatus == 0 {
                        // Clean up the temporary tar file
                        try? FileManager.default.removeItem(at: tarURL)
                        continuation.resume()
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: ArchiveError.creationFailed(errorString))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func createBZIP2(from fileURLs: [URL], to destinationURL: URL) async throws {
        // For BZIP2, we'll create a TAR.BZ2 file
        let tarURL = destinationURL.appendingPathExtension("tar")
        try await createTAR(from: fileURLs, to: tarURL)
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/bzip2")
                    process.arguments = ["-c", tarURL.path]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    let outputFile = FileHandle(forWritingAtPath: destinationURL.path)
                    process.standardOutput = outputFile
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    outputFile?.closeFile()
                    
                    if process.terminationStatus == 0 {
                        // Clean up the temporary tar file
                        try? FileManager.default.removeItem(at: tarURL)
                        continuation.resume()
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: ArchiveError.creationFailed(errorString))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func create7Z(from fileURLs: [URL], to destinationURL: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    let fileManager = FileManager.default
                    
                    // Create the destination directory if it doesn't exist
                    try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    
                    // Use 7z command line tool (if available)
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/7z")
                    
                    var arguments = ["a", destinationURL.path]
                    for fileURL in fileURLs {
                        arguments.append(fileURL.path)
                    }
                    process.arguments = arguments
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: ArchiveError.creationFailed(errorString))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum ArchiveError: LocalizedError {
    case unsupportedFormat
    case unsupportedFormatWithHint(String)
    case extractionFailed(String)
    case creationFailed(String)
    case listingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported archive format"
        case .unsupportedFormatWithHint(let message):
            return message
        case .extractionFailed(let message):
            return "Extraction failed: \(message)"
        case .creationFailed(let message):
            return "Creation failed: \(message)"
        case .listingFailed(let message):
            return "Listing failed: \(message)"
        }
    }
}
