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

    var body: some View {
        TabView {
            HomeView(photoService: photoService, videoService: videoService, storageService: storageService)
                .tabItem {
                    Label("Clean", systemImage: "trash")
                }

            NavigationStack {
                VideoCompressionView(videoService: videoService)
            }
            .tabItem {
                Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left.anywhere")
            }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
}
