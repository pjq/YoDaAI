//
//  ApprovalSheet.swift
//  YoDaAI
//
//  Presents pi extension-UI dialog requests (select / confirm / input / editor)
//  as a native sheet and returns the user's decision. This is the "Ask for
//  approval" affordance for pi-driven tool gating.
//

import SwiftUI

/// A pending pi dialog request bound to a completion handler. The handler is
/// called exactly once with the reply to send back to pi (or nil to cancel).
@MainActor
final class PiApprovalRequest: Identifiable {
    let id: String
    let request: PiExtensionUIRequest
    private let complete: (PiExtensionUIResponse?) -> Void

    init(request: PiExtensionUIRequest, complete: @escaping (PiExtensionUIResponse?) -> Void) {
        self.id = request.id
        self.request = request
        self.complete = complete
    }

    func respond(_ response: PiExtensionUIResponse?) { complete(response) }
}

struct ApprovalSheet: View {
    let approval: PiApprovalRequest
    @State private var inputText: String = ""

    private var req: PiExtensionUIRequest { approval.request }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                Text(req.title ?? "Agent request")
                    .font(.headline)
            }

            if let message = req.message, !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content

            Divider()

            actions
        }
        .padding(20)
        .frame(minWidth: 420, maxWidth: 560)
        .onAppear { inputText = req.prefill ?? "" }
    }

    private var icon: String {
        switch req.method {
        case "confirm": return "questionmark.circle"
        case "select": return "checklist"
        case "input": return "text.cursor"
        case "editor": return "square.and.pencil"
        default: return "bell"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch req.method {
        case "input":
            TextField(req.placeholder ?? "", text: $inputText)
                .textFieldStyle(.roundedBorder)
        case "editor":
            TextEditor(text: $inputText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack {
            Button("Cancel") { approval.respond(.cancel(id: req.id)) }
                .keyboardShortcut(.cancelAction)
            Spacer()
            switch req.method {
            case "select":
                ForEach(req.options ?? [], id: \.self) { option in
                    Button(option) { approval.respond(.value(option, id: req.id)) }
                        .buttonStyle(.borderedProminent)
                }
            case "confirm":
                Button("Deny") { approval.respond(.confirm(false, id: req.id)) }
                Button("Allow") { approval.respond(.confirm(true, id: req.id)) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case "input", "editor":
                Button("Submit") { approval.respond(.value(inputText, id: req.id)) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            default:
                Button("OK") { approval.respond(.cancel(id: req.id)) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
