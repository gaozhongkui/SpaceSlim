import SwiftUI
import Photos

struct DuplicatePhotosView: View {
    @ObservedObject var photoService: PhotoService

    var body: some View {
        VStack {
            if photoService.isScanning {
                VStack(spacing: 20) {
                    ProgressView(value: photoService.progress)
                        .progressViewStyle(.linear)
                        .padding()
                    Text("Scanning duplicates... \(Int(photoService.progress * 100))%")
                }
            } else if photoService.duplicateGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.stack")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Duplicates")
                        .font(.headline)
                    Text("No exact duplicate photos found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(photoService.duplicateGroups) { group in
                        Section(header: Text("Duplicate Group (\(group.assets.count) photos)")) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(group.assets, id: \.localIdentifier) { asset in
                                        AssetItemView(asset: asset)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !photoService.duplicateGroups.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button(action: {
                        // Cleanup logic
                    }) {
                        Text("Clean All Duplicates")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DuplicatePhotosView(photoService: PhotoService())
    }
}
