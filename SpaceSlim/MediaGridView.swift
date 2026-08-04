import SwiftUI
import Photos
import AVKit

// MARK: - Media grid detail page

/// A reusable detail page for one cleanup category: a thumbnail grid whose
/// items can be previewed/played (tap the thumbnail) or selected (tap the
/// corner check), with a bottom bar to delete the selection. Deletion here is
/// unrelated to compression.
struct MediaGridView: View {
    let title: String
    /// Lazily supplies the assets; run off the main body so building the
    /// NavigationLink destination stays cheap.
    let load: () -> [PHAsset]

    @State private var assets: [PHAsset] = []
    @State private var selectedIDs = Set<String>()
    @State private var previewItem: PreviewItem?
    @State private var isLoading = true
    @State private var isDeleting = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 3)]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.ssBackground.ignoresSafeArea()

            if isLoading {
                ProgressView()
            } else if assets.isEmpty {
                emptyState
            } else {
                grid
            }

            if !selectedIDs.isEmpty {
                deleteBar
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard assets.isEmpty else { return }
            let loaded = load()
            await MainActor.run {
                assets = loaded
                isLoading = false
            }
        }
        .fullScreenCover(item: $previewItem) { item in
            MediaPreviewView(asset: item.asset)
        }
        .overlay {
            if isDeleting {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Deleting…")
                        .padding(20)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    MediaGridCell(
                        asset: asset,
                        isSelected: selectedIDs.contains(asset.localIdentifier),
                        onOpen: { previewItem = PreviewItem(asset: asset) },
                        onToggle: { toggle(asset) }
                    )
                }
            }
            .padding(3)
            .padding(.bottom, selectedIDs.isEmpty ? 12 : 88)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44))
                .foregroundStyle(Color.ssTeal)
            Text("Nothing here")
                .font(.headline)
                .foregroundStyle(Color.ssTextPrimary)
            Text("This category has no items.")
                .font(.subheadline)
                .foregroundStyle(Color.ssTextSecondary)
        }
    }

    private var deleteBar: some View {
        HStack {
            Text("\(selectedIDs.count) selected")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ssTextSecondary)
            Spacer()
            Button(role: .destructive) {
                deleteSelected()
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.ssCoral))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground).ignoresSafeArea(edges: .bottom))
    }

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func deleteSelected() {
        let toDelete = assets.filter { selectedIDs.contains($0.localIdentifier) }
        guard !toDelete.isEmpty else { return }
        isDeleting = true
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
        } completionHandler: { success, _ in
            DispatchQueue.main.async {
                isDeleting = false
                if success {
                    let deleted = Set(toDelete.map(\.localIdentifier))
                    assets.removeAll { deleted.contains($0.localIdentifier) }
                    selectedIDs.removeAll()
                }
            }
        }
    }
}

/// Identifiable wrapper so a PHAsset can drive `.fullScreenCover(item:)`.
struct PreviewItem: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

// MARK: - Grid cell

private struct MediaGridCell: View {
    let asset: PHAsset
    let isSelected: Bool
    let onOpen: () -> Void
    let onToggle: () -> Void

    @State private var image: UIImage?
    private let manager = PHImageManager.default()

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .topTrailing) {
                        Rectangle().fill(Color.ssTrack)

                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }

                        // Video indicator (play + duration).
                        if asset.mediaType == .video {
                            VStack {
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill").font(.system(size: 9))
                                    Text(Self.durationString(asset.duration)).font(.system(size: 10, weight: .semibold))
                                    Spacer()
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .bottom, endPoint: .top))
                            }
                        }

                        // Selection toggle (separate hit target from the thumbnail tap).
                        Button(action: onToggle) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(isSelected ? Color.ssViolet : Color.white)
                                .background(Circle().fill(isSelected ? Color.white : Color.black.opacity(0.25)).padding(2))
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen() }
                }
            }
            .onAppear(perform: loadThumbnail)
    }

    private func loadThumbnail() {
        guard image == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        manager.requestImage(for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: options) { img, _ in
            if let img { self.image = img }
        }
    }

    private static func durationString(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Full-screen preview (photo or video)

struct MediaPreviewView: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if asset.mediaType == .video {
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    ProgressView().tint(.white)
                }
            } else {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 4)
                    }
                    .padding(16)
                }
                Spacer()
            }
        }
        .onAppear(perform: loadMedia)
        .onDisappear { player?.pause() }
    }

    private func loadMedia() {
        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                DispatchQueue.main.async {
                    guard let item else { return }
                    let p = AVPlayer(playerItem: item)
                    self.player = p
                    p.play()
                }
            }
        } else {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { img, _ in
                DispatchQueue.main.async {
                    if let img { self.image = img }
                }
            }
        }
    }
}

// MARK: - Grouped detail page (Similar photos / Duplicates)

/// Detail page for grouped results. Each group shows its photos in a grid; by
/// default the first photo in a group is kept and the rest are pre-selected for
/// deletion — the usual "keep one, remove the copies" flow. Same preview and
/// delete affordances as `MediaGridView`.
struct PhotoGroupsView: View {
    let title: String
    let groups: [PhotoGroup]

    @State private var localGroups: [PhotoGroup] = []
    @State private var selectedIDs = Set<String>()
    @State private var previewItem: PreviewItem?
    @State private var isDeleting = false
    @State private var didInit = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 3)]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.ssBackground.ignoresSafeArea()

            if localGroups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(localGroups) { group in
                            groupSection(group)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.bottom, selectedIDs.isEmpty ? 12 : 88)
                }
            }

            if !selectedIDs.isEmpty {
                deleteBar
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didInit else { return }
            didInit = true
            localGroups = groups
            var preselect = Set<String>()
            for group in groups {
                for asset in group.assets.dropFirst() {
                    preselect.insert(asset.localIdentifier)
                }
            }
            selectedIDs = preselect
        }
        .fullScreenCover(item: $previewItem) { item in
            MediaPreviewView(asset: item.asset)
        }
        .overlay {
            if isDeleting {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Deleting…")
                        .padding(20)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func groupSection(_ group: PhotoGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(group.assets.count) photos")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.ssTextSecondary)
                Spacer()
                Text("Keep 1")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ssTeal)
            }
            .padding(.horizontal, 12)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(group.assets, id: \.localIdentifier) { asset in
                    MediaGridCell(
                        asset: asset,
                        isSelected: selectedIDs.contains(asset.localIdentifier),
                        onOpen: { previewItem = PreviewItem(asset: asset) },
                        onToggle: { toggle(asset) }
                    )
                }
            }
            .padding(.horizontal, 3)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44))
                .foregroundStyle(Color.ssTeal)
            Text("Nothing here")
                .font(.headline)
                .foregroundStyle(Color.ssTextPrimary)
            Text("Your library looks clean.")
                .font(.subheadline)
                .foregroundStyle(Color.ssTextSecondary)
        }
    }

    private var deleteBar: some View {
        HStack {
            Text("\(selectedIDs.count) selected")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ssTextSecondary)
            Spacer()
            Button(role: .destructive) {
                deleteSelected()
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.ssCoral))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground).ignoresSafeArea(edges: .bottom))
    }

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func deleteSelected() {
        let ids = selectedIDs
        let toDelete = localGroups.flatMap(\.assets).filter { ids.contains($0.localIdentifier) }
        guard !toDelete.isEmpty else { return }
        isDeleting = true
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
        } completionHandler: { success, _ in
            DispatchQueue.main.async {
                isDeleting = false
                if success {
                    // Drop deleted assets; a group with ≤1 photo left is no longer a match.
                    localGroups = localGroups.compactMap { group in
                        let remaining = group.assets.filter { !ids.contains($0.localIdentifier) }
                        return remaining.count > 1 ? PhotoGroup(assets: remaining) : nil
                    }
                    selectedIDs.removeAll()
                }
            }
        }
    }
}
