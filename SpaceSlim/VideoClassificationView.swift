import SwiftUI
import Photos

struct VideoClassificationView: View {
    @ObservedObject var videoService: VideoService

    var body: some View {
        List {
            Section(header: Text("Screen Recordings (\(videoService.screenRecordings.count))")) {
                if videoService.screenRecordings.isEmpty && !videoService.isScanning {
                    Text("No screen recordings").foregroundStyle(.secondary)
                } else {
                    VideoGridView(assets: videoService.screenRecordings)
                }
            }

            Section(header: Text("Camera Videos (\(videoService.cameraVideos.count))")) {
                if videoService.cameraVideos.isEmpty && !videoService.isScanning {
                    Text("No camera videos").foregroundStyle(.secondary)
                } else {
                    VideoGridView(assets: videoService.cameraVideos)
                }
            }
        }
        .navigationTitle("Video Classification")
        .overlay {
            if videoService.isScanning {
                ProgressView("Classifying...")
            }
        }
    }
}

struct VideoGridView: View {
    let assets: [PHAsset]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    VideoThumbnailView(asset: asset)
                }
            }
            .padding(.vertical, 5)
        }
    }
}

struct VideoThumbnailView: View {
    let asset: PHAsset
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 160)
                    .clipped()
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 160)
                    .cornerRadius(8)
                    .onAppear {
                        loadThumbnail()
                    }
            }

            Text(formatDuration(asset.duration))
                .font(.caption2)
                .padding(4)
                .background(.black.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(4)
                .padding(4)
        }
    }

    private func loadThumbnail() {
        let manager = PHImageManager.default()
        manager.requestImage(for: asset, targetSize: CGSize(width: 240, height: 320), contentMode: .aspectFill, options: nil) { img, _ in
            self.thumbnail = img
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
}
