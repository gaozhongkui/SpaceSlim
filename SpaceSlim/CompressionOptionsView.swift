import SwiftUI
import Photos
import UIKit

/// Full-screen compression configuration page (presented, not a popup): pick
/// ratio + frame rate + whether to replace originals, see an estimated
/// before/after, then run the batch with live progress.
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
    @State private var isCompressing = false
    @State private var currentIndex = 0
    @State private var currentThumbnail: UIImage?
    @State private var originalBytes: Int64 = 0
    @State private var finished = false
    @State private var successCount = 0
    @State private var freedBytesResult: Int64 = 0
    @State private var processedOriginalBytes: Int64 = 0
    @State private var processedCompressedBytes: Int64 = 0

    enum Ratio: String, CaseIterable, Hashable {
        case high = "High quality"
        case balanced = "Balanced"
        case small = "Small size"

        var scale: CGFloat { self == .high ? 0.9 : self == .balanced ? 0.7 : 0.5 }
        var subtitle: String {
            switch self {
            case .high: return "90% resolution · best quality"
            case .balanced: return "70% resolution · recommended"
            case .small: return "50% resolution · smallest file"
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
        var factor: Double { self == .original ? 1.0 : self == .f30 ? 0.92 : self == .f24 ? 0.82 : 0.6 }
    }

    private var estimatedAfter: Int64 {
        Int64(Double(originalBytes) * ratio.estFactor * fps.factor)
    }
    private var estimatedSaved: Int64 { max(originalBytes - estimatedAfter, 0) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ssBackground.ignoresSafeArea()
                if finished {
                    doneView
                } else if isCompressing {
                    compressingView
                } else {
                    optionsForm
                }
            }
            .navigationTitle(finished ? "Done" : "Compress \(assets.count) video\(assets.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isCompressing && !finished {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .alert("Replace originals?", isPresented: $showReplaceWarning) {
                Button("Cancel", role: .cancel) { replaceOriginal = false }
                Button("Continue", role: .destructive) { didWarnReplace = true }
            } message: {
                Text("Each original video will be deleted after its compressed copy is saved. This notice is shown only once.")
            }
        }
        .interactiveDismissDisabled(isCompressing)
        .onAppear {
            originalBytes = assets.reduce(0) { $0 + Self.assetSize($1) }
        }
    }

    // MARK: - Options

    private var optionsForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    estimateCard

                    section("Compression ratio") {
                        VStack(spacing: 8) {
                            ForEach(Ratio.allCases, id: \.self) { option in
                                SelectableRow(title: option.rawValue, subtitle: option.subtitle, selected: ratio == option) {
                                    ratio = option
                                }
                            }
                        }
                    }

                    section("Frame rate") {
                        Picker("Frame rate", selection: $fps) {
                            ForEach(FPSOption.allCases, id: \.self) { option in
                                Text(option == .original ? "Original" : "\(option.rawValue)fps").tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    section("Original videos") {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $replaceOriginal) {
                                Text("Replace originals after compressing")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.ssTextPrimary)
                            }
                            .tint(.ssViolet)
                            .onChange(of: replaceOriginal) { on in
                                if on && !didWarnReplace { showReplaceWarning = true }
                            }
                            Text(replaceOriginal
                                 ? "Originals are deleted once the compressed copy is saved."
                                 : "Originals are kept; a compressed copy is added.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.ssTextTertiary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(radius: 16)
                    }
                }
                .padding(20)
            }

            compressButton
        }
    }

    private var estimateCard: some View {
        VStack(spacing: 12) {
            Text("ESTIMATED RESULT")
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.ssTextTertiary)

            HStack(spacing: 14) {
                estimatePill(label: "Now", value: Self.bytes(originalBytes), color: .ssTextSecondary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ssTextTertiary)
                estimatePill(label: "After", value: Self.bytes(estimatedAfter), color: .ssViolet)
            }

            Text("Save about \(Self.bytes(estimatedSaved))")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.ssTeal)

            Text("Estimate — actual size depends on each video.")
                .font(.system(size: 11))
                .foregroundStyle(Color.ssTextTertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 24)
    }

    private func estimatePill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.ssTextTertiary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private var compressButton: some View {
        Button {
            startCompression()
        } label: {
            Text("Compress")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing)))
                .shadow(color: .ssViolet.opacity(0.4), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Progress

    private var compressingView: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(Color.ssTrack, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(videoService.compressionProgress))
                    .stroke(
                        AngularGradient(colors: [.ssViolet, .ssTeal], center: .center),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                if let thumb = currentThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 130, height: 130)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.ssViolet)
                }
            }
            .frame(width: 180, height: 180)

            Text("\(Int(videoService.compressionProgress * 100))%")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.ssTextPrimary)

            Text("Compressing \(min(currentIndex + 1, assets.count)) of \(assets.count)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ssTextSecondary)

            Text("Keep SpaceSlim open until it finishes.")
                .font(.system(size: 12))
                .foregroundStyle(Color.ssTextTertiary)
        }
        .padding(30)
    }

    // MARK: - Run

    private func startCompression() {
        isCompressing = true
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
                if let compressedSize = await videoService.compressVideo(asset: asset, scale: ratio.scale, frameRate: fps.value) {
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
                finished = true
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

    private var doneView: some View {
        let saved = max(processedOriginalBytes - processedCompressedBytes, 0)
        return VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.ssTeal)

            Text(successCount == assets.count ? "All done!" : "\(successCount) of \(assets.count) compressed")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.ssTextPrimary)

            // Real before/after.
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    resultPill(label: "Before", value: Self.bytes(processedOriginalBytes), color: .ssTextSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.ssTextTertiary)
                    resultPill(label: "After", value: Self.bytes(processedCompressedBytes), color: .ssViolet)
                }
                Text("Saved \(Self.bytes(saved))")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.ssTeal)
                if replaceOriginal && freedBytesResult > 0 {
                    Text("Originals removed")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ssTextTertiary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .glassCard(radius: 24)
            .padding(.horizontal, 30)

            Button {
                onFinished(freedBytesResult, successCount, replaceOriginal)
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding(.vertical, 30)
    }

    private func resultPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.ssTextTertiary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.ssTextTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func assetSize(_ asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).first?.value(forKey: "fileSize") as? Int64 ?? 0
    }

    private static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: value)
    }
}

private struct SelectableRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ssTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ssTextSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? Color.ssViolet : Color.ssTextTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 16, tint: selected ? .ssViolet : .clear)
        }
        .buttonStyle(.plain)
    }
}
