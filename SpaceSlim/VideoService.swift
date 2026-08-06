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
        DispatchQueue.main.async { self.isScanning = true }

        DispatchQueue.global(qos: .userInitiated).async {
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
    }

    /// Removes deleted videos from the in-memory classification so the
    /// dashboard stays accurate after a delete.
    func remove(assetIDs ids: Set<String>) {
        guard !ids.isEmpty else { return }
        cameraVideos.removeAll { ids.contains($0.localIdentifier) }
        screenRecordings.removeAll { ids.contains($0.localIdentifier) }
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

    /// Compresses a video to a chosen resolution `scale` (0…1 of the original
    /// dimensions) and optional target `frameRate` (nil = keep original), then
    /// saves the result back into the photo library.
    ///
    /// Uses an AVAssetReader → AVAssetWriter transcode so we can control the
    /// exact output size, frame rate (by dropping frames) and bitrate — none of
    /// which the fixed export presets allow. Returns whether it succeeded.
    /// Compresses the video and saves it back to Photos. Returns the compressed
    /// output size in bytes on success, or nil on failure.
    @discardableResult
    func compressVideo(asset: PHAsset, scale: CGFloat, frameRate: Int?) async -> Int64? {
        await MainActor.run {
            self.isCompressing = true
            self.compressionProgress = 0
        }

        var outputBytes: Int64?
        if let avAsset = await requestAVAsset(for: asset),
           let outputURL = await transcode(avAsset: avAsset, scale: scale, frameRate: frameRate) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            let saved = await saveToPhotoLibrary(url: outputURL)
            try? FileManager.default.removeItem(at: outputURL)
            if saved { outputBytes = size }
        }

        await MainActor.run {
            self.isCompressing = false
            self.compressionProgress = outputBytes != nil ? 1 : 0
        }
        return outputBytes
    }

    private func requestAVAsset(for asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    /// Runs the reader/writer pipeline. Returns the output URL on success.
    private func transcode(avAsset: AVAsset, scale: CGFloat, frameRate: Int?) async -> URL? {
        guard let videoTrack = avAsset.tracks(withMediaType: .video).first else { return nil }
        let audioTrack = avAsset.tracks(withMediaType: .audio).first

        // Target size — scale the natural (pre-rotation) size, keep it even.
        let naturalSize = videoTrack.naturalSize
        let clampedScale = min(max(scale, 0.1), 1.0)
        var width = Int((naturalSize.width * clampedScale).rounded())
        var height = Int((naturalSize.height * clampedScale).rounded())
        width -= width % 2
        height -= height % 2
        width = max(width, 2)
        height = max(height, 2)

        let sourceFPS = videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : 30
        let targetFPS = Float(frameRate ?? Int(sourceFPS.rounded()))
        let bitrate = max(Int(Float(width * height) * targetFPS * 0.12), 200_000)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        guard let reader = try? AVAssetReader(asset: avAsset),
              let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            return nil
        }

        // Video reader → writer
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        )
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { return nil }
        reader.add(videoOutput)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalKey: Int(targetFPS.rounded()),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.transform = videoTrack.preferredTransform   // preserve orientation
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { return nil }
        writer.add(videoInput)

        // Audio reader → writer (re-encode to AAC)
        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack {
            let aOut = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM]
            )
            if reader.canAdd(aOut) {
                reader.add(aOut)
                audioOutput = aOut
                let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 2,
                    AVSampleRateKey: 44_100,
                    AVEncoderBitRateKey: 128_000
                ])
                aIn.expectsMediaDataInRealTime = false
                if writer.canAdd(aIn) {
                    writer.add(aIn)
                    audioInput = aIn
                }
            }
        }

        guard reader.startReading(), writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        let totalDuration = CMTimeGetSeconds(avAsset.duration)
        // Minimum spacing between kept frames, to hit the target fps by dropping.
        let frameInterval: Double = frameRate != nil ? (1.0 / Double(frameRate!)) : 0

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()

            group.enter()
            let videoQueue = DispatchQueue(label: "com.spaceslim.compress.video")
            var lastKeptSeconds = -Double.greatestFiniteMagnitude
            videoInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
                while videoInput.isReadyForMoreMediaData {
                    guard reader.status == .reading,
                          let sample = videoOutput.copyNextSampleBuffer() else {
                        videoInput.markAsFinished()
                        group.leave()
                        break
                    }

                    let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))

                    // Drop frames to reach the requested frame rate.
                    if frameInterval > 0, seconds - lastKeptSeconds < frameInterval - 0.001 {
                        continue
                    }
                    lastKeptSeconds = seconds

                    videoInput.append(sample)

                    if totalDuration > 0 {
                        let progress = min(seconds / totalDuration, 1.0)
                        DispatchQueue.main.async { self?.compressionProgress = progress }
                    }
                }
            }

            if let audioInput, let audioOutput {
                group.enter()
                let audioQueue = DispatchQueue(label: "com.spaceslim.compress.audio")
                audioInput.requestMediaDataWhenReady(on: audioQueue) {
                    while audioInput.isReadyForMoreMediaData {
                        guard reader.status == .reading,
                              let sample = audioOutput.copyNextSampleBuffer() else {
                            audioInput.markAsFinished()
                            group.leave()
                            break
                        }
                        audioInput.append(sample)
                    }
                }
            }

            group.notify(queue: .main) {
                writer.finishWriting {
                    continuation.resume()
                }
            }
        }

        return writer.status == .completed ? outputURL : nil
    }

    private func saveToPhotoLibrary(url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: nil)
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    /// Deletes an asset from the photo library. The system shows its own
    /// confirmation prompt; `success` reflects whether the user confirmed.
    func deleteVideo(asset: PHAsset) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
