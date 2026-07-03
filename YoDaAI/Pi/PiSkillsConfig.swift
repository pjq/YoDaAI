//
//  PiSkillsConfig.swift
//  YoDaAI
//
//  Resolves the skill directories the pi agent should load. pi discovers skills
//  from these via the repeatable `--skill <path>` CLI flag (additive), so we
//  never mutate the user's ~/.pi/agent/settings.json.
//
//  Sources (per product decision):
//   - ~/.claude/skills        (Claude Code skills)
//   - ~/.agents/skills        (shared agent-skills; pi also auto-discovers these)
//   - <project>/.claude/skills (per-project skills; requires --approve in RPC)
//

import Foundation

enum PiSkillsConfig {

    /// Global (user-level) skill directories that exist on disk. pi discovers
    /// SKILL.md recursively under each, so pointing at a marketplace's `skills/`
    /// dir surfaces all its skills.
    static func globalSkillDirectories() -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var dirs: [URL] = [
            home.appendingPathComponent(".claude/skills"),
            home.appendingPathComponent(".agents/skills"),
        ]
        // Claude Code plugin marketplaces keep skills under
        // ~/.claude/plugins/marketplaces/<name>/skills.
        let marketplaces = home.appendingPathComponent(".claude/plugins/marketplaces")
        if let entries = try? fm.contentsOfDirectory(at: marketplaces,
                                                     includingPropertiesForKeys: nil) {
            for entry in entries {
                dirs.append(entry.appendingPathComponent("skills"))
            }
        }
        return dirs
            .filter { isDirectory($0) }
            .map { $0.path }
    }

    /// Per-project skill directory (e.g. androidrepo/.claude/skills) if present.
    /// Loading these requires pi project trust (`--approve`).
    static func projectSkillDirectory(for workingDirectory: URL) -> String? {
        let dir = workingDirectory.appendingPathComponent(".claude/skills")
        return isDirectory(dir) ? dir.path : nil
    }

    /// Full list of `--skill` paths for a given working directory.
    static func skillPaths(for workingDirectory: URL) -> (paths: [String], needsApprove: Bool) {
        var paths = globalSkillDirectories()
        var needsApprove = false
        if let projectDir = projectSkillDirectory(for: workingDirectory) {
            paths.append(projectDir)
            needsApprove = true
        }
        return (paths, needsApprove)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
