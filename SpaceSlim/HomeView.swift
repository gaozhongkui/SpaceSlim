import SwiftUI
import Photos

struct HomeView: View {
    @ObservedObject var photoService: PhotoService
    @ObservedObject var videoService: VideoService
    @ObservedObject var storageService: StorageService

    @State private var categories: [MediaCategory] = [
        MediaCategory(title: "Large videos", subtitle: "Scanning...", sizeGB: 0, proportion: 0, icon: "play.rectangle.fill", color: .ssEmber, isSelected: true),
        MediaCategory(title: "Screenshots", subtitle: "Scanning...", sizeGB: 0, proportion: 0, icon: "camera.viewfinder", color: .ssTeal, isSelected: true),
        MediaCategory(title: "Live Photos", subtitle: "Scanning...", sizeGB: 0, proportion: 0, icon: "livephoto", color: .ssPink, isSelected: true),
        MediaCategory(title: "Screen recordings", subtitle: "Scanning...", sizeGB: 0, proportion: 0, icon: "record.circle", color: .ssCoral, isSelected: false),
        MediaCategory(title: "Blurry photos", subtitle: "Scanning...", sizeGB: 0, proportion: 0, icon: "camera.filters", color: .ssIndigo, isSelected: true),
    ]

    @State private var reclaimableSimilarSize: String = "0 GB"
    @State private var reclaimableDuplicateSize: String = "0 GB"

    private var featureIndex: Int { 0 }
    private var gridIndices: [Int] { Array(1..<categories.count) }
    private var selectedCount: Int { categories.filter(\.isSelected).count }
    private var selectedGB: Double { categories.filter(\.isSelected).reduce(0) { $0 + $1.sizeGB } }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Background
            Color.ssBackground.ignoresSafeArea()

            // Vibrant Background Blobs - SATURATION BOOSTED
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Color.ssViolet.opacity(0.5))
                        .frame(width: 600, height: 600)
                        .blur(radius: 100)
                        .offset(x: -200, y: 0)

                    Circle()
                        .fill(Color.ssTeal.opacity(0.45))
                        .frame(width: 500, height: 500)
                        .blur(radius: 90)
                        .offset(x: geo.size.width - 200, y: 200)

                    Circle()
                        .fill(Color.ssPink.opacity(0.3))
                        .frame(width: 400, height: 400)
                        .blur(radius: 80)
                        .offset(x: 100, y: geo.size.height - 400)
                }
            }
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Text("SpaceSlim")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(Color.ssTextPrimary)
                        Spacer()

                        if photoService.isScanning || videoService.isScanning {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.8)
                                Text("Scanning...").font(.system(size: 12, weight: .semibold)).foregroundColor(.ssViolet)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color.ssViolet.opacity(0.12)))
                        }

                        Button {} label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 18))
                                .foregroundColor(Color.ssTextSecondary)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                    }

                    // 1. Storage Overview
                    StorageGaugeView(
                        usedGB: Double(storageService.usedSpace) / 1024 / 1024 / 1024,
                        totalGB: Double(storageService.totalSpace) / 1024 / 1024 / 1024
                    )

                    // 2. Quick-access tiles
                    HStack(spacing: 14) {
                        NavigationLink(destination: SimilarPhotosView(photoService: photoService)) {
                            QuickAccessTile(
                                icon: "photo.on.rectangle.angled",
                                count: photoService.similarGroups.count,
                                label: "Similar photos",
                                sizeLabel: "≈ \(reclaimableSimilarSize) free",
                                gradient: [.ssEmber, Color(red: 1, green: 0.54, blue: 0.23)],
                                tint: .ssEmber
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: DuplicatePhotosView(photoService: photoService)) {
                            QuickAccessTile(
                                icon: "square.on.square",
                                count: photoService.duplicateGroups.count,
                                label: "Duplicates",
                                sizeLabel: "≈ \(reclaimableDuplicateSize) free",
                                gradient: [.ssCoral, Color(red: 0.91, green: 0.26, blue: 0.23)],
                                tint: .ssCoral
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // 3. Media Cleanup
                    VStack(spacing: 12) {
                        HStack(alignment: .lastTextBaseline) {
                            Text("MEDIA CLEANUP")
                                .font(.system(size: 13, weight: .bold))
                                .tracking(0.8)
                                .foregroundColor(Color.ssTextTertiary)
                            Spacer()
                            Text("\(categories.count) categories found")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.ssTeal)
                        }
                        .padding(.top, 8)

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

                        VideoCompressionCard(onCompress: {
                            // compression flow
                        })

                        CleanupSummaryBar(selectedCount: selectedCount, selectedGB: selectedGB, onClean: {
                            // bulk clean flow
                        })
                    }

                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            // Start Scan Button
            Button {
                startGlobalScan()
            } label: {
                HStack(spacing: 10) {
                    if photoService.isScanning || videoService.isScanning {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(photoService.isScanning || videoService.isScanning ? "Scanning Library..." : "Start scan")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing))
                )
                .shadow(color: .ssViolet.opacity(0.45), radius: 15, y: 10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 25)
        }
        .onAppear {
            storageService.refresh()
            updateRealData()
        }
        .onChange(of: photoService.isScanning) { scanning in
            if !scanning { updateRealData() }
        }
    }

    private func startGlobalScan() {
        if photoService.authorizationStatus == .notDetermined {
            Task { await photoService.requestAuthorization() }
        } else {
            Task { await photoService.scanForSimilarAndDuplicatePhotos() }
            videoService.fetchAndClassifyVideos()
        }
    }

    private func updateRealData() {
        Task {
            let screenshots = fetchAssets(subtype: .photoScreenshot)
            let livePhotos = fetchAssets(subtype: .photoLive)

            // Calculate real sizes asynchronously
            async let screenshotsSize = photoService.calculateSize(for: screenshots)
            async let livePhotosSize = photoService.calculateSize(for: livePhotos)
            async let largeVideosSize = videoService.calculateSize(for: videoService.cameraVideos)
            async let screenRecordingsSize = videoService.calculateSize(for: videoService.screenRecordings)

            let sSize = await screenshotsSize
            let lSize = await livePhotosSize
            let lvSize = await largeVideosSize
            let srSize = await screenRecordingsSize

            // Reclaimable sizes for top tiles
            async let similarSize = photoService.calculateGroupsSize(groups: photoService.similarGroups)
            async let duplicateSize = photoService.calculateGroupsSize(groups: photoService.duplicateGroups)

            let simSize = await similarSize
            let dupSize = await duplicateSize

            // Update UI on main thread
            await MainActor.run {
                self.reclaimableSimilarSize = formatGB(simSize)
                self.reclaimableDuplicateSize = formatGB(dupSize)

                var newCategories: [MediaCategory] = []

                let categoriesRaw = [
                    (title: "Large videos", count: videoService.cameraVideos.count, size: lvSize, icon: "play.rectangle.fill", color: Color.ssEmber),
                    (title: "Screenshots", count: screenshots.count, size: sSize, icon: "camera.viewfinder", color: Color.ssTeal),
                    (title: "Live Photos", count: livePhotos.count, size: lSize, icon: "livephoto", color: Color.ssPink),
                    (title: "Screen recordings", count: videoService.screenRecordings.count, size: srSize, icon: "record.circle", color: Color.ssCoral),
                    (title: "Blurry photos", count: 0, size: 0, icon: "camera.filters", color: Color.ssIndigo)
                ]

                let maxSize = categoriesRaw.map { $0.size }.max() ?? 1

                for item in categoriesRaw {
                    newCategories.append(MediaCategory(
                        title: item.title,
                        subtitle: "\(item.count) items",
                        sizeGB: Double(item.size) / 1024 / 1024 / 1024,
                        proportion: Double(item.size) / Double(maxSize),
                        icon: item.icon,
                        color: item.color,
                        isSelected: true
                    ))
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

    private func formatGB(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1024 / 1024 / 1024
        return String(format: "%.1f GB", gb)
    }

    @ViewBuilder
    private func destinationFor(category: MediaCategory) -> some View {
        if category.title == "Screenshots" {
            SimilarPhotosView(photoService: photoService)
        } else if category.title == "Screen recordings" {
            VideoClassificationView(videoService: videoService)
        } else {
            VideoCompressionView(videoService: videoService)
        }
    }
}

// MARK: - Subviews

struct QuickAccessTile: View {
    var icon: String
    var count: Int
    var label: String
    var sizeLabel: String
    var gradient: [Color]
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer(minLength: 15)
            Text("\(count)")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(Color.ssTextPrimary)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.ssTextSecondary)
                .padding(.top, 4)
            Text(sizeLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.ssTextTertiary)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading)
        .glassCard(radius: 28, tint: tint)
    }
}

struct StorageGaugeView: View {
    var usedGB: Double
    var totalGB: Double
    var percentUsed: Double { totalGB > 0 ? usedGB / totalGB : 0 }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.ssTrack, lineWidth: 18)
                Circle()
                    .trim(from: 0, to: CGFloat(percentUsed))
                    .stroke(AngularGradient(colors: [.ssViolet, .ssTeal], center: .center), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .ssViolet.opacity(0.5), radius: 10)

                VStack(spacing: 8) {
                    Text(usedGB, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.ssTextPrimary)
                    Text("GB used of \(Int(totalGB)) GB")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.ssTextTertiary)
                    Text("\(Int(percentUsed * 100))% full")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Color.ssCoral))
                }
            }
            .frame(width: 240, height: 240)

            Text("Clean up to boost device performance")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.ssTextSecondary)
                .padding(.top, 12)
        }
        .padding(.vertical, 32).padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 35)
    }
}

struct MediaFeatureCard: View {
    var category: MediaCategory
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [category.color, category.color.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                Image(systemName: category.icon).font(.system(size: 22, weight: .bold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.title).font(.system(size: 16, weight: .bold)).foregroundColor(Color.ssTextPrimary)
                        Text(category.subtitle).font(.system(size: 12)).foregroundColor(Color.ssTextSecondary)
                    }
                    Spacer()
                    Text(category.sizeGB, format: .number.precision(.fractionLength(1))).font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundColor(Color.ssTextPrimary)
                    + Text(" GB").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(Color.ssTextTertiary)
                }
                ProportionBar(value: category.proportion, color: category.color)
            }
        }
        .padding(18).glassCard(radius: 26, tint: category.color)
    }
}

struct MediaGridCard: View {
    @Binding var category: MediaCategory
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [category.color, category.color.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    Image(systemName: category.icon).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                }
                Spacer()
                ZStack {
                    Circle().strokeBorder(category.isSelected ? Color.clear : Color.ssTextTertiary.opacity(0.5), lineWidth: 1.8)
                        .background(category.isSelected ? AnyView(Circle().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))) : AnyView(Color.clear))
                    if category.isSelected { Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundColor(.white) }
                }.frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(category.title).font(.system(size: 14, weight: .bold)).foregroundColor(Color.ssTextPrimary)
                Text(category.subtitle).font(.system(size: 11)).foregroundColor(Color.ssTextSecondary)
            }
            ProportionBar(value: category.proportion, color: category.color)
            HStack {
                Text(category.sizeGB, format: .number.precision(.fractionLength(1))).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(Color.ssTextPrimary)
                + Text(" GB").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(Color.ssTextTertiary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(Color.ssTextTertiary)
            }
        }
        .padding(16).glassCard(radius: 24, tint: category.color)
    }
}

struct VideoCompressionCard: View {
    var onCompress: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [.ssViolet, Color(red: 0.3, green: 0.25, blue: 0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                Image(systemName: "rectangle.compress.vertical").font(.system(size: 20, weight: .bold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Video compression").font(.system(size: 15, weight: .bold)).foregroundColor(Color.ssTextPrimary)
                Text("Shrink without quality loss").font(.system(size: 12)).foregroundColor(Color.ssTextSecondary).lineLimit(1)
            }
            Spacer()
            Button(action: onCompress) {
                Text("Compress").font(.system(size: 13, weight: .bold)).foregroundColor(.white).padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(LinearGradient(colors: [.ssViolet, Color(red: 0.37, green: 0.55, blue: 0.94)], startPoint: .leading, endPoint: .trailing)))
            }.buttonStyle(.plain)
        }
        .padding(18).background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(LinearGradient(colors: [.ssViolet.opacity(0.15), .ssTeal.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .glassCard(radius: 26)
    }
}

struct CleanupSummaryBar: View {
    var selectedCount: Int
    var selectedGB: Double
    var onClean: () -> Void
    var body: some View {
        HStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundColor(.white)
                }.frame(width: 22, height: 22)
                Text("\(selectedCount) selected").font(.system(size: 13, weight: .semibold)).foregroundColor(Color.ssTextSecondary)
            }
            Spacer()
            HStack(spacing: 12) {
                Text(selectedGB, format: .number.precision(.fractionLength(1))).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundColor(Color.ssTextPrimary)
                + Text(" GB").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(Color.ssTextSecondary)
                Button(action: onClean) {
                    Text("Clean").font(.system(size: 14, weight: .bold)).foregroundColor(.white).padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing))).shadow(color: .ssViolet.opacity(0.4), radius: 8, y: 4)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16).glassCard(radius: 22)
    }
}

struct ProportionBar: View {
    var value: Double
    var color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ssTrack.opacity(0.15))
                Capsule().fill(color).frame(width: max(4, geo.size.width * value))
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Optimized Version-Specific Glass Card Logic

struct GlassCard: ViewModifier {
    var radius: CGFloat = 24
    var tint: Color = .clear
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // VERSION CHECK: Keep original design for high versions, fix iOS 16
                    if #available(iOS 17.0, *) {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    } else {
                        // iOS 16 SPECIFIC FIX: Ultra-Bright mode to kill the "grey"
                        ZStack {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(.ultraThinMaterial)

                            // 95% White layer to force brightness
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(colorScheme == .dark ? Color.black.opacity(0.4) : Color.white.opacity(0.95))

                            // SHINE EFFECT: Subtle diagonal gradient to make it look reflective
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.2), Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .center
                                    )
                                )
                        }
                    }

                    // High-contrast border - PURE WHITE for that glass edge
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.2) : Color.white.opacity(1.0),
                            lineWidth: 1.5
                        )

                    // Vibrant color tint
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(tint.opacity(colorScheme == .dark ? 0.15 : 0.25))
                }
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 15, x: 0, y: 10)
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
        self.init(UIColor { trait in trait.userInterfaceStyle == .dark ? dark : light })
    }
    static let ssViolet = Color(red: 0.486, green: 0.435, blue: 0.941)
    static let ssTeal   = Color(red: 0.204, green: 0.906, blue: 0.776)
    static let ssEmber  = Color(red: 1.000, green: 0.714, blue: 0.282)
    static let ssCoral  = Color(red: 1.000, green: 0.420, blue: 0.361)
    static let ssPink   = Color(red: 1.000, green: 0.498, blue: 0.690)
    static let ssIndigo = Color(red: 0.608, green: 0.549, blue: 0.969)
    static let ssBackground = Color(light: UIColor(red: 0.96, green: 0.96, blue: 0.99, alpha: 1), dark: UIColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 1))
    static let ssTextPrimary = Color(light: UIColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1), dark: UIColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 1))
    static let ssTextSecondary = Color(light: UIColor(red: 0.3, green: 0.3, blue: 0.4, alpha: 1), dark: UIColor(red: 0.7, green: 0.7, blue: 0.8, alpha: 1))
    static let ssTextTertiary = Color(light: UIColor(red: 0.5, green: 0.5, blue: 0.6, alpha: 1), dark: UIColor(red: 0.4, green: 0.4, blue: 0.5, alpha: 1))
    static let ssTrack = Color(light: UIColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 0.1), dark: UIColor(white: 1, alpha: 0.15))
}

struct MediaCategory: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let sizeGB: Double
    let proportion: Double
    let icon: String
    let color: Color
    var isSelected: Bool
}
