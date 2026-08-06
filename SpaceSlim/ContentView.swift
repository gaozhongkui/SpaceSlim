//
//  ContentView.swift
//  SpaceSlim
//
//  Created by gaozhongkui on 2026/8/4.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var photoService = PhotoService()
    @StateObject private var videoService = VideoService()
    @StateObject private var storageService = StorageService()
    @StateObject private var historyStore = CleanupHistoryStore()
    @State private var selectedTab = 0

    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showOnboarding = false

    var body: some View {
        tabView
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView { didOnboard = true; showOnboarding = false }
            }
            .onAppear { showOnboarding = !didOnboard }
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(photoService: photoService, videoService: videoService, storageService: storageService, historyStore: historyStore, selectedTab: $selectedTab)
            }
            .tabItem {
                Label("Clean", systemImage: "trash")
            }
            .tag(0)

            NavigationStack {
                VideoCompressionView(videoService: videoService)
                    .navigationTitle("Compress")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Compress", systemImage: "rectangle.compress.vertical")
            }
            .tag(1)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
            .tag(2)
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    let onGetStarted: () -> Void

    var body: some View {
        ZStack {
            HomeBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 92, height: 92)
                        .shadow(color: .ssViolet.opacity(0.45), radius: 16, y: 8)
                    Image(systemName: "sparkles")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("SpaceSlim")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ssTextPrimary)
                    .padding(.top, 16)
                Text("Free up space without\nlosing your memories")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ssTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)

                Spacer(minLength: 24)

                VStack(spacing: 16) {
                    feature("rectangle.compress.vertical", .ssViolet, "Compress videos",
                            "Shrink large videos, keep the quality")
                    feature("wand.and.stars", .ssTeal, "Clean up smartly",
                            "Find similar, duplicate & blurry photos")
                    feature("lock.fill", .ssSky, "100% on-device",
                            "No account, no uploads — fully private")
                }

                Spacer(minLength: 24)

                Button(action: onGetStarted) {
                    Text("Get Started")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing)))
                        .shadow(color: .ssViolet.opacity(0.4), radius: 14, y: 8)
                }
                .buttonStyle(.plain)

                Text("Next, we'll ask for photo access to scan your library.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ssTextTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
        }
    }

    private func feature(_ icon: String, _ color: Color, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ssTextPrimary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ssTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(radius: 18)
    }
}

#Preview {
    ContentView()
}
