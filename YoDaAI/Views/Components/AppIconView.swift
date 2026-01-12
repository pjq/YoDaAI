//
//  AppIconView.swift
//  YoDaAI
//
//  Helper view for displaying app icons
//

import SwiftUI
import AppKit

struct AppIconView: View {
    let bundleIdentifier: String
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Fallback: generic app icon
                Image(systemName: "app.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            loadIcon()
        }
    }

    private func loadIcon() {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        icon = NSWorkspace.shared.icon(forFile: appURL.path)
    }
}
