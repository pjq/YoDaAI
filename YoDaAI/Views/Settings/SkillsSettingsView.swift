//
//  SkillsSettingsView.swift
//  YoDaAI
//
//  Shows the skill directories the pi agent loads from and the skills it has
//  discovered. Read-only for now: skills are managed by dropping SKILL.md
//  folders into the source directories (~/.claude/skills, ~/.agents/skills, or
//  a project's .claude/skills). pi discovers them; we surface them here.
//

import SwiftUI
import SwiftData

struct SkillsSettingsView: View {
    @ObservedObject private var llmSettings = LLMSettings.shared
    @Query(sort: [SortDescriptor(\LLMProvider.updatedAt, order: .reverse)])
    private var providers: [LLMProvider]

    @State private var skills: [PiChatEngine.DiscoveredCommand] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var defaultProvider: LLMProvider? {
        providers.first(where: { $0.isDefault }) ?? providers.first
    }

    private var sourceDirectories: [String] {
        PiSkillsConfig.globalSkillDirectories()
    }

    var body: some View {
        Form {
            if !llmSettings.usePiAgent {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Skills require the pi agent", systemImage: "exclamationmark.triangle")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.orange)
                        Text("Skills are a pi-agent capability. The direct OpenAI-compatible client does not use them. Enable the pi agent to discover and run skills.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Enable pi agent") { llmSettings.usePiAgent = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Text("Skills are self-contained capability packages the agent loads on demand. They are discovered by the pi agent from the directories below. Add a skill by placing its folder (with a SKILL.md) into one of these directories.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Skill Directories") {
                if sourceDirectories.isEmpty {
                    Text("No skill directories found. Create ~/.claude/skills or ~/.agents/skills.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sourceDirectories, id: \.self) { dir in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(dir)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                NSWorkspace.shared.open(URL(fileURLWithPath: dir))
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                            }
                            .buttonStyle(.borderless)
                            .help("Reveal in Finder")
                        }
                    }
                }
                Text("Per-project skills (a project's .claude/skills) are loaded automatically when you chat inside that project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if !llmSettings.usePiAgent {
                    Text("Enable the pi agent to discover skills.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isLoading {
                    HStack { ProgressView().controlSize(.small); Text("Discovering skills…").foregroundStyle(.secondary) }
                } else if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if skills.isEmpty {
                    Text("No skills discovered yet. Click Refresh after adding skill folders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(skills) { skill in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("/\(skill.name)")
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                Spacer()
                                Text(skill.source)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            if !skill.description.isEmpty {
                                Text(skill.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                HStack {
                    Text("Discovered Skills")
                    Spacer()
                    Button("Refresh") { Task { await refresh() } }
                        .controlSize(.small)
                        .disabled(isLoading || !llmSettings.usePiAgent)
                }
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        guard llmSettings.usePiAgent else { skills = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let scratch = PiExecutable.scratchDirectory()
        let all = await PiChatEngine.shared.discoverCommands(workingDirectory: scratch)
        skills = all.filter { $0.source == "skill" }
        if all.isEmpty {
            errorMessage = "Could not reach the pi agent. Build it (../pi: npm run build) or bundle the binary."
        }
    }
}
