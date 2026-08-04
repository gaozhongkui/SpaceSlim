import SwiftUI
import Photos

struct VideoCompressionView: View {
    @StateObject private var videoService = VideoService()
    @State private var allVideos: [PHAsset] = []

    var body: some View {
        List(allVideos, id: \.localIdentifier) { asset in
            HStack {
                VideoThumbnailView(asset: asset)
                    .frame(width: 60, height: 60)

                VStack(alignment: .leading) {
                    Text("Video - \(formatDuration(asset.duration))")
                        .font(.subheadline)
                    Text("Created: \(asset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Compress") {
                    Task {
                        await videoService.compressVideo(asset: asset, quality: "Medium")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .navigationTitle("Video Compression")
        .overlay {
            if videoService.isCompressing {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView(value: videoService.compressionProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                        Text("Compressing... \(Int(videoService.compressionProgress * 100))%")
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
            }
        }
        .onAppear {
            fetchAllVideos()
        }
    }

    private func fetchAllVideos() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .video, options: fetchOptions)
        var assets: [PHAsset] = []
        result.enumerateObjects { (asset, _, _) in
            assets.append(asset)
        }
        self.allVideos = assets
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
}
