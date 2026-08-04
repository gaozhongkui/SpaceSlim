import Photos
import Vision
import SwiftUI
import Combine

class PhotoService: ObservableObject {
    @Published var similarGroups: [PhotoGroup] = []
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

    func scanForSimilarPhotos() async {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }

        DispatchQueue.main.async {
            self.isScanning = true
            self.progress = 0
            self.similarGroups = []
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

        // Grouping logic (Simplified for now: comparing adjacent fingerprints)
        var groups: [PhotoGroup] = []
        var currentGroup: [PHAsset] = []

        for i in 0..<fingerprints.count {
            if currentGroup.isEmpty {
                currentGroup.append(fingerprints[i].asset)
                continue
            }

            let previousFingerprint = fingerprints[i-1].fingerprint
            let currentFingerprint = fingerprints[i].fingerprint

            do {
                var distance: Float = 0
                try previousFingerprint.computeDistance(&distance, to: currentFingerprint)

                // Distance < 10 is usually very similar
                if distance < 10.0 {
                    currentGroup.append(fingerprints[i].asset)
                } else {
                    if currentGroup.count > 1 {
                        groups.append(PhotoGroup(assets: currentGroup))
                    }
                    currentGroup = [fingerprints[i].asset]
                }
            } catch {
                print("Error computing distance: \(error)")
            }
        }

        if currentGroup.count > 1 {
            groups.append(PhotoGroup(assets: currentGroup))
        }

        DispatchQueue.main.async {
            self.similarGroups = groups
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
}

struct PhotoGroup: Identifiable {
    let id = UUID()
    let assets: [PHAsset]
    var selectedAssetIds: Set<String> = []
}
