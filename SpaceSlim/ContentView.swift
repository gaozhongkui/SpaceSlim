//
//  ContentView.swift
//  SpaceSlim
//
//  Created by gaozhongkui on 2026/8/4.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Clean", systemImage: "trash")
                }

            Text("Compression List")
                .tabItem {
                    Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left.anywhere")
                }

            Text("Settings")
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
}
