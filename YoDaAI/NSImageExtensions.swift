//
//  NSImageExtensions.swift
//  YoDaAI
//
//  Extensions for NSImage to support thumbnail creation and format conversion
//

import AppKit

extension NSImage {
    /// Resize image to fit within specified size while maintaining aspect ratio
    func resized(to targetSize: NSSize) -> NSImage {
        let imageRect = CGRect(origin: .zero, size: size)
        let targetRect = CGRect(origin: .zero, size: targetSize)

        let scale = min(
            targetRect.width / imageRect.width,
            targetRect.height / imageRect.height
        )

        let scaledSize = CGSize(
            width: imageRect.width * scale,
            height: imageRect.height * scale
        )

        let newImage = NSImage(size: scaledSize)
        newImage.lockFocus()

        let destRect = CGRect(origin: .zero, size: scaledSize)
        draw(in: destRect, from: imageRect, operation: .copy, fraction: 1.0)

        newImage.unlockFocus()
        return newImage
    }

    /// Convert NSImage to PNG data
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
