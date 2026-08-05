import Photos
import Vision
import SwiftUI
import Combine
import CoreGraphics

class PhotoService: ObservableObject {
    @Published var similarGroups: [PhotoGroup] = []
    @Published var duplicateGroups: [PhotoGroup] = []
    @Published var blurryPhotos: [PHAsset] = []
    /// Photos that contain at least one detected face (people / portraits).
    @Published var portraitPhotos: [PHAsset] = []
    @Published var isScanning = false
    @Published var progress: Double = 0
    /// Human-readable stage label surfaced during a live scan.
    @Published var scanStage: String = ""
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    private let imageManager = PHCachingImageManager()

    /// Laplacian-variance threshold below which a photo counts as blurry,
    /// measured on the 299×299 fast-format thumbnail we already fetch. Driven by
    /// the Settings "scan depth": Deep raises the bar so more borderline-blurry
    /// photos get flagged.
    private var blurThreshold: Double {
        UserDefaults.standard.string(forKey: "scanDepth") == "deep" ? 110 : 55
    }

    init() {
        checkAuthorization()
    }

    func checkAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    @discardableResult
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.authorizationStatus = status
        }
        return status
    }

    func scanForSimilarAndDuplicatePhotos() async {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }

        await MainActor.run {
            self.isScanning = true
            self.progress = 0
            self.scanStage = "Preparing…"
            self.similarGroups = []
            self.duplicateGroups = []
            self.blurryPhotos = []
            self.portraitPhotos = []
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var fingerprints: [(asset: PHAsset, fingerprint: VNFeaturePrintObservation)] = []
        var blurry: [PHAsset] = []
        var portraits: [PHAsset] = []
        let total = allPhotos.count
        let threshold = blurThreshold

        // Phase 1 — analyze each photo once: feature print (for similar/dup),
        // sharpness (for blur) and face presence (for portraits), all reusing
        // the same fetched thumbnail. 0 → 0.85.
        for i in 0..<total {
            let asset = allPhotos.object(at: i)
            let result = await analyzePhoto(for: asset)
            if let fingerprint = result.fingerprint {
                fingerprints.append((asset, fingerprint))
            }
            if result.sharpness < threshold {
                blurry.append(asset)
            }
            if result.hasFace {
                portraits.append(asset)
            }

            let done = i + 1
            await MainActor.run {
                self.progress = Double(done) / Double(max(total, 1)) * 0.85
                self.scanStage = "Analyzing photos \(done)/\(total)"
            }
        }

        // Phase 2 — group by visual distance. 0.85 → 1.0.
        //
        // A naive all-pairs comparison is O(n²) and melts on large libraries.
        // We avoid it with two facts about how near-duplicate photos occur:
        //   1. Bucket by pixel dimensions — differently sized photos are never
        //      near-duplicates, so we only ever compare within one bucket.
        //   2. Sliding window inside each bucket — the fetch is date-sorted, and
        //      bursts / same-scene shots sit next to each other in time, so we
        //      only compare an anchor against the next `window` items.
        // Cost drops from O(n²) to ~O(n · window).
        let window = 20
        let fpCount = fingerprints.count

        var buckets: [String: [Int]] = [:]
        for idx in 0..<fpCount {
            let a = fingerprints[idx].asset
            let key = "\(a.pixelWidth)x\(a.pixelHeight)"
            buckets[key, default: []].append(idx)
        }

        var similar: [PhotoGroup] = []
        var duplicates: [PhotoGroup] = []
        var processedIndices = Set<Int>()
        var anchorsDone = 0

        for (_, indices) in buckets {
            for pos in 0..<indices.count {
                let i = indices[pos]
                anchorsDone += 1
                if processedIndices.contains(i) { continue }

                var currentGroup: [PHAsset] = [fingerprints[i].asset]
                var isDuplicate = false
                let upper = min(pos + window, indices.count)

                for q in (pos + 1)..<upper {
                    let j = indices[q]
                    if processedIndices.contains(j) { continue }

                    do {
                        var distance: Float = 0
                        try fingerprints[i].fingerprint.computeDistance(&distance, to: fingerprints[j].fingerprint)

                        if distance < 1.0 { // Extremely similar = Duplicate
                            currentGroup.append(fingerprints[j].asset)
                            processedIndices.insert(j)
                            isDuplicate = true
                        } else if distance < 10.0 { // Visually similar
                            currentGroup.append(fingerprints[j].asset)
                            processedIndices.insert(j)
                        }
                    } catch {
                        print("Error: \(error)")
                    }
                }

                if currentGroup.count > 1 {
                    if isDuplicate {
                        duplicates.append(PhotoGroup(assets: currentGroup))
                    } else {
                        similar.append(PhotoGroup(assets: currentGroup))
                    }
                }

                if fpCount > 0 && (anchorsDone % 25 == 0 || anchorsDone == fpCount) {
                    let frac = Double(anchorsDone) / Double(fpCount)
                    await MainActor.run {
                        self.progress = 0.85 + frac * 0.15
                        self.scanStage = "Grouping matches…"
                    }
                }
            }
        }

        await MainActor.run {
            self.similarGroups = similar
            self.duplicateGroups = duplicates
            self.blurryPhotos = blurry
            self.portraitPhotos = portraits
            self.progress = 1
            self.scanStage = "Done"
            self.isScanning = false
        }
    }

    /// Fetches one thumbnail per asset and derives the Vision feature print
    /// (similar/dup), a sharpness score (blur) and whether it contains a face
    /// (portraits) from it, so a full scan only touches each photo once.
    private func analyzePhoto(for asset: PHAsset) async -> (fingerprint: VNFeaturePrintObservation?, sharpness: Double, hasFace: Bool) {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .fastFormat

            imageManager.requestImage(for: asset, targetSize: CGSize(width: 299, height: 299), contentMode: .aspectFill, options: options) { image, _ in
                guard let image = image, let cgImage = image.cgImage else {
                    // Couldn't load — treat as sharp so we don't false-flag it.
                    continuation.resume(returning: (nil, .greatestFiniteMagnitude, false))
                    return
                }

                let sharpness = self.laplacianVariance(of: cgImage)

                let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                let featurePrint = VNGenerateImageFeaturePrintRequest()
                let faceRequest = VNDetectFaceRectanglesRequest()

                do {
                    try requestHandler.perform([featurePrint, faceRequest])
                    let hasFace = !((faceRequest.results as? [VNFaceObservation])?.isEmpty ?? true)
                    continuation.resume(returning: (featurePrint.results?.first as? VNFeaturePrintObservation, sharpness, hasFace))
                } catch {
                    continuation.resume(returning: (nil, sharpness, false))
                }
            }
        }
    }

    /// Variance of the Laplacian — a standard, real blur metric. The image is
    /// drawn into a small grayscale buffer, a 4-neighbour Laplacian is applied,
    /// and the variance of the response is returned. Sharp images have strong
    /// high-frequency edges (high variance); blurry ones are flat (low variance).
    private func laplacianVariance(of cgImage: CGImage) -> Double {
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let ctx = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return .greatestFiniteMagnitude
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var sum = 0.0
        var sumSq = 0.0
        var count = 0.0

        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let idx = y * side + x
                let center = Double(pixels[idx])
                let laplacian = 4 * center
                    - Double(pixels[idx - side])
                    - Double(pixels[idx + side])
                    - Double(pixels[idx - 1])
                    - Double(pixels[idx + 1])
                sum += laplacian
                sumSq += laplacian * laplacian
                count += 1
            }
        }

        guard count > 0 else { return .greatestFiniteMagnitude }
        let mean = sum / count
        return (sumSq / count) - (mean * mean)
    }

    func calculateSize(for assets: [PHAsset]) async -> Int64 {
        var totalSize: Int64 = 0
        for asset in assets {
            let resources = PHAssetResource.assetResources(for: asset)
            if let resource = resources.first {
                if let size = resource.value(forKey: "fileSize") as? Int64 {
                    totalSize += size
                }
            }
        }
        return totalSize
    }

    func calculateGroupsSize(groups: [PhotoGroup]) async -> Int64 {
        var totalSize: Int64 = 0
        for group in groups {
            // Reclaimable = Total size of group - size of one photo (the one we keep)
            var groupSize: Int64 = 0
            for asset in group.assets {
                let resources = PHAssetResource.assetResources(for: asset)
                if let size = resources.first?.value(forKey: "fileSize") as? Int64 {
                    groupSize += size
                }
            }
            if !group.assets.isEmpty {
                // Approximate reclaimable by total - 1
                let onePhotoSize = groupSize / Int64(group.assets.count)
                totalSize += (groupSize - onePhotoSize)
            }
        }
        return totalSize
    }
}

struct PhotoGroup: Identifiable {
    let id = UUID()
    let assets: [PHAsset]
    var selectedAssetIds: Set<String> = []
}
