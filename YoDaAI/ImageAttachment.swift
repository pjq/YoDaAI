//
//  ImageAttachment.swift
//  YoDaAI
//
//  Image attachment model for storing image files linked to chat messages
//

import Foundation
import SwiftData

@Model
final class ImageAttachment: Identifiable {
    var id: UUID
    var createdAt: Date

    // File storage
    var fileName: String          // e.g., "A7B3C2D1-4E5F-6789-ABCD-123456789ABC.jpg"
    var filePath: String          // Relative path from app Documents directory
    var mimeType: String          // e.g., "image/jpeg", "image/png"
    var fileSize: Int             // Bytes

    // Optional metadata
    var width: Int?
    var height: Int?

    // Relationship
    var message: ChatMessage?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        fileName: String,
        filePath: String,
        mimeType: String,
        fileSize: Int,
        width: Int? = nil,
        height: Int? = nil,
        message: ChatMessage? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fileName = fileName
        self.filePath = filePath
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.width = width
        self.height = height
        self.message = message
    }
}
