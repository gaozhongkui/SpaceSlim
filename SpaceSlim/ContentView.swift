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
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(photoService: photoService, videoService: videoService, storageService: storageService, selectedTab: $selectedTab)
            }
            .tabItem {
                Label("Clean", systemImage: "trash")
            }
            .tag(0)

            NavigationStack {
                VideoCompressionView(videoService: videoService)
                    .ignoresSafeArea(edges: .bottom)
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

#Preview {
    ContentView()
}
