//
//  ImageStorageService.swift
//  YoDaAI
//
//  Service for managing image file storage in the app's Documents directory
//

import Foundation
import AppKit

enum ImageStorageError: Error {
    case invalidImageData
    case unsupportedFormat
    case fileSizeTooLarge
    case storageError(Error)
    case invalidURL
}

@MainActor
final class ImageStorageService {
    static let shared = ImageStorageService()

    // Configuration
    private let maxFileSizeMB = 20  // 20MB limit per image
    private let supportedTypes: Set<String> = ["public.jpeg", "public.png", "public.heic", "public.gif"]

    // Storage directory
    private let imageDirectoryName = "ChatImages"

    private init() {}

    /// Get the app's image storage directory (creates if needed)
    func getImageStorageDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ImageStorageError.invalidURL
        }

        let imageDirectoryURL = documentsURL.appendingPathComponent(imageDirectoryName, isDirectory: true)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: imageDirectoryURL.path) {
            try fileManager.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)
        }

        return imageDirectoryURL
    }

    /// Save image data to disk, returns file metadata
    func saveImage(data: Data, originalFileName: String? = nil) throws -> (filePath: String, fileName: String, mimeType: String, fileSize: Int, dimensions: (width: Int, height: Int)?) {
        // Validate file size
        let fileSizeBytes = data.count
        guard fileSizeBytes <= maxFileSizeMB * 1024 * 1024 else {
            throw ImageStorageError.fileSizeTooLarge
        }

        // Validate image format and get dimensions
        guard let nsImage = NSImage(data: data) else {
            throw ImageStorageError.invalidImageData
        }

        let dimensions = (width: Int(nsImage.size.width), height: Int(nsImage.size.height))

        // Determine MIME type from data
        let mimeType = getMimeType(from: data)
        let fileExtension = getFileExtension(from: mimeType)

        // Generate unique filename
        let fileName = "\(UUID().uuidString).\(fileExtension)"

        // Get storage directory and save file
        let storageDir = try getImageStorageDirectory()
        let fileURL = storageDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ImageStorageError.storageError(error)
        }

        // Return relative path (just filename, since all images are in same directory)
        return (filePath: fileName, fileName: fileName, mimeType: mimeType, fileSize: fileSizeBytes, dimensions: dimensions)
    }

    /// Load image data from disk
    func loadImage(filePath: String) throws -> Data {
        let storageDir = try getImageStorageDirectory()
        let fileURL = storageDir.appendingPathComponent(filePath)

        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw ImageStorageError.storageError(error)
        }
    }

    /// Delete image file from disk
    func deleteImage(filePath: String) throws {
        let storageDir = try getImageStorageDirectory()
        let fileURL = storageDir.appendingPathComponent(filePath)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - Helper Methods

    private func getMimeType(from data: Data) -> String {
        // Check magic numbers
        guard data.count > 2 else { return "image/jpeg" }

        let bytes = [UInt8](data.prefix(12))

        if bytes[0] == 0xFF && bytes[1] == 0xD8 {
            return "image/jpeg"
        } else if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        } else if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 {
            return "image/gif"
        } else if data.count >= 12 && String(bytes: bytes[4..<12], encoding: .ascii) == "ftypheic" {
            return "image/heic"
        }

        return "image/jpeg" // default
    }

    private func getFileExtension(from mimeType: String) -> String {
        switch mimeType {
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/heic": return "heic"
        default: return "jpg"
        }
    }
}
