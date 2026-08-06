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
    /// Called with the deleted asset ids so the caller can refresh its data.
    var onDeleted: (Set<String>) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    /// The sorted array actually rendered. Recomputed only on load / sort / delete
    /// — never on every render — so selection stays smooth on large libraries.
    @State private var displayAssets: [PHAsset] = []
    @State private var selectedIDs = Set<String>()
    @State private var previewItem: PreviewItem?
    @State private var isLoading = true
    @State private var sortOrder: MediaSortOrder = .largestFirst
    @State private var sizeCache: [String: Int64] = [:]
    @State private var totalBytes: Int64 = 0
    @State private var deletePhase: DeletePhase = .idle
    @State private var deletedCount = 0
    @State private var freedBytes: Int64 = 0

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 170), spacing: 6)]

    private var selectedBytes: Int64 { selectedIDs.reduce(0) { $0 + (sizeCache[$1] ?? 0) } }

    private func applySort() {
        displayAssets = assets.sorted { lhs, rhs in
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if assets.isEmpty {
                MediaEmptyState(subtitle: "This category has no items.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                totalBytes = cache.values.reduce(0, +)
                applySort()
                isLoading = false
            }
        }
        .onChange(of: sortOrder) { _ in applySort() }
        .fullScreenCover(item: $previewItem) { item in
            MediaPreviewView(asset: item.asset) { deleted in
                removeLocally([deleted.localIdentifier])
                onDeleted([deleted.localIdentifier])
            }
        }
        .overlay {
            if deletePhase == .deleting {
                DeletingScreen(count: deletedCount).transition(.opacity)
            } else if deletePhase == .done {
                DeletedScreen(count: deletedCount, freed: freedBytes) {
                    withAnimation { deletePhase = .idle }
                }
                .transition(.opacity)
            }
        }
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
                ForEach(displayAssets, id: \.localIdentifier) { asset in
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

    private func removeLocally(_ ids: Set<String>) {
        assets.removeAll { ids.contains($0.localIdentifier) }
        displayAssets.removeAll { ids.contains($0.localIdentifier) }
        selectedIDs.subtract(ids)
        totalBytes = assets.reduce(0) { $0 + (sizeCache[$1.localIdentifier] ?? 0) }
    }

    private func deleteSelected() {
        let toDelete = assets.filter { selectedIDs.contains($0.localIdentifier) }
        guard !toDelete.isEmpty else { return }
        deletedCount = toDelete.count
        freedBytes = toDelete.reduce(0) { $0 + (sizeCache[$1.localIdentifier] ?? 0) }
        withAnimation { deletePhase = .deleting }
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
        } completionHandler: { success, _ in
            DispatchQueue.main.async {
                if success {
                    let deleted = Set(toDelete.map(\.localIdentifier))
                    removeLocally(deleted)
                    onDeleted(deleted)
                    // Keep the progress page visible briefly, then show the result.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation { deletePhase = .done }
                    }
                } else {
                    withAnimation { deletePhase = .idle }
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
    var onDeleted: (Set<String>) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var localGroups: [PhotoGroup] = []
    @State private var selectedIDs = Set<String>()
    @State private var previewItem: PreviewItem?
    @State private var didInit = false
    @State private var deletePhase: DeletePhase = .idle
    @State private var deletedCount = 0
    @State private var freedBytes: Int64 = 0

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 170), spacing: 6)]

    var body: some View {
        ZStack(alignment: .bottom) {
            HomeBackground()

            if localGroups.isEmpty {
                MediaEmptyState(subtitle: "Your library looks clean.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { keepBest() } label: { Label("Keep best (recommended)", systemImage: "star") }
                    Button { selectAll() } label: { Label("Select all", systemImage: "checkmark.circle") }
                    Button(role: .cancel) { selectedIDs.removeAll() } label: { Label("Deselect all", systemImage: "circle") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ssViolet)
                }
            }
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
            MediaPreviewView(asset: item.asset) { deleted in
                let id = deleted.localIdentifier
                localGroups = localGroups.compactMap { group in
                    let remaining = group.assets.filter { $0.localIdentifier != id }
                    return remaining.count > 1 ? PhotoGroup(assets: remaining) : nil
                }
                selectedIDs.remove(id)
                onDeleted([id])
            }
        }
        .overlay {
            if deletePhase == .deleting {
                DeletingScreen(count: deletedCount).transition(.opacity)
            } else if deletePhase == .done {
                DeletedScreen(count: deletedCount, freed: freedBytes) {
                    withAnimation { deletePhase = .idle }
                }
                .transition(.opacity)
            }
        }
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
                        isBest: asset.localIdentifier == group.assets.first?.localIdentifier,
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

    /// Reset to the default "keep the first, remove the rest" selection.
    private func keepBest() {
        var preselect = Set<String>()
        for group in localGroups {
            for asset in group.assets.dropFirst() { preselect.insert(asset.localIdentifier) }
        }
        withAnimation { selectedIDs = preselect }
    }

    private func selectAll() {
        withAnimation { selectedIDs = Set(localGroups.flatMap(\.assets).map(\.localIdentifier)) }
    }

    private func deleteSelected() {
        let ids = selectedIDs
        let toDelete = localGroups.flatMap(\.assets).filter { ids.contains($0.localIdentifier) }
        guard !toDelete.isEmpty else { return }
        deletedCount = toDelete.count
        freedBytes = MediaFormat.size(of: toDelete)
        withAnimation { deletePhase = .deleting }
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
        } completionHandler: { success, _ in
            DispatchQueue.main.async {
                if success {
                    localGroups = localGroups.compactMap { group in
                        let remaining = group.assets.filter { !ids.contains($0.localIdentifier) }
                        return remaining.count > 1 ? PhotoGroup(assets: remaining) : nil
                    }
                    selectedIDs.removeAll()
                    onDeleted(Set(toDelete.map(\.localIdentifier)))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation { deletePhase = .done }
                    }
                } else {
                    withAnimation { deletePhase = .idle }
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

// MARK: - Delete flow (progress + result full pages)

enum DeletePhase: Equatable { case idle, deleting, done }

/// Full-screen "deleting…" page shown while assets are being removed.
struct DeletingScreen: View {
    let count: Int
    @State private var spin = false

    var body: some View {
        ZStack {
            HomeBackground()
            VStack(spacing: 24) {
                ZStack {
                    Circle().stroke(Color.ssTrack, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            AngularGradient(gradient: Gradient(colors: [.ssTeal, .ssViolet, .ssPink, .ssTeal]), center: .center),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Color.ssCoral)
                }
                .frame(width: 130, height: 130)

                VStack(spacing: 6) {
                    Text("Deleting…")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ssTextPrimary)
                    Text("Removing \(count) item\(count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ssTextTertiary)
                }
            }
            .padding(30)
        }
        .onAppear { spin = true }
    }
}

/// Full-screen result page shown after a successful delete.
struct DeletedScreen: View {
    let count: Int
    let freed: Int64
    let onDone: () -> Void

    var body: some View {
        ZStack {
            HomeBackground()
            VStack(spacing: 22) {
                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.ssTeal, Color(red: 0.1, green: 0.7, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 104, height: 104)
                        .shadow(color: .ssTeal.opacity(0.45), radius: 18, y: 8)
                    Image(systemName: "checkmark")
                        .font(.system(size: 46, weight: .heavy))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 4) {
                    Text("Cleaned up!")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ssTextPrimary)
                    Text("You freed")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.ssTextSecondary)
                }

                VStack(spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(MediaFormat.parts(freed).value)
                            .font(.system(size: 50, weight: .bold, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Text(MediaFormat.parts(freed).unit)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.ssTextSecondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill").font(.system(size: 11, weight: .bold))
                        Text("\(count) item\(count == 1 ? "" : "s") removed")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.ssTextTertiary)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .glassCard(radius: 24)
                .padding(.horizontal, 24)

                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 12, weight: .semibold))
                    Text("In Recently Deleted for 30 days — recoverable")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(Color.ssTextTertiary)
                .padding(.top, 4)

                Spacer()

                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing)))
                        .shadow(color: .ssViolet.opacity(0.4), radius: 14, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 24)
        }
    }
}

// MARK: - Grid cell

private struct MediaGridCell: View {
    let asset: PHAsset
    let isSelected: Bool
    var isBest: Bool = false
    let onOpen: () -> Void
    let onToggle: () -> Void

    @State private var image: UIImage?
    private static let manager = PHCachingImageManager()

    private var borderColor: Color {
        if isBest { return .ssTeal }
        if isSelected { return .ssViolet }
        return .white.opacity(0.12)
    }

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

                        // Recommended-to-keep badge (top-right).
                        if isBest {
                            VStack {
                                HStack {
                                    Spacer()
                                    HStack(spacing: 3) {
                                        Image(systemName: "star.fill").font(.system(size: 9, weight: .bold))
                                        Text("Best").font(.system(size: 11, weight: .heavy, design: .rounded))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(LinearGradient(colors: [.ssTeal, Color(red: 0.1, green: 0.7, blue: 0.55)],
                                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                                    )
                                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                                    .padding(7)
                                }
                                Spacer()
                            }
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

                        // The best/keep photo isn't part of the delete selection,
                        // so it shows the badge instead of a selection circle.
                        if !isBest {
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
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: (isBest || isSelected) ? 2.5 : 1)
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
        Self.manager.requestImage(for: asset, targetSize: CGSize(width: 320, height: 320), contentMode: .aspectFill, options: options) { img, _ in
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

    static func parts(_ value: Int64) -> (value: String, unit: String) {
        let string = bytes(value)
        let split = string.split(separator: " ", maxSplits: 1)
        return split.count == 2 ? (String(split[0]), String(split[1])) : (string, "")
    }

    static func size(of assets: [PHAsset]) -> Int64 {
        assets.reduce(0) { $0 + ((PHAssetResource.assetResources(for: $1).first?.value(forKey: "fileSize") as? Int64) ?? 0) }
    }
}

// MARK: - Zoomable image (pinch / drag / double-tap)

private struct ZoomableImage: View {
    let image: UIImage

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value, 1), 5)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                offset = .zero; lastOffset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale > 1 else { return }
                        offset = CGSize(width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if scale > 1 {
                        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
                    } else {
                        scale = 2.5; lastScale = 2.5
                    }
                }
            }
    }
}

// MARK: - Full-screen preview (photo or video)

struct MediaPreviewView: View {
    let asset: PHAsset
    /// Called after this asset is deleted, so the grid/dashboard can update.
    var onDeleted: (PHAsset) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isDeleting = false

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
                    ZoomableImage(image: image)
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

                Button(role: .destructive, action: deleteAsset) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill").font(.system(size: 16, weight: .bold))
                        Text("Delete").font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .frame(height: 52)
                    .background(
                        Capsule().fill(LinearGradient(colors: [.ssCoral, Color(red: 0.91, green: 0.26, blue: 0.23)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                    .opacity(isDeleting ? 0.6 : 1)
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                .padding(.bottom, 28)
            }
        }
        .onAppear(perform: loadMedia)
        .onDisappear { player?.pause() }
    }

    private func deleteAsset() {
        guard !isDeleting else { return }
        isDeleting = true
        player?.pause()
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        } completionHandler: { success, _ in
            DispatchQueue.main.async {
                isDeleting = false
                if success {
                    onDeleted(asset)
                    dismiss()
                }
            }
        }
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
