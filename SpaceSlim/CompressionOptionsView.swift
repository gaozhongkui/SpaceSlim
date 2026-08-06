import SwiftUI
import Photos
import UIKit

/// Pushed compression *options* page: pick ratio + frame rate + whether to
/// replace originals, see an estimated before/after. Tapping "Compress" pushes
/// a separate `CompressionRunView` page for progress + result — nothing about
/// the run is shown inline on this page.
struct CompressionOptionsView: View {
    @ObservedObject var videoService: VideoService
    let assets: [PHAsset]
    /// freedBytes (from replaced originals), successCount, replaced
    let onFinished: (Int64, Int, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("didWarnReplaceOriginal") private var didWarnReplace = false

    @State private var ratio: Ratio = .balanced
    @State private var fps: FPSOption = .original
    @State private var replaceOriginal = false
    @State private var showReplaceWarning = false
    @State private var originalBytes: Int64 = 0
    @State private var showRun = false

    enum Ratio: String, CaseIterable, Hashable {
        case high = "High quality"
        case balanced = "Balanced"
        case small = "Small size"

        var scale: CGFloat { self == .high ? 0.9 : self == .balanced ? 0.7 : 0.5 }
        var percent: String { self == .high ? "90%" : self == .balanced ? "70%" : "50%" }
        var subtitle: String {
            switch self {
            case .high: return "Best quality, gentle savings"
            case .balanced: return "Recommended balance"
            case .small: return "Smallest file size"
            }
        }
        var icon: String {
            switch self {
            case .high: return "sparkles"
            case .balanced: return "dial.medium.fill"
            case .small: return "arrow.down.right.and.arrow.up.left"
            }
        }
        /// Rough size multiplier for the estimate (resolution + re-encode).
        var estFactor: Double { self == .high ? 0.75 : self == .balanced ? 0.5 : 0.3 }
    }

    enum FPSOption: String, CaseIterable, Hashable {
        case original = "Original"
        case f30 = "30"
        case f24 = "24"
        case f15 = "15"

        var value: Int? { self == .original ? nil : Int(rawValue) }
        var label: String { self == .original ? "Original" : "\(rawValue)fps" }
        var factor: Double { self == .original ? 1.0 : self == .f30 ? 0.92 : self == .f24 ? 0.82 : 0.6 }
    }

    private var estimatedAfter: Int64 { Int64(Double(originalBytes) * ratio.estFactor * fps.factor) }
    private var estimatedSaved: Int64 { max(originalBytes - estimatedAfter, 0) }

    var body: some View {
        ZStack {
            HomeBackground()
            optionsForm
        }
        .navigationTitle("Compress \(assets.count) video\(assets.count == 1 ? "" : "s")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tint(.ssViolet)
            }
        }
        .alert("Replace originals?", isPresented: $showReplaceWarning) {
            Button("Cancel", role: .cancel) { replaceOriginal = false }
            Button("Continue", role: .destructive) { didWarnReplace = true }
        } message: {
            Text("Each original video will be deleted after its compressed copy is saved. This notice is shown only once.")
        }
        .navigationDestination(isPresented: $showRun) {
            CompressionRunView(
                videoService: videoService,
                assets: assets,
                scale: ratio.scale,
                frameRate: fps.value,
                replaceOriginal: replaceOriginal,
                onFinished: onFinished
            )
        }
        .onAppear {
            originalBytes = assets.reduce(0) { $0 + Self.assetSize($1) }
        }
    }

    // MARK: - Options

    private var optionsForm: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    estimateCard

                    section("Quality") {
                        VStack(spacing: 10) {
                            ForEach(Ratio.allCases, id: \.self) { option in
                                SelectableRow(
                                    icon: option.icon,
                                    badge: option.percent,
                                    title: option.rawValue,
                                    subtitle: option.subtitle,
                                    selected: ratio == option
                                ) { ratio = option }
                            }
                        }
                    }

                    section("Frame rate") {
                        SegmentedPills(
                            options: FPSOption.allCases,
                            selection: $fps,
                            label: { $0.label }
                        )
                    }

                    section("Original videos") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $replaceOriginal) {
                                Text("Replace originals after compressing")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.ssTextPrimary)
                            }
                            .tint(.ssViolet)
                            .onChange(of: replaceOriginal) { on in
                                if on && !didWarnReplace { showReplaceWarning = true }
                            }
                            Text(replaceOriginal
                                 ? "Originals are deleted once the compressed copy is saved."
                                 : "Originals are kept; a compressed copy is added.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.ssTextTertiary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(radius: 18)
                    }
                }
                .padding(20)
                .padding(.bottom, 8)
            }

            compressButton
        }
    }

    private var estimateCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("ESTIMATED RESULT")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color.ssTextTertiary)
                Spacer()
            }

            VStack(spacing: 4) {
                Text("Save about")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ssTextSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Self.parts(estimatedSaved).value)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(Self.parts(estimatedSaved).unit)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ssTextSecondary)
                }
            }

            SizeCompareBars(before: originalBytes, after: estimatedAfter)

            Text("Estimate — actual size depends on each video.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.ssTextTertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 24)
    }

    private var compressButton: some View {
        Button {
            showRun = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "rectangle.compress.vertical").font(.system(size: 16, weight: .bold))
                Text("Compress \(assets.count) video\(assets.count == 1 ? "" : "s")")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing)))
            .shadow(color: .ssViolet.opacity(0.4), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ssTextPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func assetSize(_ asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).first?.value(forKey: "fileSize") as? Int64 ?? 0
    }

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
}

// MARK: - Run + result (separate pushed page)

/// Pushed page that runs the compression batch and shows live progress, then a
/// result summary. Presented on its own so the run never renders on the options
/// page. Back navigation is blocked while it runs; "Done" pops the whole flow.
struct CompressionRunView: View {
    @ObservedObject var videoService: VideoService
    let assets: [PHAsset]
    let scale: CGFloat
    let frameRate: Int?
    let replaceOriginal: Bool
    let onFinished: (Int64, Int, Bool) -> Void

    @State private var started = false
    @State private var currentIndex = 0
    @State private var currentThumbnail: UIImage?
    @State private var finished = false
    @State private var successCount = 0
    @State private var freedBytesResult: Int64 = 0
    @State private var processedOriginalBytes: Int64 = 0
    @State private var processedCompressedBytes: Int64 = 0

    var body: some View {
        ZStack {
            HomeBackground()
            if finished {
                doneView
            } else {
                compressingView
            }
        }
        .navigationTitle(finished ? "Done" : "Compressing")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(SwipeBackGate(enabled: false))
        .onAppear {
            guard !started else { return }
            started = true
            startCompression()
        }
    }

    // MARK: Progress

    private var compressingView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().stroke(Color.ssTrack, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: CGFloat(videoService.compressionProgress))
                    .stroke(
                        AngularGradient(gradient: Gradient(colors: [.ssTeal, .ssViolet, .ssPink, .ssTeal]), center: .center),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .ssViolet.opacity(0.45), radius: 10)
                    .animation(.easeInOut(duration: 0.25), value: videoService.compressionProgress)

                if let thumb = currentThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 132, height: 132)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 2))
                } else {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(Color.ssViolet)
                }

                VStack {
                    Spacer()
                    Text("\(Int(videoService.compressionProgress * 100))%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                        .offset(y: 18)
                }
                .frame(width: 190, height: 190)
            }
            .frame(width: 190, height: 190)

            VStack(spacing: 6) {
                Text("Compressing \(min(currentIndex + 1, assets.count)) of \(assets.count)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ssTextPrimary)
                Text("Keep SpaceSlim open until it finishes.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ssTextTertiary)
            }
        }
        .padding(30)
    }

    // MARK: Result

    private var doneView: some View {
        let saved = max(processedOriginalBytes - processedCompressedBytes, 0)
        let percent = processedOriginalBytes > 0 ? Int((Double(saved) / Double(processedOriginalBytes)) * 100) : 0
        return VStack(spacing: 22) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 104, height: 104)
                    .shadow(color: .ssTeal.opacity(0.45), radius: 18, y: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 46, weight: .heavy))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text(successCount == assets.count ? "All done!" : "\(successCount) of \(assets.count) compressed")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ssTextPrimary)
                Text("You saved")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ssTextSecondary)
            }

            VStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(CompressionOptionsView.parts(saved).value)
                            .font(.system(size: 50, weight: .bold, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Text(CompressionOptionsView.parts(saved).unit)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.ssTextSecondary)
                    }
                    if percent > 0 {
                        Text("−\(percent)%")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.ssTeal)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.ssTeal.opacity(0.16)))
                    }
                }

                SizeCompareBars(before: processedOriginalBytes, after: processedCompressedBytes)

                if replaceOriginal && freedBytesResult > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill").font(.system(size: 11, weight: .bold))
                        Text("Originals removed")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.ssTextTertiary)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .glassCard(radius: 24)

            Spacer()

            Button {
                onFinished(freedBytesResult, successCount, replaceOriginal)
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing)))
                    .shadow(color: .ssViolet.opacity(0.4), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    // MARK: Run

    private func startCompression() {
        Task {
            var freed: Int64 = 0
            var ok = 0
            var originalTotal: Int64 = 0
            var compressedTotal: Int64 = 0
            for (index, asset) in assets.enumerated() {
                await MainActor.run {
                    currentIndex = index
                    currentThumbnail = nil
                    loadThumbnail(for: asset)
                }
                let before = Self.assetSize(asset)
                if let compressedSize = await videoService.compressVideo(asset: asset, scale: scale, frameRate: frameRate) {
                    ok += 1
                    originalTotal += before
                    compressedTotal += compressedSize
                    if replaceOriginal {
                        let deleted = await videoService.deleteVideo(asset: asset)
                        if deleted { freed += before }
                    }
                }
            }
            await MainActor.run {
                freedBytesResult = freed
                successCount = ok
                processedOriginalBytes = originalTotal
                processedCompressedBytes = compressedTotal
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { finished = true }
            }
        }
    }

    private func loadThumbnail(for asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: options) { image, _ in
            if let image { self.currentThumbnail = image }
        }
    }

    private static func assetSize(_ asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).first?.value(forKey: "fileSize") as? Int64 ?? 0
    }
}

// MARK: - Selectable quality row

private struct SelectableRow: View {
    let icon: String
    let badge: String
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(selected
                              ? AnyShapeStyle(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(Color.ssViolet.opacity(0.14)))
                        .frame(width: 46, height: 46)
                    VStack(spacing: 0) {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .bold))
                        Text(badge)
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(selected ? .white : Color.ssViolet)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ssTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ssTextSecondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .strokeBorder(selected ? Color.clear : Color.ssTextTertiary.opacity(0.5), lineWidth: 1.8)
                        .frame(width: 24, height: 24)
                    if selected {
                        Circle()
                            .fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 18, tint: selected ? .ssViolet : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? Color.ssViolet.opacity(0.7) : Color.clear, lineWidth: 1.8)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented pills

private struct SegmentedPills<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Text(label(option))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : Color.ssTextSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        Group {
                            if isSelected {
                                Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                            }
                        }
                    )
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option }
                    }
            }
        }
    }
}

// MARK: - Before/after size bars

private struct SizeCompareBars: View {
    let before: Int64
    let after: Int64

    var body: some View {
        VStack(spacing: 12) {
            bar(label: "Before", value: before, fraction: 1,
                fill: AnyShapeStyle(Color.ssTextTertiary.opacity(0.55)))
            bar(label: "After", value: after,
                fraction: before > 0 ? min(Double(after) / Double(before), 1) : 0,
                fill: AnyShapeStyle(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing)))
        }
    }

    private func bar(label: String, value: Int64, fraction: Double, fill: AnyShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ssTextSecondary)
                Spacer()
                Text(CompressionOptionsView.bytes(value))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.ssTextPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ssTextTertiary.opacity(0.15))
                    Capsule().fill(fill)
                        .frame(width: max(geo.size.width * CGFloat(fraction), 10))
                }
            }
            .frame(height: 12)
        }
    }
}

// MARK: - Swipe-back gate

/// Disables the navigation interactive pop gesture while `enabled` is false, so
/// an in-progress compression can't be swiped away.
private struct SwipeBackGate: UIViewControllerRepresentable {
    let enabled: Bool

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = enabled
        }
    }
}
