import Photos
import Vision
import SwiftUI
import Combine

class PhotoService: ObservableObject {
    @Published var similarGroups: [PhotoGroup] = []
    @Published var duplicateGroups: [PhotoGroup] = []
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    private let imageManager = PHCachingImageManager()

    init() {
        checkAuthorization()
    }

    func checkAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
    }

    func scanForSimilarAndDuplicatePhotos() async {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }

        DispatchQueue.main.async {
            self.isScanning = true
            self.progress = 0
            self.similarGroups = []
            self.duplicateGroups = []
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var fingerprints: [(asset: PHAsset, fingerprint: VNFeaturePrintObservation)] = []
        let total = allPhotos.count

        for i in 0..<total {
            let asset = allPhotos.object(at: i)
            if let fingerprint = await getFingerprint(for: asset) {
                fingerprints.append((asset, fingerprint))
            }

            DispatchQueue.main.async {
                self.progress = Double(i + 1) / Double(total)
            }
        }

        // Grouping logic
        var similar: [PhotoGroup] = []
        var duplicates: [PhotoGroup] = []

        // Simple hash-based duplicate detection (by duration/pixel size/etc as proxy or actual data)
        // For real duplicates, we usually compare MD5 or exact pixel data.
        // Here we'll use a very low distance threshold for Vision feature prints.

        var processedIndices = Set<Int>()

        for i in 0..<fingerprints.count {
            if processedIndices.contains(i) { continue }

            var currentGroup: [PHAsset] = [fingerprints[i].asset]
            var isDuplicate = false

            for j in (i + 1)..<fingerprints.count {
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
        }

        DispatchQueue.main.async {
            self.similarGroups = similar
            self.duplicateGroups = duplicates
            self.isScanning = false
        }
    }

    private func getFingerprint(for asset: PHAsset) async -> VNFeaturePrintObservation? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .fastFormat

            imageManager.requestImage(for: asset, targetSize: CGSize(width: 299, height: 299), contentMode: .aspectFill, options: options) { image, _ in
                guard let image = image, let cgImage = image.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }

                let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                let request = VNGenerateImageFeaturePrintRequest()

                do {
                    try requestHandler.perform([request])
                    continuation.resume(returning: request.results?.first as? VNFeaturePrintObservation)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
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
