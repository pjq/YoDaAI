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
//   - ~/.claude/plugins/marketplaces/*/skills (Claude Code plugin skills)
//   - per-project: <project>/{.claude,.pi,.agents}/skills and Claude plugin
//     marketplaces under the project (requires --approve for project trust in RPC)
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

    /// Per-project skill directories that exist under the project's working dir.
    /// Covers the common harness layouts:
    ///   - <project>/.claude/skills        (Claude Code — pi does NOT auto-discover)
    ///   - <project>/.pi/skills            (pi native — auto-discovered when trusted)
    ///   - <project>/.agents/skills        (shared — auto-discovered when trusted)
    ///   - <project>/.claude/plugins/marketplaces/<name>/skills (Claude plugins)
    /// We pass them all explicitly via `--skill` so they load regardless of pi's
    /// auto-discovery, and require `--approve` (project trust) in RPC mode.
    static func projectSkillDirectories(for workingDirectory: URL) -> [String] {
        let fm = FileManager.default
        var dirs: [URL] = [
            workingDirectory.appendingPathComponent(".claude/skills"),
            workingDirectory.appendingPathComponent(".pi/skills"),
            workingDirectory.appendingPathComponent(".agents/skills"),
        ]
        let marketplaces = workingDirectory.appendingPathComponent(".claude/plugins/marketplaces")
        if let entries = try? fm.contentsOfDirectory(at: marketplaces, includingPropertiesForKeys: nil) {
            for entry in entries { dirs.append(entry.appendingPathComponent("skills")) }
        }
        return dirs.filter { isDirectory($0) }.map { $0.path }
    }

    /// Full list of `--skill` paths for a given working directory: global dirs
    /// plus every per-project skill dir that exists. `needsApprove` is true when
    /// any project-local dir is present (project trust is required in RPC mode).
    static func skillPaths(for workingDirectory: URL) -> (paths: [String], needsApprove: Bool) {
        var paths = globalSkillDirectories()
        let projectDirs = projectSkillDirectories(for: workingDirectory)
        paths.append(contentsOf: projectDirs)
        return (paths, !projectDirs.isEmpty)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
