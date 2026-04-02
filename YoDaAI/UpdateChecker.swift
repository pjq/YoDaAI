import Foundation
import Combine
import AppKit

// MARK: - GitHub Release Model

private struct GitHubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    let body: String?
    let assets: [GitHubAsset]
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
        case assets
        case publishedAt = "published_at"
    }
}

private struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

// MARK: - Update Checker

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    private static let repo = "pjq/YoDaAI"
    private static let lastCheckedKey = "updateChecker_lastChecked"

    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var releaseURL: URL?
    @Published var releaseNotes: String?
    @Published var downloadURL: URL?
    @Published var lastChecked: Date?
    @Published var errorMessage: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    var commitHash: String {
        Bundle.main.infoDictionary?["CommitHash"] as? String ?? "dev"
    }

    var buildDate: String {
        Bundle.main.infoDictionary?["BuildDate"] as? String ?? ""
    }

    private init() {
        if let timestamp = UserDefaults.standard.object(forKey: Self.lastCheckedKey) as? Double {
            lastChecked = Date(timeIntervalSince1970: timestamp)
        }
    }

    /// Check for updates. If `force` is false, only checks if >24h since last check.
    func checkForUpdate(force: Bool = true) {
        if !force, let last = lastChecked, Date().timeIntervalSince(last) < 86400 {
            return
        }

        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil

        Task {
            defer { isChecking = false }

            do {
                let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
                var request = URLRequest(url: url)
                request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 15

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    errorMessage = "GitHub API returned an error"
                    return
                }

                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

                // Strip leading 'v' from tag
                let remoteVersion = release.tagName.hasPrefix("v")
                    ? String(release.tagName.dropFirst())
                    : release.tagName

                latestVersion = remoteVersion
                releaseURL = URL(string: release.htmlUrl)
                releaseNotes = release.body

                // Find DMG asset preferring DMG over ZIP
                if let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) {
                    downloadURL = URL(string: dmg.browserDownloadUrl)
                } else if let zip = release.assets.first(where: { $0.name.hasSuffix(".zip") }) {
                    downloadURL = URL(string: zip.browserDownloadUrl)
                }

                updateAvailable = isNewerVersion(remoteVersion, than: currentVersion)

                lastChecked = Date()
                UserDefaults.standard.set(lastChecked!.timeIntervalSince1970, forKey: Self.lastCheckedKey)

            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func openReleasePage() {
        if let url = releaseURL {
            NSWorkspace.shared.open(url)
        }
    }

    func openDownload() {
        if let url = downloadURL {
            NSWorkspace.shared.open(url)
        } else {
            openReleasePage()
        }
    }

    // MARK: - Semantic Version Comparison

    /// Returns true if `remote` is strictly newer than `local`
    private func isNewerVersion(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        let count = max(remoteParts.count, localParts.count)
        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
