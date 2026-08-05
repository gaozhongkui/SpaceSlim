import SwiftUI
import Photos
import UIKit

// MARK: - Home screen (dashboard)

struct HomeView: View {
    @ObservedObject var photoService: PhotoService
    @ObservedObject var videoService: VideoService
    @ObservedObject var storageService: StorageService
    @ObservedObject var historyStore: CleanupHistoryStore
    @Binding var selectedTab: Int

    @AppStorage("autoScan") private var autoScan = true

    @State private var categories: [MediaCategory] = [
        MediaCategory(title: "Large videos", subtitle: "Not scanned", count: 0, sizeGB: 0, proportion: 0, icon: "play.rectangle.fill", color: .ssEmber, isSelected: true),
        MediaCategory(title: "Screenshots", subtitle: "Not scanned", count: 0, sizeGB: 0, proportion: 0, icon: "camera.viewfinder", color: .ssTeal, isSelected: true),
        MediaCategory(title: "Live Photos", subtitle: "Not scanned", count: 0, sizeGB: 0, proportion: 0, icon: "livephoto", color: .ssPink, isSelected: true),
        MediaCategory(title: "Screen recordings", subtitle: "Not scanned", count: 0, sizeGB: 0, proportion: 0, icon: "record.circle", color: .ssCoral, isSelected: false),
        MediaCategory(title: "Blurry photos", subtitle: "Not scanned", count: 0, sizeGB: 0, proportion: 0, icon: "camera.filters", color: .ssIndigo, isSelected: true),
    ]

    @State private var reclaimableSimilarBytes: Int64 = 0
    @State private var reclaimableDuplicateBytes: Int64 = 0
    @State private var recommendedBytes: Int64 = 0
    @State private var compressibleBytes: Int64 = 0
    @State private var hasScanned = false

    // Cleanup + feedback
    @State private var pendingCleanupAssets: [PHAsset] = []
    @State private var showCleanConfirm = false
    @State private var cleanupResultMessage = ""
    @State private var showCleanupResult = false
    @State private var showHistory = false
    @State private var showFreedToast = false
    @State private var freedText = ""

    private var isScanning: Bool { photoService.isScanning || videoService.isScanning }
    private var scanPercent: Int { Int(photoService.progress * 100) }
    private var isAccessDenied: Bool {
        photoService.authorizationStatus == .denied || photoService.authorizationStatus == .restricted
    }
    private var usedGB: Double { Double(storageService.usedSpace) / 1024 / 1024 / 1024 }
    private var totalGB: Double { Double(storageService.totalSpace) / 1024 / 1024 / 1024 }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.ssBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    DashboardCard(
                        compressibleBytes: compressibleBytes,
                        cleanableBytes: recommendedBytes,
                        usedGB: usedGB,
                        totalGB: totalGB,
                        isScanning: isScanning,
                        scanPercent: scanPercent,
                        accessDenied: isAccessDenied,
                        onCompress: { selectedTab = 1 },
                        onClean: prepareCleanup,
                        onEnableAccess: openSettings
                    )
                    valueProp
                    categoriesSection
                    videoToolCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }

            if showFreedToast {
                freedToast
            }
        }
        .onAppear {
            storageService.refresh()
            if autoScan && !hasScanned && !isScanning {
                startGlobalScan()
            }
        }
        .onChange(of: photoService.isScanning) { scanning in
            if !scanning && hasScanned { updateRealData() }
        }
        .onChange(of: videoService.isScanning) { scanning in
            if !scanning && hasScanned { updateRealData() }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showHistory) {
            NavigationStack { HistoryView(store: historyStore) }
        }
        .alert("Clean \(pendingCleanupAssets.count) items?", isPresented: $showCleanConfirm) {
            Button("Clean", role: .destructive) { performCleanup() }
            Button("Cancel", role: .cancel) { pendingCleanupAssets = [] }
        } message: {
            Text("Blurry photos and duplicate/similar copies will be removed from Photos, freeing about \(formatSize(recommendedBytes)).")
        }
        .alert("Cleanup", isPresented: $showCleanupResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(cleanupResultMessage)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("SpaceSlim")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.ssTextPrimary)
            Spacer()

            if isScanning {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.8)
                    Text(photoService.isScanning ? "\(scanPercent)%" : "Scanning…")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.ssViolet)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.ssViolet.opacity(0.12)))
            }

            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.ssTextSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.ultraThinMaterial))
            }
        }
    }

    private var valueProp: some View {
        VStack(spacing: 4) {
            Text("Compress to keep memories · Clean to remove junk")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ssTextSecondary)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 10))
                Text("100% on-device · No account, no uploads")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.ssTextTertiary)
        }
        .multilineTextAlignment(.center)
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                Text("CLEAN UP BY CATEGORY")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.ssTextTertiary)
                Spacer()
                Text("tap to review")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ssTeal)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                NavigationLink(destination: PhotoGroupsView(title: "Similar photos", groups: photoService.similarGroups)) {
                    CategoryChip(icon: "photo.on.rectangle.angled", color: .ssEmber, count: photoService.similarGroups.count, title: "Similar", sizeText: formatSize(reclaimableSimilarBytes))
                }
                .buttonStyle(.plain)

                NavigationLink(destination: PhotoGroupsView(title: "Duplicates", groups: photoService.duplicateGroups)) {
                    CategoryChip(icon: "square.on.square", color: .ssCoral, count: photoService.duplicateGroups.count, title: "Duplicates", sizeText: formatSize(reclaimableDuplicateBytes))
                }
                .buttonStyle(.plain)

                ForEach(categories) { category in
                    NavigationLink(destination: destinationFor(category: category)) {
                        let parts = spaceSizeParts(gb: category.sizeGB)
                        CategoryChip(icon: category.icon, color: category.color, count: category.count, title: category.title, sizeText: "\(parts.value) \(parts.unit)")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var videoToolCard: some View {
        Button {
            selectedTab = 1
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [.ssViolet, Color(red: 0.298, green: 0.247, blue: 0.796)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Video compression")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.ssTextPrimary)
                    Text("Shrink large videos, keep the quality")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ssTextSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ssTextTertiary)
            }
            .padding(16)
            .glassCard(radius: 24)
        }
        .buttonStyle(.plain)
    }

    private var freedToast: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
            Text(freedText)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text("reclaimed")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: .ssViolet.opacity(0.4), radius: 20, y: 10)
        .padding(.bottom, 60)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Scan

    private func startGlobalScan() {
        guard !isScanning else { return }
        Task {
            var status = photoService.authorizationStatus
            if status == .notDetermined {
                status = await photoService.requestAuthorization()
            }
            guard status == .authorized || status == .limited else { return }

            storageService.refresh()
            videoService.fetchAndClassifyVideos()
            await photoService.scanForSimilarAndDuplicatePhotos()
            hasScanned = true
            updateRealData()
        }
    }

    private func updateRealData() {
        Task {
            let screenshots = fetchAssets(subtype: .photoScreenshot)
            let livePhotos = fetchAssets(subtype: .photoLive)

            async let screenshotsSize = photoService.calculateSize(for: screenshots)
            async let livePhotosSize = photoService.calculateSize(for: livePhotos)
            async let largeVideosSize = videoService.calculateSize(for: videoService.cameraVideos)
            async let screenRecordingsSize = videoService.calculateSize(for: videoService.screenRecordings)
            async let blurrySize = photoService.calculateSize(for: photoService.blurryPhotos)

            let recAssets = await MainActor.run { recommendedAssets() }
            async let recSize = photoService.calculateSize(for: recAssets)

            async let similarSize = photoService.calculateGroupsSize(groups: photoService.similarGroups)
            async let duplicateSize = photoService.calculateGroupsSize(groups: photoService.duplicateGroups)

            let sSize = await screenshotsSize
            let lSize = await livePhotosSize
            let lvSize = await largeVideosSize
            let srSize = await screenRecordingsSize
            let blSize = await blurrySize
            let recBytes = await recSize
            let simSize = await similarSize
            let dupSize = await duplicateSize
            let blurryCount = photoService.blurryPhotos.count

            await MainActor.run {
                self.reclaimableSimilarBytes = simSize
                self.reclaimableDuplicateBytes = dupSize
                self.recommendedBytes = recBytes
                // Estimated savings from re-encoding videos (kept, just smaller).
                self.compressibleBytes = Int64(Double(lvSize + srSize) * 0.5)

                let categoriesRaw = [
                    (title: "Large videos", count: videoService.cameraVideos.count, size: lvSize, icon: "play.rectangle.fill", color: Color.ssEmber),
                    (title: "Screenshots", count: screenshots.count, size: sSize, icon: "camera.viewfinder", color: Color.ssTeal),
                    (title: "Live Photos", count: livePhotos.count, size: lSize, icon: "livephoto", color: Color.ssPink),
                    (title: "Screen recordings", count: videoService.screenRecordings.count, size: srSize, icon: "record.circle", color: Color.ssCoral),
                    (title: "Blurry photos", count: blurryCount, size: blSize, icon: "camera.filters", color: Color.ssIndigo)
                ]

                let maxSize = max(categoriesRaw.map { $0.size }.max() ?? 1, 1)

                let newCategories = categoriesRaw.map { item in
                    MediaCategory(
                        title: item.title,
                        subtitle: "\(item.count) items",
                        count: item.count,
                        sizeGB: Double(item.size) / 1024 / 1024 / 1024,
                        proportion: Double(item.size) / Double(maxSize),
                        icon: item.icon,
                        color: item.color,
                        isSelected: true
                    )
                }

                self.categories = newCategories.sorted(by: { $0.sizeGB > $1.sizeGB })
            }
        }
    }

    // MARK: - Cleanup

    /// The safe-to-remove set surfaced by the dashboard: all blurry photos plus
    /// the redundant copies in each similar/duplicate group (keeping the first).
    private func recommendedAssets() -> [PHAsset] {
        var seen = Set<String>()
        var result: [PHAsset] = []
        func add(_ asset: PHAsset) {
            if seen.insert(asset.localIdentifier).inserted { result.append(asset) }
        }
        photoService.blurryPhotos.forEach(add)
        for group in photoService.similarGroups { group.assets.dropFirst().forEach(add) }
        for group in photoService.duplicateGroups { group.assets.dropFirst().forEach(add) }
        return result
    }

    private func prepareCleanup() {
        let assets = recommendedAssets()
        pendingCleanupAssets = assets
        guard !assets.isEmpty else {
            cleanupResultMessage = "Nothing recommended to clean right now."
            showCleanupResult = true
            return
        }
        showCleanConfirm = true
    }

    private func performCleanup() {
        let assets = pendingCleanupAssets
        pendingCleanupAssets = []
        guard !assets.isEmpty else { return }

        Task {
            let freed = await photoService.calculateSize(for: assets)
            let count = assets.count
            let success = await deleteAssets(assets)
            await MainActor.run {
                if success {
                    historyStore.add(freedBytes: freed, itemCount: count, kind: .cleanup)
                    freedText = formatSize(freed)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { showFreedToast = true }
                    storageService.refresh()
                    startGlobalScan()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                        withAnimation { showFreedToast = false }
                    }
                } else {
                    cleanupResultMessage = "Nothing was deleted."
                    showCleanupResult = true
                }
            }
        }
    }

    private func deleteAssets(_ assets: [PHAsset]) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - Helpers

    private func assetsFor(category: MediaCategory) -> [PHAsset] {
        switch category.title {
        case "Large videos":      return videoService.cameraVideos
        case "Screenshots":       return fetchAssets(subtype: .photoScreenshot)
        case "Live Photos":       return fetchAssets(subtype: .photoLive)
        case "Screen recordings": return videoService.screenRecordings
        case "Blurry photos":     return photoService.blurryPhotos
        default:                  return []
        }
    }

    private func fetchAssets(subtype: PHAssetMediaSubtype) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", subtype.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    @ViewBuilder
    private func destinationFor(category: MediaCategory) -> some View {
        MediaGridView(title: category.title) {
            assetsFor(category: category)
        }
    }
}

// MARK: - Dashboard card

struct DashboardCard: View {
    let compressibleBytes: Int64
    let cleanableBytes: Int64
    let usedGB: Double
    let totalGB: Double
    let isScanning: Bool
    let scanPercent: Int
    let accessDenied: Bool
    let onCompress: () -> Void
    let onClean: () -> Void
    let onEnableAccess: () -> Void

    private var percentUsed: Double { totalGB > 0 ? usedGB / totalGB : 0 }
    private var totalReclaimable: Int64 { compressibleBytes + cleanableBytes }

    private func parts(_ bytes: Int64) -> (value: String, unit: String) {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        let string = formatter.string(fromByteCount: bytes)
        let split = string.split(separator: " ", maxSplits: 1)
        return split.count == 2 ? (String(split[0]), String(split[1])) : (string, "")
    }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.ssTrack, lineWidth: 16)
                Circle()
                    .trim(from: 0, to: CGFloat(percentUsed))
                    .stroke(
                        AngularGradient(colors: [.ssViolet, .ssTeal], center: .center),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .ssViolet.opacity(0.4), radius: 8)

                VStack(spacing: 4) {
                    Text("RECLAIMABLE")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.ssTextTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(parts(totalReclaimable).value)
                            .font(.system(size: 46, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.ssTextPrimary)
                        Text(parts(totalReclaimable).unit)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.ssTextSecondary)
                    }
                    Text("\(Int(usedGB)) GB used of \(Int(totalGB)) GB")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.ssTextTertiary)
                }
            }
            .frame(width: 210, height: 210)

            if accessDenied {
                VStack(spacing: 8) {
                    Button(action: onEnableAccess) {
                        Text("Enable Photo Access")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing)))
                    }
                    .buttonStyle(.plain)
                    Text("SpaceSlim needs photo access to scan your library.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ssTextTertiary)
                        .multilineTextAlignment(.center)
                }
            } else if isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Scanning \(scanPercent)%")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ssTextSecondary)
                }
                .frame(height: 60)
            } else {
                // The differentiator: compress (keep everything) vs clean (remove junk).
                HStack(spacing: 12) {
                    ActionPill(
                        icon: "rectangle.compress.vertical",
                        title: "Compress",
                        amount: parts(compressibleBytes),
                        subtitle: "keep everything",
                        colors: [.ssViolet, Color(red: 0.37, green: 0.55, blue: 0.94)],
                        enabled: compressibleBytes > 0,
                        action: onCompress
                    )
                    ActionPill(
                        icon: "trash.fill",
                        title: "Clean",
                        amount: parts(cleanableBytes),
                        subtitle: "remove junk",
                        colors: [.ssCoral, Color(red: 0.91, green: 0.26, blue: 0.23)],
                        enabled: cleanableBytes > 0,
                        action: onClean
                    )
                }
            }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 32)
    }
}

/// One of the two dashboard actions — a bold, tappable pill showing how much
/// each path can reclaim.
struct ActionPill: View {
    let icon: String
    let title: String
    let amount: (value: String, unit: String)
    let subtitle: String
    let colors: [Color]
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(amount.value)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                    Text(amount.unit)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: enabled ? colors : [Color.ssTextTertiary.opacity(0.4), Color.ssTextTertiary.opacity(0.4)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: enabled ? colors[0].opacity(0.35) : .clear, radius: 10, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Category chip

struct CategoryChip: View {
    let icon: String
    let color: Color
    let count: Int
    let title: String
    let sizeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.ssTextPrimary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ssTextSecondary)
                .lineLimit(1)
            Text(sizeText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ssTextTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .glassCard(radius: 22, tint: color)
    }
}

// MARK: - Reusable glass surface

/// The glassmorphism card style used across the screen.
///
/// On iOS 17+ we use a translucent `.ultraThinMaterial`. On iOS 16 that same
/// material renders muddy grey over light backgrounds, so we drop the blur and
/// use an opaque, fully controllable card surface instead.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 24
    var tint: Color = .clear
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(glassBackground)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, x: 0, y: 8)
    }

    @ViewBuilder
    private var glassBackground: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        if #available(iOS 17.0, *) {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(tint.opacity(0.12))
            }
        } else {
            ZStack {
                shape.fill(Color.ssCardSolid)
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.35), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                shape.fill(tint.opacity(colorScheme == .dark ? 0.14 : 0.10))
            }
        }
    }
}

extension View {
    func glassCard(radius: CGFloat = 24, tint: Color = .clear) -> some View {
        modifier(GlassCard(radius: radius, tint: tint))
    }
}

// MARK: - Palette

extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let ssViolet = Color(red: 0.486, green: 0.435, blue: 0.941)
    static let ssTeal   = Color(red: 0.204, green: 0.906, blue: 0.776)
    static let ssEmber  = Color(red: 1.000, green: 0.714, blue: 0.282)
    static let ssCoral  = Color(red: 1.000, green: 0.420, blue: 0.361)
    static let ssPink   = Color(red: 1.000, green: 0.498, blue: 0.690)
    static let ssIndigo = Color(red: 0.608, green: 0.549, blue: 0.969)

    static let ssBackground = Color(light: UIColor(red: 0.965, green: 0.961, blue: 0.984, alpha: 1),
                                     dark:  UIColor(red: 0.043, green: 0.059, blue: 0.106, alpha: 1))
    static let ssTextPrimary = Color(light: UIColor(red: 0.071, green: 0.071, blue: 0.102, alpha: 1),
                                      dark:  UIColor(red: 0.953, green: 0.953, blue: 0.969, alpha: 1))
    static let ssTextSecondary = Color(light: UIColor(red: 0.357, green: 0.357, blue: 0.408, alpha: 1),
                                        dark:  UIColor(red: 0.655, green: 0.659, blue: 0.722, alpha: 1))
    static let ssTextTertiary = Color(light: UIColor(red: 0.549, green: 0.549, blue: 0.600, alpha: 1),
                                       dark:  UIColor(red: 0.431, green: 0.439, blue: 0.525, alpha: 1))
    static let ssTrack = Color(light: UIColor(red: 0.071, green: 0.071, blue: 0.102, alpha: 0.08),
                                dark:  UIColor(white: 1, alpha: 0.08))
    static let ssCardSolid = Color(light: UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1),
                                    dark:  UIColor(red: 0.098, green: 0.114, blue: 0.169, alpha: 1))
}

// MARK: - Helpers & model

/// Splits an adaptive byte-count string into value + unit so the two can be
/// rendered at different sizes ("340" big, "MB" small). Adaptive so small
/// categories show real MB/KB instead of rounding to "0.0 GB".
func spaceSizeParts(gb: Double) -> (value: String, unit: String) {
    let bytes = Int64(max(gb, 0) * 1_073_741_824)
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    let string = formatter.string(fromByteCount: bytes)
    let parts = string.split(separator: " ", maxSplits: 1)
    if parts.count == 2 { return (String(parts[0]), String(parts[1])) }
    return (string, "")
}

struct MediaCategory: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let count: Int
    let sizeGB: Double
    let proportion: Double
    let icon: String
    let color: Color
    var isSelected: Bool
}
