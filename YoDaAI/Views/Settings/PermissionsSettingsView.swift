//
//  PermissionsSettingsView.swift
//  YoDaAI
//
//  Extracted from ContentView.swift
//

import SwiftUI
import SwiftData

struct PermissionsSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\AppPermissionRule.updatedAt, order: .reverse)])
    private var permissionRules: [AppPermissionRule]
    
    @State private var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var refreshTimer: Timer?

    var body: some View {
        Form {
            Section("Accessibility Permission") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: isAccessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(isAccessibilityGranted ? Color.green : Color.red)
                                .font(.title2)
                            Text(isAccessibilityGranted ? "Granted" : "Not Granted")
                                .font(.headline)
                                .foregroundStyle(isAccessibilityGranted ? Color.primary : Color.red)
                        }
                        Text("Required to capture content from other apps and insert text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    // Refresh button
                    Button {
                        checkAccessibilityPermission()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh status")
                    
                    if !isAccessibilityGranted {
                        Button("Grant Access") {
                            requestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Open Settings") {
                            openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
                
                if !isAccessibilityGranted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to enable:")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("1. Click \"Grant Access\" to open System Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("2. Find YoDaAI in the list and enable the toggle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("3. Click the refresh button or restart YoDaAI")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            
            Section("Automation Permission") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.2")
                            .foregroundStyle(.blue)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Required for App Control")
                                .font(.headline)
                            Text("Click each app below to trigger the permission request")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                
                // App permission request buttons
                AutomationAppRow(appName: "Safari", bundleId: "com.apple.Safari", icon: "safari")
                AutomationAppRow(appName: "Google Chrome", bundleId: "com.google.Chrome", icon: "globe")
                AutomationAppRow(appName: "Notes", bundleId: "com.apple.Notes", icon: "note.text")
                AutomationAppRow(appName: "Mail", bundleId: "com.apple.mail", icon: "envelope")
                AutomationAppRow(appName: "TextEdit", bundleId: "com.apple.TextEdit", icon: "doc.text")
                
                HStack {
                    Spacer()
                    Button("Open Automation Settings") {
                        openAutomationSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note: Permission dialogs only appear once per app. If you previously denied, use \"Open Automation Settings\" to enable manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            Section("Per-App Permissions") {
                if permissionRules.isEmpty {
                    Text("No apps recorded yet. Use @ mentions or enable auto-context to populate this list.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(permissionRules) { rule in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(rule.displayName)
                                Text(rule.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            
                            VStack {
                                Text("Context")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Toggle("Context", isOn: Binding(get: {
                                    rule.allowContext
                                }, set: { newValue in
                                    rule.allowContext = newValue
                                    rule.updatedAt = Date()
                                    try? modelContext.save()
                                }))
                                .toggleStyle(.switch)
                                .labelsHidden()
                            }
                            
                            VStack {
                                Text("Insert")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Toggle("Insert", isOn: Binding(get: {
                                    rule.allowInsert
                                }, set: { newValue in
                                    rule.allowInsert = newValue
                                    rule.updatedAt = Date()
                                    try? modelContext.save()
                                }))
                                .toggleStyle(.switch)
                                .labelsHidden()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            checkAccessibilityPermission()
            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
    }
    
    private func checkAccessibilityPermission() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }
    
    private func startRefreshTimer() {
        // Check every 2 seconds while the view is visible
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            DispatchQueue.main.async {
                checkAccessibilityPermission()
            }
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func requestAccessibilityPermission() {
        // First try to trigger the system prompt (works only on first request)
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        let result = AXIsProcessTrustedWithOptions(options)
        
        // If still not trusted, the prompt may not have shown (already denied before)
        // In that case, open System Settings directly
        if !result {
            openAccessibilitySettings()
        }
    }
    
    private func openAccessibilitySettings() {
        // Try the modern macOS 13+ URL first
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openAutomationSettings() {
        // Open Automation section in Privacy & Security
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Automation App Row
private struct AutomationAppRow: View {
    let appName: String
    let bundleId: String
    let icon: String

    @State private var status: PermissionStatus = .unknown
    @State private var isRequesting = false
    @State private var showInfoAlert = false
    
    enum PermissionStatus {
        case unknown
        case requesting
        case granted
        case denied
        case notInstalled
    }
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            
            Text(appName)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            switch status {
            case .unknown:
                Button("Request Permission") {
                    showInfoAlert = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRequesting)
                .alert("Request Automation Permission", isPresented: $showInfoAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Continue") {
                        requestPermission()
                    }
                } message: {
                    Text("YoDaAI will open \(appName) and try to control it.\n\nIf this is your FIRST time:\n• A permission dialog should appear\n• Click 'OK' or 'Allow' in the dialog\n• The dialog may appear behind other windows\n\nIf the dialog doesn't appear:\n• The permission may already be granted\n• Or you may need to check System Settings → Privacy & Security → Automation manually")
                }
                
            case .requesting:
                ProgressView()
                    .controlSize(.small)
                Text("Requesting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
            case .granted:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Granted")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                
            case .denied:
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Denied")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
            case .notInstalled:
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                    Text("Not Installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func requestPermission() {
        print("[AutomationAppRow] Requesting permission for \(appName) (\(bundleId))...")
        isRequesting = true
        status = .requesting
        
        // Run AppleScript in background to trigger permission dialog
        DispatchQueue.global(qos: .userInitiated).async {
            let result = triggerAutomationPermission(for: bundleId, appName: appName)
            
            DispatchQueue.main.async {
                print("[AutomationAppRow] Result for \(appName): \(result)")
                isRequesting = false
                status = result
            }
        }
    }
    
    private func triggerAutomationPermission(for bundleId: String, appName: String) -> PermissionStatus {
        print("[AutomationAppRow] Running AppleScript for \(appName)...")

        // First, try to launch the app using NSWorkspace (this doesn't require permission)
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            print("[AutomationAppRow] Found app at: \(appURL.path)")

            let config = NSWorkspace.OpenConfiguration()
            config.activates = true

            let semaphore = DispatchSemaphore(value: 0)
            var launchError: Error?

            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                launchError = error
                semaphore.signal()
            }

            semaphore.wait()

            if let error = launchError {
                print("[AutomationAppRow] Failed to launch \(appName): \(error)")
            } else {
                print("[AutomationAppRow] Launched \(appName), waiting for app to start...")
                // Wait longer for app to fully launch and be ready (especially Safari)
                Thread.sleep(forTimeInterval: 2.0)
            }
        } else {
            print("[AutomationAppRow] App not found: \(bundleId)")
            return .notInstalled
        }
        
        // Now run AppleScript to trigger the permission dialog
        // Using NSAppleScript directly since we're not sandboxed
        let script: String
        
        switch bundleId {
        case "com.apple.Safari":
            script = """
            tell application "Safari"
                count of windows
            end tell
            """
        case "com.google.Chrome":
            script = """
            tell application "Google Chrome"
                count of windows
            end tell
            """
        case "com.apple.Notes":
            script = """
            tell application "Notes"
                count of notes
            end tell
            """
        case "com.apple.mail":
            script = """
            tell application "Mail"
                count of mailboxes
            end tell
            """
        case "com.apple.TextEdit":
            script = """
            tell application "TextEdit"
                count of documents
            end tell
            """
        default:
            return .unknown
        }
        
        print("[AutomationAppRow] Executing AppleScript: \(script.prefix(50))...")
        
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            print("[AutomationAppRow] Failed to create AppleScript")
            return .unknown
        }
        
        let result = appleScript.executeAndReturnError(&error)
        
        if let error = error {
            let errorNumber = error["NSAppleScriptErrorNumber"] as? Int ?? 0
            let errorMessage = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown"
            print("[AutomationAppRow] AppleScript error for \(appName): [\(errorNumber)] \(errorMessage)")

            switch errorNumber {
            case -1743:
                print("[AutomationAppRow] ⚠️ Permission DENIED or NOT YET GRANTED for \(appName)")
                print("[AutomationAppRow] → The permission dialog should have appeared. If you missed it:")
                print("[AutomationAppRow] → Go to: System Settings → Privacy & Security → Automation")
                print("[AutomationAppRow] → Look for 'YoDaAI' and enable '\(appName)'")
                return .denied
            case -600:
                print("[AutomationAppRow] ⚠️ Error -600: \(appName) is not responding to AppleScript")
                print("[AutomationAppRow] → This usually means the app is still launching")
                print("[AutomationAppRow] → Try again in a few seconds")
                return .unknown
            default:
                print("[AutomationAppRow] ⚠️ Unknown AppleScript error")
                return .unknown
            }
        }

        print("[AutomationAppRow] ✅ AppleScript succeeded for \(appName)!")
        print("[AutomationAppRow] → Permission is GRANTED")
        print("[AutomationAppRow] → Result: \(result.stringValue ?? "nil")")
        return .granted
    }
}
