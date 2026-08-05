import SwiftUI

struct SettingsView: View {
    @AppStorage("scanDepth") private var scanDepth = "standard"
    @AppStorage("autoScan") private var autoScan = true

    @State private var showPrivacy = false
    @State private var cacheCleared = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(selection: $scanDepth) {
                        Text("Standard").tag("standard")
                        Text("Deep").tag("deep")
                    } label: {
                        Label("Scan Depth", systemImage: "magnifyingglass")
                    }

                    Toggle(isOn: $autoScan) {
                        Label("Scan on open", systemImage: "sparkles")
                    }
                } header: {
                    Text("Clean Strategy")
                } footer: {
                    Text(scanDepth == "deep"
                         ? "Deep flags more borderline-blurry photos — slower but more thorough."
                         : "Standard flags only clearly blurry photos.")
                }

                Section {
                    Button {
                        clearTemporaryFiles()
                    } label: {
                        HStack {
                            Label("Clear temporary files", systemImage: "trash")
                            Spacer()
                            if cacheCleared {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .tint(.primary)
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Removes leftover temporary files (e.g. from interrupted compressions).")
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        showPrivacy = true
                    } label: {
                        HStack {
                            Text("Privacy Policy")
                                .tint(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPrivacy) {
                PrivacyPolicyView()
            }
        }
    }

    private func clearTemporaryFiles() {
        let fileManager = FileManager.default
        let tmp = fileManager.temporaryDirectory
        if let contents = try? fileManager.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for url in contents {
                try? fileManager.removeItem(at: url)
            }
        }
        withAnimation { cacheCleared = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { cacheCleared = false }
        }
    }
}

// MARK: - Privacy policy

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your privacy")
                        .font(.title2.bold())

                    Text("SpaceSlim works entirely on your device. It reads your photo library only to find items you can clean up — similar and duplicate photos, blurry shots, large videos, screenshots, and screen recordings.")

                    Text("What we access")
                        .font(.headline)
                    Text("• Your photo library, to scan and classify media.\n• On-device storage information, to show how full your device is.")

                    Text("What we don't do")
                        .font(.headline)
                    Text("• Nothing is uploaded to any server.\n• No analytics or tracking.\n• Deletions and compressions happen locally, and always go through the system's own confirmation.")

                    Text("You stay in control")
                        .font(.headline)
                    Text("You choose what to delete or compress. You can revoke photo access any time in the Settings app.")
                }
                .padding(20)
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
