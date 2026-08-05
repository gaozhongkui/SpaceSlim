import SwiftUI
import Photos
import AVFoundation

// MARK: - Sort order

enum VideoSortOrder {
    case largestFirst
    case smallestFirst
}

// MARK: - Compress tab

/// SwiftUI video-compression list, styled to match the home dashboard (glass
/// cards, gradient accents, rounded type). Fetches every video, lets the user
/// multi-select, then presents `CompressionOptionsView` full-screen to run the
/// batch. `sortOrder` is driven by the toolbar menu in `ContentView`.
struct VideoCompressionView: View {
    @ObservedObject var videoService: VideoService

    @State private var sortOrder: VideoSortOrder = .largestFirst
    @State private var videos: [PHAsset] = []
    @State private var sizeCache: [String: Int64] = [:]
    @State private var selected: Set<String> = []
    @State private var hasLoaded = false
    @State private var showOptions = false

    private var totalBytes: Int64 { videos.reduce(0) { $0 + (sizeCache[$1.localIdentifier] ?? 0) } }
    private var selectedBytes: Int64 {
        selected.reduce(0) { $0 + (sizeCache[$1] ?? 0) }
    }
    private var estimatedSavings: Int64 { Int64(Double(selectedBytes) * 0.5) }

    private var selectedAssets: [PHAsset] {
        videos.filter { selected.contains($0.localIdentifier) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            HomeBackground()

            if hasLoaded && videos.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        summaryCard
                        ForEach(videos, id: \.localIdentifier) { asset in
                            VideoRow(
                                asset: asset,
                                sizeText: Self.sizeString(sizeCache[asset.localIdentifier] ?? 0),
                                isSelected: selected.contains(asset.localIdentifier)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { toggle(asset) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, selected.isEmpty ? 96 : 120)
                }
            }

            if !selected.isEmpty {
                compressBar
            }
        }
        .onAppear { if !hasLoaded { fetch() } }
        .onChange(of: sortOrder) { _ in applySort() }
        .fullScreenCover(isPresented: $showOptions) {
            NavigationStack {
                CompressionOptionsView(videoService: videoService, assets: selectedAssets) { _, _, _ in
                    selected.removeAll()
                    fetch()
                    showOptions = false   // dismiss the whole presented flow back to the list
                }
            }
        }
    }

    // MARK: - Sections

    private var summaryCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [.ssViolet, Color(red: 0.298, green: 0.247, blue: 0.796)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                    .shadow(color: .ssViolet.opacity(0.4), radius: 8, y: 4)
                Image(systemName: "film.stack")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(videos.count)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.ssTextPrimary)
                    Text(videos.count == 1 ? "video" : "videos")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.ssTextSecondary)
                }
                Text("\(Self.sizeString(totalBytes)) total")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ssTextTertiary)
            }

            Spacer()

            sortMenu
        }
        .padding(14)
        .glassCard(radius: 22)
        .padding(.bottom, 4)
    }

    private var sortMenu: some View {
        Menu {
            Button {
                sortOrder = .largestFirst
            } label: {
                Label("Largest first", systemImage: sortOrder == .largestFirst ? "checkmark" : "arrow.down.to.line")
            }
            Button {
                sortOrder = .smallestFirst
            } label: {
                Label("Smallest first", systemImage: sortOrder == .smallestFirst ? "checkmark" : "arrow.up.to.line")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: sortOrder == .largestFirst ? "arrow.down" : "arrow.up")
                    .font(.system(size: 10, weight: .heavy))
                Text(sortOrder == .largestFirst ? "Largest" : "Smallest")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .heavy))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(LinearGradient(colors: [.ssViolet, Color(red: 0.42, green: 0.38, blue: 0.9)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: .ssViolet.opacity(0.35), radius: 6, y: 3)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.ssViolet.opacity(0.14))
                    .frame(width: 96, height: 96)
                Image(systemName: "film.stack")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.ssViolet)
            }
            Text("No videos found")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ssTextPrimary)
            Text("Videos in your library will show up here,\nready to shrink without losing them.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ssTextTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 60)
    }

    private var compressBar: some View {
        VStack(spacing: 0) {
            Button {
                showOptions = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 16, weight: .bold))
                    Text("Compress \(selected.count)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 13, weight: .bold))
                        Text("save ~\(Self.sizeString(estimatedSavings))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .opacity(0.95)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 58)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing))
                )
                .shadow(color: .ssViolet.opacity(0.4), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)   // sit just above the floating tab bar
        }
        .background(
            LinearGradient(colors: [.clear, Color.ssBackground.opacity(0.001)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected.isEmpty)
    }

    // MARK: - Actions

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func fetch() {
        DispatchQueue.global(qos: .userInitiated).async {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: .video, options: options)
            var assets: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in assets.append(asset) }

            var cache: [String: Int64] = [:]
            for asset in assets {
                let resources = PHAssetResource.assetResources(for: asset)
                cache[asset.localIdentifier] = resources.first?.value(forKey: "fileSize") as? Int64 ?? 0
            }

            DispatchQueue.main.async {
                self.sizeCache = cache
                self.videos = assets
                self.selected.formIntersection(Set(assets.map(\.localIdentifier)))
                self.applySort()
                self.hasLoaded = true
            }
        }
    }

    private func applySort() {
        videos.sort { lhs, rhs in
            let a = sizeCache[lhs.localIdentifier] ?? 0
            let b = sizeCache[rhs.localIdentifier] ?? 0
            return sortOrder == .largestFirst ? a > b : a < b
        }
    }

    // MARK: - Formatting

    static func sizeString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Row

private struct VideoRow: View {
    let asset: PHAsset
    let sizeText: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 13) {
            VideoThumbnail(asset: asset)

            VStack(alignment: .leading, spacing: 4) {
                Text("Video · \(Self.durationString(asset.duration))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ssTextPrimary)
                    .lineLimit(1)
                if let date = asset.creationDate {
                    Text(Self.dateFormatter.string(from: date))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ssTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(sizeText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.ssTextSecondary)

            ZStack {
                Circle()
                    .strokeBorder(isSelected ? Color.clear : Color.ssTextTertiary.opacity(0.5), lineWidth: 1.8)
                    .frame(width: 24, height: 24)
                if isSelected {
                    Circle()
                        .fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 24, height: 24)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(12)
        .glassCard(radius: 18, tint: isSelected ? .ssViolet : .clear)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.ssViolet.opacity(0.7) : Color.clear, lineWidth: 1.8)
        )
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static func durationString(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Thumbnail

/// Async photo-library thumbnail with a duration/play overlay.
private struct VideoThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    private static let manager = PHCachingImageManager()

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color.ssTrack)
            }

            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        )
        .onAppear(perform: load)
    }

    private func load() {
        guard image == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let id = asset.localIdentifier
        Self.manager.requestImage(for: asset,
                                  targetSize: CGSize(width: 160, height: 160),
                                  contentMode: .aspectFill,
                                  options: options) { result, _ in
            guard asset.localIdentifier == id, let result else { return }
            self.image = result
        }
    }
}
