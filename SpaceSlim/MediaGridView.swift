import SwiftUI
import Photos
import AVKit

// MARK: - Sort order

enum MediaSortOrder: Hashable {
    case largestFirst
    case smallestFirst
    case newestFirst
    case oldestFirst

    var label: String {
        switch self {
        case .largestFirst:  return "Largest"
        case .smallestFirst: return "Smallest"
        case .newestFirst:   return "Newest"
        case .oldestFirst:   return "Oldest"
        }
    }
    var icon: String {
        switch self {
        case .largestFirst:  return "arrow.down"
        case .smallestFirst: return "arrow.up"
        case .newestFirst:   return "clock"
        case .oldestFirst:   return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Media grid detail page

/// A reusable detail page for one cleanup category: a thumbnail grid whose
/// items can be previewed/played (tap the thumbnail) or selected (tap the
/// corner check), with a bottom bar to delete the selection. Presented as a
/// full-screen page, so it carries its own Close button.
struct MediaGridView: View {
    let title: String
    /// Lazily supplies the assets so building the destination stays cheap.
    let load: () -> [PHAsset]

    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var selectedIDs = Set<String>()
    @State private var previewItem: PreviewItem?
    @State private var isLoading = true
    @State private var isDeleting = false
    @State private var sortOrder: MediaSortOrder = .largestFirst
    @State private var sizeCache: [String: Int64] = [:]

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 170), spacing: 6)]

    private var totalBytes: Int64 { assets.reduce(0) { $0 + (sizeCache[$1.localIdentifier] ?? 0) } }
    private var selectedBytes: Int64 { selectedIDs.reduce(0) { $0 + (sizeCache[$1] ?? 0) } }

    private var sortedAssets: [PHAsset] {
        assets.sorted { lhs, rhs in
            switch sortOrder {
            case .largestFirst:  return (sizeCache[lhs.localIdentifier] ?? 0) > (sizeCache[rhs.localIdentifier] ?? 0)
            case .smallestFirst: return (sizeCache[lhs.localIdentifier] ?? 0) < (sizeCache[rhs.localIdentifier] ?? 0)
            case .newestFirst:   return (lhs.creationDate ?? .distantPast) > (rhs.creationDate ?? .distantPast)
            case .oldestFirst:   return (lhs.creationDate ?? .distantPast) < (rhs.creationDate ?? .distantPast)
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            HomeBackground()

            if isLoading {
                ProgressView().tint(.ssViolet)
            } else if assets.isEmpty {
                MediaEmptyState(subtitle: "This category has no items.")
            } else {
                VStack(spacing: 0) {
                    headerRow
                    grid
                }
            }

            if !selectedIDs.isEmpty {
                MediaDeleteBar(count: selectedIDs.count, sizeText: MediaFormat.bytes(selectedBytes),
                               onDeselect: { selectedIDs.removeAll() },
                               onDelete: deleteSelected)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { CloseButton { dismiss() } }
        }
        .task {
            guard assets.isEmpty else { return }
            let loaded = load()
            var cache: [String: Int64] = [:]
            for asset in loaded {
                let resources = PHAssetResource.assetResources(for: asset)
                cache[asset.localIdentifier] = resources.first?.value(forKey: "fileSize") as? Int64 ?? 0
            }
            await MainActor.run {
                assets = loaded
                sizeCache = cache
                isLoading = false
            }
        }
        .fullScreenCover(item: $previewItem) { item in
            MediaPreviewView(asset: item.asset)
        }
        .overlay { if isDeleting { DeletingOverlay() } }
    }

    private var headerRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(assets.count) item\(assets.count == 1 ? "" : "s")")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ssTextPrimary)
                Text("\(MediaFormat.bytes(totalBytes)) total")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ssTextTertiary)
            }
            Spacer()
            sortMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sortOrder) {
                Label("Largest first", systemImage: "arrow.down").tag(MediaSortOrder.largestFirst)
                Label("Smallest first", systemImage: "arrow.up").tag(MediaSortOrder.smallestFirst)
                Label("Newest first", systemImage: "clock").tag(MediaSortOrder.newestFirst)
                Label("Oldest first", systemImage: "clock.arrow.circlepath").tag(MediaSortOrder.oldestFirst)
            }
        } label: {
            SortPillLabel(icon: sortOrder.icon, text: sortOrder.label)
        }
    }

    private var grid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(sortedAssets, id: \.localIdentifier) { asset in
                    MediaGridCell(
                        asset: asset,
                        isSelected: selectedIDs.contains(asset.localIdentifier),
                        onOpen: { previewItem = PreviewItem(asset: asset) },
                        onToggle: { toggle(asset) }
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, selectedIDs.isEmpty ? 24 : 108)
        }
    }

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
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

// MARK: - Grouped detail page (Similar photos / Duplicates)

/// Detail page for grouped results. Each group shows its photos in a grid; by
/// default the first photo is kept and the rest are pre-selected for deletion —
/// the usual "keep one, remove the copies" flow.
struct PhotoGroupsView: View {
    let title: String
    let groups: [PhotoGroup]

    @Environment(\.dismiss) private var dismiss

    @State private var localGroups: [PhotoGroup] = []
    @State private var selectedIDs = Set<String>()
    @State private var previewItem: PreviewItem?
    @State private var isDeleting = false
    @State private var didInit = false

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 170), spacing: 6)]

    var body: some View {
        ZStack(alignment: .bottom) {
            HomeBackground()

            if localGroups.isEmpty {
                MediaEmptyState(subtitle: "Your library looks clean.")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(localGroups.enumerated()), id: \.element.id) { index, group in
                            groupSection(group, index: index)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, selectedIDs.isEmpty ? 24 : 108)
                }
            }

            if !selectedIDs.isEmpty {
                MediaDeleteBar(count: selectedIDs.count, sizeText: nil,
                               onDeselect: { selectedIDs.removeAll() },
                               onDelete: deleteSelected)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { CloseButton { dismiss() } }
        }
        .task {
            guard !didInit else { return }
            didInit = true
            localGroups = groups
            var preselect = Set<String>()
            for group in groups {
                for asset in group.assets.dropFirst() { preselect.insert(asset.localIdentifier) }
            }
            selectedIDs = preselect
        }
        .fullScreenCover(item: $previewItem) { item in
            MediaPreviewView(asset: item.asset)
        }
        .overlay { if isDeleting { DeletingOverlay() } }
    }

    private func groupSection(_ group: PhotoGroup, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Group \(index + 1)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ssTextPrimary)
                Text("\(group.assets.count) photos")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ssTextTertiary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11, weight: .bold))
                    Text("Keep 1")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color.ssTeal)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.ssTeal.opacity(0.15)))
            }
            .padding(.horizontal, 16)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(group.assets, id: \.localIdentifier) { asset in
                    MediaGridCell(
                        asset: asset,
                        isSelected: selectedIDs.contains(asset.localIdentifier),
                        onOpen: { previewItem = PreviewItem(asset: asset) },
                        onToggle: { toggle(asset) }
                    )
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
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

// MARK: - Shared chrome

/// Circular glass close button for presented detail pages.
private struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.ssTextSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        }
    }
}

private struct SortPillLabel: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .heavy))
            Text(text).font(.system(size: 13, weight: .bold, design: .rounded))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .heavy)).opacity(0.7)
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

private struct MediaEmptyState: View {
    let subtitle: String
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.ssTeal.opacity(0.14)).frame(width: 96, height: 96)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.ssTeal)
            }
            Text("Nothing here")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ssTextPrimary)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ssTextTertiary)
        }
    }
}

/// Floating glass bar with the selection count and a Delete action.
private struct MediaDeleteBar: View {
    let count: Int
    let sizeText: String?
    let onDeselect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count) selected")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ssTextPrimary)
                if let sizeText {
                    Text(sizeText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.ssTextTertiary)
                } else {
                    Button(action: onDeselect) {
                        Text("Deselect all")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.ssViolet)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                HStack(spacing: 7) {
                    Image(systemName: "trash.fill").font(.system(size: 14, weight: .bold))
                    Text("Delete").font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 46)
                .background(
                    Capsule().fill(LinearGradient(colors: [.ssCoral, Color(red: 0.91, green: 0.26, blue: 0.23)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .shadow(color: .ssCoral.opacity(0.4), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}

private struct DeletingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            ProgressView("Deleting…")
                .tint(.white)
                .foregroundStyle(.white)
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
        }
    }
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

                        if isSelected {
                            Color.ssViolet.opacity(0.18)
                        }

                        if asset.mediaType == .video {
                            VStack {
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                                    Text(Self.durationString(asset.duration))
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                    Spacer()
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .top))
                            }
                        }

                        Button(action: onToggle) {
                            ZStack {
                                if isSelected {
                                    Circle()
                                        .fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 24, height: 24)
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                                } else {
                                    Circle().fill(Color.black.opacity(0.28)).frame(width: 24, height: 24)
                                    Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.6).frame(width: 24, height: 24)
                                }
                            }
                            .padding(7)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? Color.ssViolet : Color.white.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
                    )
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
        manager.requestImage(for: asset, targetSize: CGSize(width: 320, height: 320), contentMode: .aspectFill, options: options) { img, _ in
            if let img { self.image = img }
        }
    }

    private static func durationString(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Formatting

enum MediaFormat {
    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: value)
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
