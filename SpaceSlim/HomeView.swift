import SwiftUI
import Photos

// MARK: - Home screen

struct HomeView: View {
    @ObservedObject var photoService: PhotoService
    @ObservedObject var videoService: VideoService
    @ObservedObject var storageService: StorageService
    @Binding var selectedTab: Int

    @State private var categories: [MediaCategory] = [
        MediaCategory(title: "Large videos", subtitle: "Not scanned", sizeGB: 0, proportion: 0, icon: "play.rectangle.fill", color: .ssEmber, isSelected: true),
        MediaCategory(title: "Screenshots", subtitle: "Not scanned", sizeGB: 0, proportion: 0, icon: "camera.viewfinder", color: .ssTeal, isSelected: true),
        MediaCategory(title: "Live Photos", subtitle: "Not scanned", sizeGB: 0, proportion: 0, icon: "livephoto", color: .ssPink, isSelected: true),
        MediaCategory(title: "Screen recordings", subtitle: "Not scanned", sizeGB: 0, proportion: 0, icon: "record.circle", color: .ssCoral, isSelected: false),
        MediaCategory(title: "Blurry photos", subtitle: "Not scanned", sizeGB: 0, proportion: 0, icon: "camera.filters", color: .ssIndigo, isSelected: true),
    ]

    @State private var reclaimableSimilarSize: String = "0 GB"
    @State private var reclaimableDuplicateSize: String = "0 GB"
    @State private var hasScanned = false

    // Bulk cleanup flow
    @State private var pendingCleanupAssets: [PHAsset] = []
    @State private var showCleanConfirm = false
    @State private var cleanupResultMessage = ""
    @State private var showCleanupResult = false

    /// First category is the "feature" (largest); the rest fill the grid.
    private var featureIndex: Int { 0 }
    private var gridIndices: [Int] { Array(1..<categories.count) }

    private var selectedCount: Int { categories.filter(\.isSelected).count }
    private var selectedGB: Double { categories.filter(\.isSelected).reduce(0) { $0 + $1.sizeGB } }

    private var isScanning: Bool { photoService.isScanning || videoService.isScanning }
    private var scanPercent: Int { Int(photoService.progress * 100) }
    private var scanButtonLabel: String {
        if photoService.isScanning && !photoService.scanStage.isEmpty { return photoService.scanStage }
        if isScanning { return "Scanning Library…" }
        return "Start scan"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.ssBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Header
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
                            // history / settings action
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.ssTextSecondary)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                    }

                    // 1. Storage gauge
                    StorageGaugeView(
                        usedGB: Double(storageService.usedSpace) / 1024 / 1024 / 1024,
                        totalGB: Double(storageService.totalSpace) / 1024 / 1024 / 1024
                    )

                    // 2. Quick-access tiles
                    HStack(spacing: 14) {
                        NavigationLink(destination: PhotoGroupsView(title: "Similar photos", groups: photoService.similarGroups)) {
                            QuickAccessTile(
                                icon: "photo.on.rectangle.angled",
                                count: photoService.similarGroups.count,
                                label: "Similar photos",
                                sizeLabel: "≈ \(reclaimableSimilarSize) reclaimable",
                                gradient: [.ssEmber, Color(red: 1, green: 0.541, blue: 0.239)]
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: PhotoGroupsView(title: "Duplicates", groups: photoService.duplicateGroups)) {
                            QuickAccessTile(
                                icon: "square.on.square",
                                count: photoService.duplicateGroups.count,
                                label: "Duplicates",
                                sizeLabel: "≈ \(reclaimableDuplicateSize) reclaimable",
                                gradient: [.ssCoral, Color(red: 0.910, green: 0.263, blue: 0.235)]
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // 3. Media cleanup
                    VStack(spacing: 12) {
                        HStack(alignment: .lastTextBaseline) {
                            Text("MEDIA CLEANUP")
                                .font(.system(size: 13, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(Color.ssTextTertiary)
                            Spacer()
                            Text("\(categories.count) categories found")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.ssTeal)
                        }
                        .padding(.top, 6)

                        NavigationLink(destination: destinationFor(category: categories[featureIndex])) {
                            MediaFeatureCard(category: categories[featureIndex])
                        }
                        .buttonStyle(.plain)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                            ForEach(gridIndices, id: \.self) { i in
                                NavigationLink(destination: destinationFor(category: categories[i])) {
                                    MediaGridCard(category: $categories[i])
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VideoCompressionCard {
                            selectedTab = 1
                        }

                        CleanupSummaryBar(selectedCount: selectedCount, selectedGB: selectedGB) {
                            prepareCleanup()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }

            // Start scan button
            Button {
                startGlobalScan()
            } label: {
                HStack(spacing: 9) {
                    if isScanning {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(scanButtonLabel)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing))
                )
                .shadow(color: .ssViolet.opacity(0.42), radius: 20, y: 10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear {
            storageService.refresh()
            // Kick off a scan automatically on first appearance.
            if !hasScanned && !isScanning {
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
        .alert("Delete \(pendingCleanupAssets.count) items?", isPresented: $showCleanConfirm) {
            Button("Delete", role: .destructive) { performCleanup() }
            Button("Cancel", role: .cancel) { pendingCleanupAssets = [] }
        } message: {
            let parts = spaceSizeParts(gb: selectedGB)
            Text("They'll be removed from Photos, freeing about \(parts.value) \(parts.unit).")
        }
        .alert("Cleanup", isPresented: $showCleanupResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(cleanupResultMessage)
        }
    }

    // MARK: - Data

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

            let sSize = await screenshotsSize
            let lSize = await livePhotosSize
            let lvSize = await largeVideosSize
            let srSize = await screenRecordingsSize
            let blSize = await blurrySize
            let blurryCount = photoService.blurryPhotos.count

            async let similarSize = photoService.calculateGroupsSize(groups: photoService.similarGroups)
            async let duplicateSize = photoService.calculateGroupsSize(groups: photoService.duplicateGroups)

            let simSize = await similarSize
            let dupSize = await duplicateSize

            await MainActor.run {
                self.reclaimableSimilarSize = formatSize(simSize)
                self.reclaimableDuplicateSize = formatSize(dupSize)

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

    @ViewBuilder
    private func destinationFor(category: MediaCategory) -> some View {
        MediaGridView(title: category.title) {
            assetsFor(category: category)
        }
    }

    // MARK: - Bulk cleanup

    /// Collects every asset in the selected categories (de-duplicated) and asks
    /// the user to confirm before deleting.
    private func prepareCleanup() {
        let selected = categories.filter(\.isSelected)
        var seen = Set<String>()
        var assets: [PHAsset] = []
        for category in selected {
            for asset in assetsFor(category: category) where seen.insert(asset.localIdentifier).inserted {
                assets.append(asset)
            }
        }
        pendingCleanupAssets = assets
        guard !assets.isEmpty else {
            cleanupResultMessage = "Nothing to clean in the selected categories."
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
            let success = await deleteAssets(assets)
            await MainActor.run {
                if success {
                    cleanupResultMessage = "Freed \(formatSize(freed)). Rescanning your library…"
                    storageService.refresh()
                    startGlobalScan()   // refresh all categories after deletion
                } else {
                    cleanupResultMessage = "Nothing was deleted."
                }
                showCleanupResult = true
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

    /// Supplies the assets backing each category's detail page.
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
}

// MARK: - Storage gauge

struct StorageGaugeView: View {
    var usedGB: Double
    var totalGB: Double
    var percentUsed: Double { totalGB > 0 ? usedGB / totalGB : 0 }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.ssTrack, lineWidth: 16)

                Circle()
                    .trim(from: 0, to: CGFloat(percentUsed))
                    .stroke(
                        AngularGradient(colors: [.ssViolet, .ssTeal], center: .center),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .ssViolet.opacity(0.4), radius: 8)

                VStack(spacing: 6) {
                    Text(usedGB, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 40, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.ssTextPrimary)
                    Text("GB used of \(Int(totalGB)) GB")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Color.ssTextTertiary)
                    Text("\(Int(percentUsed * 100))% full")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ssCoral)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.ssCoral.opacity(0.14)))
                        .padding(.top, 4)
                }
            }
            .frame(width: 216, height: 216)

            Text("Free up space to keep things running smoothly")
                .font(.system(size: 13))
                .foregroundStyle(Color.ssTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 32)
    }
}

// MARK: - Quick-access tile (Similar Photos / Duplicates)

struct QuickAccessTile: View {
    var icon: String
    var count: Int
    var label: String
    var sizeLabel: String
    var gradient: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 14)

            Text(count, format: .number)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ssTextPrimary)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.ssTextSecondary)
                .padding(.top, 2)
            Text(sizeLabel)
                .font(.system(size: 12))
                .foregroundStyle(Color.ssTextTertiary)
                .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .glassCard(radius: 26)
    }
}

// MARK: - Media cleanup: feature card (single largest category, full width)

struct MediaFeatureCard: View {
    var category: MediaCategory

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [category.color, category.color.opacity(0.7)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                Image(systemName: category.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.ssTextPrimary)
                        Text(category.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ssTextSecondary)
                    }
                    Spacer()
                    Text(spaceSizeParts(gb: category.sizeGB).value)
                        .font(.system(size: 19, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.ssTextPrimary)
                    + Text(" " + spaceSizeParts(gb: category.sizeGB).unit)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.ssTextTertiary)
                }

                ProportionBar(value: category.proportion, color: category.color)
            }
        }
        .padding(16)
        .glassCard(radius: 24)
    }
}

// MARK: - Media cleanup: two-column grid card

struct MediaGridCard: View {
    @Binding var category: MediaCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [category.color, category.color.opacity(0.7)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 34)
                    Image(systemName: category.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button {
                    category.isSelected.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(category.isSelected ? .clear : Color.ssTextTertiary, lineWidth: 1.6)
                            .background(
                                Circle().fill(
                                    category.isSelected
                                        ? AnyShapeStyle(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(Color.clear)
                                )
                            )
                        if category.isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 19, height: 19)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.ssTextPrimary)
                Text(category.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ssTextSecondary)
            }

            ProportionBar(value: category.proportion, color: category.color)

            HStack {
                Text(spaceSizeParts(gb: category.sizeGB).value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.ssTextPrimary)
                + Text(" " + spaceSizeParts(gb: category.sizeGB).unit)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.ssTextTertiary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ssTextTertiary)
            }
        }
        .padding(14)
        .glassCard(radius: 22)
    }
}

private struct ProportionBar: View {
    var value: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ssTrack)
                Capsule().fill(color)
                    .frame(width: max(4, geo.size.width * value))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Action card (Video compression — a transform, not a delete)

struct VideoCompressionCard: View {
    var onCompress: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [.ssViolet, Color(red: 0.298, green: 0.247, blue: 0.796)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: "rectangle.compress.vertical")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Video compression")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Color.ssTextPrimary)
                Text("Shrink without losing quality")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ssTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 8)

            Button(action: onCompress) {
                Text("Compress")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(LinearGradient(colors: [.ssViolet, Color(red: 0.369, green: 0.549, blue: 0.941)], startPoint: .leading, endPoint: .trailing)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [.ssViolet.opacity(0.14), .ssTeal.opacity(0.10)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .glassCard(radius: 24)
    }
}

// MARK: - Summary bar (bulk selection footer)

struct CleanupSummaryBar: View {
    var selectedCount: Int
    var selectedGB: Double
    var onClean: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 19, height: 19)

                Text("\(selectedCount) categories selected")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.ssTextSecondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Text(spaceSizeParts(gb: selectedGB).value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.ssTextPrimary)
                + Text(" " + spaceSizeParts(gb: selectedGB).unit)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.ssTextSecondary)

                Button(action: onClean) {
                    Text("Clean")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing)))
                        .shadow(color: .ssViolet.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassCard(radius: 20)
    }
}

// MARK: - Reusable glass surface

/// The glassmorphism card style used across the screen.
///
/// On iOS 17+ we use the mockup's design verbatim: a translucent
/// `.ultraThinMaterial` with a hairline border, which reads as clean glass.
///
/// On iOS 16 the same material renders muddy/grey over light backgrounds and
/// loses the glass look, so we apply a compensation pass — a brightening wash
/// plus a diagonal shine — to recover a comparable appearance.
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
            // Modern systems: the material is already clean and translucent.
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(tint.opacity(0.12))
            }
        } else {
            // iOS 16: the plain material renders grey on light backgrounds and
            // can't be cleaned up reliably, so drop the blur and use an opaque
            // card surface — fully controllable and guaranteed not to look grey.
            // A soft diagonal shine keeps a hint of the glassy highlight.
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
    /// A color that adapts between light and dark without relying on an asset
    /// catalog — handy for single-file reuse.
    init(light: UIColor, dark: UIColor) {
        self.init(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let ssViolet = Color(red: 0.486, green: 0.435, blue: 0.941)   // #7C6FF0
    static let ssTeal   = Color(red: 0.204, green: 0.906, blue: 0.776)   // #34E7C6
    static let ssEmber  = Color(red: 1.000, green: 0.714, blue: 0.282)   // #FFB648
    static let ssCoral  = Color(red: 1.000, green: 0.420, blue: 0.361)   // #FF6B5C
    static let ssPink   = Color(red: 1.000, green: 0.498, blue: 0.690)   // #FF7FB0
    static let ssIndigo = Color(red: 0.608, green: 0.549, blue: 0.969)   // #9B8CF7

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

    /// Solid card surface used on iOS 16, where `.ultraThinMaterial` renders
    /// muddy grey and can't be cleaned up reliably. Opaque and fully
    /// controllable: near-white in light mode, one step brighter than the
    /// background in dark mode.
    static let ssCardSolid = Color(light: UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1),
                                    dark:  UIColor(red: 0.098, green: 0.114, blue: 0.169, alpha: 1))
}

// MARK: - Models

struct MediaCategory: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let sizeGB: Double
    let proportion: Double   // 0...1, relative to the largest category
    let icon: String
    let color: Color
    var isSelected: Bool
}

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
