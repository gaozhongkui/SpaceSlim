import SwiftUI
import Photos
import PhotosUI
import UIKit

// MARK: - Home screen (dashboard)

struct HomeView: View {
    @ObservedObject var photoService: PhotoService
    @ObservedObject var videoService: VideoService
    @ObservedObject var storageService: StorageService
    @ObservedObject var historyStore: CleanupHistoryStore
    @Binding var selectedTab: Int

    @AppStorage("autoScan") private var autoScan = true
    @AppStorage("didOnboard") private var didOnboard = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var categories: [MediaCategory] = [
        MediaCategory(title: "Large videos", subtitle: "Not scanned", count: 0, sizeGB: 0, proportion: 0, icon: "play.rectangle.fill", color: .ssEmber, isSelected: true),
        MediaCategory(title: "Screenshots", subtitle: "Not scanned", count: 0, sizeGB: 0, proportion: 0, icon: "camera.viewfinder", color: .ssTeal, isSelected: true),
        MediaCategory(title: "Live Photos", subtitle: "Not scanned", count: 0, sizeGB: 0, proportion: 0, icon: "livephoto", color: .ssPink, isSelected: true),
        MediaCategory(title: "Screen recordings", subtitle: "Not scanned", count: 0, sizeGB: 0, proportion: 0, icon: "record.circle", color: .ssCoral, isSelected: false),
        MediaCategory(title: "Blurry photos", subtitle: "Not scanned", count: 0, sizeGB: 0, proportion: 0, icon: "camera.filters", color: .ssIndigo, isSelected: true),
        MediaCategory(title: "Portraits", subtitle: "Not scanned", count: 0, sizeGB: 0, proportion: 0, icon: "person.crop.square.fill", color: .ssSky, isSelected: true),
    ]

    @State private var reclaimableSimilarBytes: Int64 = 0
    @State private var reclaimableDuplicateBytes: Int64 = 0
    @State private var recommendedBytes: Int64 = 0
    @State private var compressibleBytes: Int64 = 0
    @State private var hasScanned = false
    @State private var activeDetail: HomeDetail?

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
    private var isLimited: Bool { photoService.authorizationStatus == .limited }
    private var usedGB: Double { Double(storageService.usedSpace) / 1024 / 1024 / 1024 }
    private var totalGB: Double { Double(storageService.totalSpace) / 1024 / 1024 / 1024 }

    var body: some View {
        ZStack(alignment: .bottom) {
            HomeBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    if isLimited { limitedBanner }
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
                .padding(.bottom, 110)
            }
            .refreshable { await runScan() }

            if showFreedToast {
                freedToast
            }
        }
        .onAppear {
            storageService.refresh()
            if autoScan && didOnboard && !hasScanned && !isScanning {
                startGlobalScan()
            }
        }
        // The onboarding cover sits on top of Home, so Home's `onAppear` does not
        // fire again when it is dismissed. Kick off the first scan when onboarding
        // completes (didOnboard flips to true).
        .onChange(of: didOnboard) { done in
            if done && autoScan && !hasScanned && !isScanning {
                startGlobalScan()
            }
        }
        // If the user grants photo access later (e.g. from the system Settings
        // app), rescan when we come back to the foreground.
        .onChange(of: scenePhase) { phase in
            guard phase == .active, didOnboard, autoScan, !hasScanned, !isScanning else { return }
            photoService.checkAuthorization()
            if photoService.authorizationStatus == .authorized || photoService.authorizationStatus == .limited {
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
        .fullScreenCover(item: $activeDetail) { detail in
            NavigationStack {
                switch detail {
                case .similar:
                    PhotoGroupsView(title: "Similar photos", groups: photoService.similarGroups, onDeleted: handleDeleted)
                case .duplicates:
                    PhotoGroupsView(title: "Duplicates", groups: photoService.duplicateGroups, onDeleted: handleDeleted)
                case .category(let category):
                    MediaGridView(title: category.title, load: { assetsFor(category: category) }, onDeleted: handleDeleted)
                }
            }
        }
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
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                    .shadow(color: .ssViolet.opacity(0.35), radius: 6, y: 3)
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("SpaceSlim")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ssTextPrimary)

            Spacer()

            if isScanning {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text(photoService.isScanning ? "\(scanPercent)%" : "Scanning…")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.ssViolet)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.ssViolet.opacity(0.14)))
            }

            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ssTextSecondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            }
        }
    }

    private var valueProp: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.ssTeal)
            Text("100% on-device")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ssTextSecondary)
            Text("·  No account, no uploads")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.ssTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    private var limitedBanner: some View {
        Button {
            presentLimitedPicker()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.ssViolet)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.ssViolet.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Limited photo access")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ssTextPrimary)
                    Text("SpaceSlim can only scan the photos you selected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ssTextTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text("Select more")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ssViolet)
            }
            .padding(14)
            .glassCard(radius: 18, tint: .ssViolet)
        }
        .buttonStyle(.plain)
    }

    private func presentLimitedPicker() {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
        guard let root else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Clean up by category")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ssTextPrimary)
                Text("Tap a card to review and clean")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ssTextTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                Button {
                    activeDetail = .similar
                } label: {
                    CategoryChip(icon: "photo.on.rectangle.angled", color: .ssEmber, count: photoService.similarGroups.count, title: "Similar", sizeText: formatSize(reclaimableSimilarBytes))
                }
                .buttonStyle(.plain)

                Button {
                    activeDetail = .duplicates
                } label: {
                    CategoryChip(icon: "square.on.square", color: .ssCoral, count: photoService.duplicateGroups.count, title: "Duplicates", sizeText: formatSize(reclaimableDuplicateBytes))
                }
                .buttonStyle(.plain)

                ForEach(categories) { category in
                    Button {
                        activeDetail = .category(category)
                    } label: {
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
                VStack(alignment: .leading, spacing: 3) {
                    Text("Video compression")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ssTextPrimary)
                    Text("Shrink large videos, keep the quality")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ssTextSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.ssTextTertiary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.ssTextTertiary.opacity(0.12)))
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
        Task { await runScan() }
    }

    /// Awaitable scan used by both auto-scan and pull-to-refresh.
    private func runScan() async {
        guard !isScanning else { return }
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

    /// Called when a detail page deletes assets: drop them from the scan
    /// results and recompute the dashboard so counts + Reclaimable stay accurate
    /// without a full re-scan.
    private func handleDeleted(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        photoService.remove(assetIDs: ids)
        videoService.remove(assetIDs: ids)
        storageService.refresh()
        updateRealData()
    }

    private func updateRealData() {
        Task {
            let screenshots = screenshotAssets()
            let livePhotos = livePhotoAssets()
            let screenRecordings = screenRecordingAssets()

            async let screenshotsSize = photoService.calculateSize(for: screenshots)
            async let livePhotosSize = photoService.calculateSize(for: livePhotos)
            async let largeVideosSize = videoService.calculateSize(for: videoService.cameraVideos)
            async let screenRecordingsSize = videoService.calculateSize(for: screenRecordings)
            async let blurrySize = photoService.calculateSize(for: photoService.blurryPhotos)
            async let portraitSize = photoService.calculateSize(for: photoService.portraitPhotos)

            let recAssets = await MainActor.run { recommendedAssets() }
            async let recSize = photoService.calculateSize(for: recAssets)

            async let similarSize = photoService.calculateGroupsSize(groups: photoService.similarGroups)
            async let duplicateSize = photoService.calculateGroupsSize(groups: photoService.duplicateGroups)

            let sSize = await screenshotsSize
            let lSize = await livePhotosSize
            let lvSize = await largeVideosSize
            let srSize = await screenRecordingsSize
            let blSize = await blurrySize
            let ptSize = await portraitSize
            let recBytes = await recSize
            let simSize = await similarSize
            let dupSize = await duplicateSize
            let blurryCount = photoService.blurryPhotos.count
            let portraitCount = photoService.portraitPhotos.count

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
                    (title: "Screen recordings", count: screenRecordings.count, size: srSize, icon: "record.circle", color: Color.ssCoral),
                    (title: "Blurry photos", count: blurryCount, size: blSize, icon: "camera.filters", color: Color.ssIndigo),
                    (title: "Portraits", count: portraitCount, size: ptSize, icon: "person.crop.square.fill", color: Color.ssSky)
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
        case "Screenshots":       return screenshotAssets()
        case "Live Photos":       return livePhotoAssets()
        case "Screen recordings": return screenRecordingAssets()
        case "Blurry photos":     return photoService.blurryPhotos
        case "Portraits":         return photoService.portraitPhotos
        default:                  return []
        }
    }

    // Subtype-based categories. On a real device these read the true photo
    // subtypes; in the Simulator (where those can't be seeded) they fall back to
    // slices of the library so the whole dashboard can be previewed.
    private func screenshotAssets() -> [PHAsset] {
        let real = fetchAssets(subtype: .photoScreenshot)
        #if targetEnvironment(simulator)
        return real.isEmpty ? mockSlice(from: 0, count: 4) : real
        #else
        return real
        #endif
    }

    private func livePhotoAssets() -> [PHAsset] {
        let real = fetchAssets(subtype: .photoLive)
        #if targetEnvironment(simulator)
        return real.isEmpty ? mockSlice(from: 4, count: 3) : real
        #else
        return real
        #endif
    }

    private func screenRecordingAssets() -> [PHAsset] {
        #if targetEnvironment(simulator)
        return videoService.screenRecordings.isEmpty
            ? Array(videoService.cameraVideos.suffix(2))
            : videoService.screenRecordings
        #else
        return videoService.screenRecordings
        #endif
    }

    #if targetEnvironment(simulator)
    /// A deterministic wrap-around slice of the photo library, for preview data.
    private func mockSlice(from start: Int, count: Int) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        guard result.count > 0 else { return [] }
        return (0..<count).map { result.object(at: (start + $0) % result.count) }
    }
    #endif

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

}

/// Which cleanup detail the home is presenting (as a full-screen page).
enum HomeDetail: Identifiable {
    case similar
    case duplicates
    case category(MediaCategory)

    var id: String {
        switch self {
        case .similar:            return "similar"
        case .duplicates:         return "duplicates"
        case .category(let c):    return c.id.uuidString
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
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(Color.ssTrack, lineWidth: 18)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(percentUsed, 0), 1)))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.ssTeal, .ssViolet, .ssPink, .ssTeal]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .ssViolet.opacity(0.45), radius: 10)

                VStack(spacing: 5) {
                    Text("RECLAIMABLE")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Color.ssTextTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(parts(totalReclaimable).value)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                        Text(parts(totalReclaimable).unit)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.ssTextSecondary)
                    }
                    HStack(spacing: 5) {
                        Circle().fill(Color.ssViolet).frame(width: 6, height: 6)
                        Text("\(Int(usedGB)) GB used of \(Int(totalGB)) GB")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.ssTextTertiary)
                    }
                }
            }
            .frame(width: 214, height: 214)

            if accessDenied {
                VStack(spacing: 8) {
                    Button(action: onEnableAccess) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.stack.fill").font(.system(size: 15, weight: .bold))
                            Text("Enable Photo Access")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing)))
                        .shadow(color: .ssViolet.opacity(0.35), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                    Text("SpaceSlim needs photo access to scan your library.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ssTextTertiary)
                        .multilineTextAlignment(.center)
                }
            } else if isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Scanning \(scanPercent)%")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
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
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.white.opacity(0.2)))
                    .padding(.bottom, 2)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(amount.value)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(amount.unit)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                Text(LocalizedStringKey(title))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(
                        colors: enabled ? colors : [Color.ssTextTertiary.opacity(0.4), Color.ssTextTertiary.opacity(0.4)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: enabled ? colors[0].opacity(0.4) : .clear, radius: 12, y: 7)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                        .shadow(color: color.opacity(0.4), radius: 6, y: 3)
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(sizeText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(color.opacity(0.16)))
            }

            Spacer(minLength: 14)

            Text("\(count)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ssTextPrimary)
                .monospacedDigit()
            Text(LocalizedStringKey(title))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ssTextSecondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
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
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(colorScheme == .dark ? 0.28 : 0.85),
                                     Color.white.opacity(colorScheme == .dark ? 0.05 : 0.2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
            .shadow(color: (colorScheme == .dark ? Color.black : tint == .clear ? Color.ssViolet : tint).opacity(colorScheme == .dark ? 0.35 : 0.14),
                    radius: 20, x: 0, y: 10)
    }

    @ViewBuilder
    private var glassBackground: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        if #available(iOS 17.0, *) {
            ZStack {
                shape.fill(Color.ssCardSolid.opacity(colorScheme == .dark ? 0.55 : 0.65))
                shape.fill(.ultraThinMaterial)
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.08 : 0.5), .clear],
                        startPoint: .topLeading, endPoint: .center))
                shape.fill(tint.opacity(colorScheme == .dark ? 0.16 : 0.13))
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

// MARK: - Background

/// Layered app background: a soft vertical wash plus two blurred color glows so
/// the glass cards have something to refract instead of sitting on a flat fill.
struct HomeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.ssBackground

            LinearGradient(
                colors: [Color.ssViolet.opacity(colorScheme == .dark ? 0.16 : 0.10), .clear],
                startPoint: .top, endPoint: .center)

            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Color.ssViolet.opacity(colorScheme == .dark ? 0.30 : 0.22))
                        .frame(width: geo.size.width * 0.9)
                        .blur(radius: 90)
                        .offset(x: -geo.size.width * 0.28, y: -geo.size.height * 0.08)
                    Circle()
                        .fill(Color.ssTeal.opacity(colorScheme == .dark ? 0.22 : 0.18))
                        .frame(width: geo.size.width * 0.8)
                        .blur(radius: 90)
                        .offset(x: geo.size.width * 0.34, y: geo.size.height * 0.02)
                }
            }
        }
        .ignoresSafeArea()
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
    static let ssSky    = Color(red: 0.290, green: 0.620, blue: 0.980)

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
