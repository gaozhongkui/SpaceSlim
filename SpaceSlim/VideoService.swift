import Photos
import AVFoundation
import Combine
import SwiftUI

class VideoService: ObservableObject {
    @Published var screenRecordings: [PHAsset] = []
    @Published var cameraVideos: [PHAsset] = []
    @Published var isScanning = false
    @Published var compressionProgress: Double = 0
    @Published var isCompressing = false

    private let imageManager = PHCachingImageManager()

    func fetchAndClassifyVideos() {
        isScanning = true
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allVideos = PHAsset.fetchAssets(with: .video, options: fetchOptions)

        var tempScreenRecordings: [PHAsset] = []
        var tempCameraVideos: [PHAsset] = []

        allVideos.enumerateObjects { (asset, _, _) in
            if asset.mediaSubtypes.contains(.videoScreenRecording) {
                tempScreenRecordings.append(asset)
            } else {
                tempCameraVideos.append(asset)
            }
        }

        DispatchQueue.main.async {
            self.screenRecordings = tempScreenRecordings
            self.cameraVideos = tempCameraVideos
            self.isScanning = false
        }
    }

    func compressVideo(asset: PHAsset, quality: String) async {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard let avAsset = avAsset as? AVURLAsset else {
                    continuation.resume()
                    return
                }

                let exportPreset: String
                switch quality {
                case "Low": exportPreset = AVAssetExportPresetLowQuality
                case "Medium": exportPreset = AVAssetExportPresetMediumQuality
                default: exportPreset = AVAssetExportPresetHighestQuality
                }

                guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: exportPreset) else {
                    continuation.resume()
                    return
                }

                let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
                exportSession.outputURL = outputURL
                exportSession.outputFileType = .mp4

                DispatchQueue.main.async {
                    self.isCompressing = true
                    self.compressionProgress = 0
                }

                // Monitor progress (simplified)
                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                    DispatchQueue.main.async {
                        self.compressionProgress = Double(exportSession.progress)
                        if exportSession.status != .exporting {
                            timer.invalidate()
                        }
                    }
                }

                exportSession.exportAsynchronously {
                    DispatchQueue.main.async {
                        self.isCompressing = false
                        if exportSession.status == .completed {
                            print("Compression completed: \(outputURL)")
                            // Here you would typically save to library or show success
                        }
                        continuation.resume()
                    }
                }
            }
        }
    }
}
