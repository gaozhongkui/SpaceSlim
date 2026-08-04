import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("General")) {
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.blue)
                        Text("Notifications")
                        Spacer()
                        Toggle("", isOn: .constant(true))
                    }

                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                        Text("Privacy Policy")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Clean Strategy")) {
                    HStack {
                        Text("Scan Depth")
                        Spacer()
                        Text("Standard")
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
