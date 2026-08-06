import SwiftUI

struct SettingsView: View {
    @AppStorage("scanDepth") private var scanDepth = "standard"
    @AppStorage("autoScan") private var autoScan = true

    @State private var showPrivacy = false
    @State private var cacheCleared = false
    @State private var showVault = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        brandHeader

                        privacyCard
                        cleanStrategyCard
                        storageCard
                        aboutCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPrivacy) {
                PrivacyPolicyView()
            }
            .fullScreenCover(isPresented: $showVault) {
                NavigationStack { VaultView() }
            }
        }
    }

    // MARK: - Header

    private var brandHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 76, height: 76)
                    .shadow(color: .ssViolet.opacity(0.4), radius: 12, y: 6)
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 3) {
                Text("SpaceSlim")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ssTextPrimary)
                Text("Version \(appVersion)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ssTextTertiary)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Cards

    private var privacyCard: some View {
        SettingsCard(title: "Privacy", footer: "Move photos & videos here to hide them from the Photos app — encrypted and locked behind Face ID.") {
            Button { showVault = true } label: {
                SettingsRow(icon: "lock.rectangle.stack.fill", color: .ssViolet, title: "Private Vault") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.ssTextTertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var cleanStrategyCard: some View {
        SettingsCard(title: "Clean strategy", footer: scanDepth == "deep"
                     ? "Deep flags more borderline-blurry photos — slower but more thorough."
                     : "Standard flags only clearly blurry photos.") {
            SettingsRow(icon: "magnifyingglass", color: .ssViolet, title: "Scan depth") {
                SegmentedControl(options: [("standard", "Standard"), ("deep", "Deep")], selection: $scanDepth)
            }
            RowDivider()
            SettingsRow(icon: "sparkles", color: .ssTeal, title: "Scan on open") {
                Toggle("", isOn: $autoScan).labelsHidden().tint(.ssViolet)
            }
        }
    }

    private var storageCard: some View {
        SettingsCard(title: "Storage", footer: "Removes leftover temporary files (e.g. from interrupted compressions).") {
            Button(action: clearTemporaryFiles) {
                SettingsRow(icon: "trash", color: .ssCoral, title: "Clear temporary files") {
                    if cacheCleared {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Cleared")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ssTeal)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.ssTextTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutCard: some View {
        SettingsCard(title: "About", footer: nil) {
            SettingsRow(icon: "info.circle", color: .ssIndigo, title: "Version") {
                Text(appVersion)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ssTextSecondary)
            }
            RowDivider()
            Button {
                showPrivacy = true
            } label: {
                SettingsRow(icon: "lock.shield", color: .ssSky, title: "Privacy Policy") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.ssTextTertiary)
                }
            }
            .buttonStyle(.plain)
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

// MARK: - Building blocks

private struct SettingsCard<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Color.ssTextTertiary)
                .padding(.leading, 6)

            VStack(spacing: 0) { content }
                .glassCard(radius: 20)

            if let footer {
                Text(footer)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ssTextTertiary)
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
            }
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let icon: String
    let color: Color
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(LocalizedStringKey(title))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ssTextPrimary)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.ssTextTertiary.opacity(0.15))
            .frame(height: 1)
            .padding(.leading, 56)
    }
}

private struct SegmentedControl: View {
    let options: [(key: String, label: String)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.key) { option in
                let selected = selection == option.key
                Text(LocalizedStringKey(option.label))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? .white : Color.ssTextSecondary)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(
                        Group {
                            if selected {
                                Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing))
                            } else {
                                Capsule().fill(Color.ssTextTertiary.opacity(0.12))
                            }
                        }
                    )
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = option.key }
                    }
            }
        }
    }
}

// MARK: - Privacy policy

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                HomeBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        section("Your privacy",
                                "SpaceSlim works entirely on your device. It reads your photo library only to find items you can clean up — similar and duplicate photos, blurry shots, large videos, screenshots, and screen recordings.")
                        section("What we access",
                                "• Your photo library, to scan and classify media.\n• On-device storage information, to show how full your device is.")
                        section("What we don't do",
                                "• Nothing is uploaded to any server.\n• No analytics or tracking.\n• Deletions and compressions happen locally, and always go through the system's own confirmation.")
                        section("You stay in control",
                                "You choose what to delete or compress. You can revoke photo access any time in the Settings app.")
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .tint(.ssViolet)
                }
            }
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ssTextPrimary)
            Text(body)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.ssTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(radius: 18)
    }
}
