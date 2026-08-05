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
    @State private var videoSort: VideoSortOrder = .largestFirst

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(photoService: photoService, videoService: videoService, storageService: storageService, historyStore: historyStore, selectedTab: $selectedTab)
            }
            .tabItem {
                Label("Clean", systemImage: "trash")
            }
            .tag(0)

            NavigationStack {
                VideoCompressionView(videoService: videoService, sortOrder: videoSort)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Compress")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                Picker("Sort", selection: $videoSort) {
                                    Label("Largest first", systemImage: "arrow.down").tag(VideoSortOrder.largestFirst)
                                    Label("Smallest first", systemImage: "arrow.up").tag(VideoSortOrder.smallestFirst)
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                            }
                        }
                    }
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
