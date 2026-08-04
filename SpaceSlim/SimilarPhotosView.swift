import SwiftUI
import Photos

struct SimilarPhotosView: View {
    @ObservedObject var photoService: PhotoService

    var body: some View {
        VStack {
            if photoService.isScanning {
                VStack(spacing: 20) {
                    ProgressView(value: photoService.progress)
                        .progressViewStyle(.linear)
                        .padding()
                    Text("Scanning photos... \(Int(photoService.progress * 100))%")
                }
            } else if photoService.similarGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Similar Photos")
                        .font(.headline)
                    Text("Results will appear here after scanning")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(photoService.similarGroups) { group in
                        Section(header: Text("Similar Group (\(group.assets.count) photos)")) {
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
        .navigationTitle("Similar Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !photoService.similarGroups.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button(action: {
                        // Cleanup logic
                    }) {
                        Text("Clean Selected")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
        }
    }
}

struct AssetItemView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var isSelected = false
    @State private var fileSize: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            ZStack(alignment: .topTrailing) {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 150, height: 150)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 150, height: 150)
                        .cornerRadius(8)
                        .onAppear {
                            loadThumbnail()
                            loadSize()
                        }
                }

                Button(action: {
                    isSelected.toggle()
                }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? .blue : .white)
                        .padding(8)
                        .shadow(radius: 2)
                }
            }

            Text(fileSize)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadThumbnail() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        manager.requestImage(for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: options) { result, _ in
            self.image = result
        }
    }

    private func loadSize() {
        let resources = PHAssetResource.assetResources(for: asset)
        if let resource = resources.first {
            if let size = resource.value(forKey: "fileSize") as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                self.fileSize = formatter.string(fromByteCount: size)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SimilarPhotosView(photoService: PhotoService())
    }
}
