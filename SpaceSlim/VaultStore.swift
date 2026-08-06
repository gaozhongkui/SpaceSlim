import Foundation
import Combine
import CryptoKit
import Photos
import UIKit

/// One encrypted item in the private vault.
struct VaultItem: Identifiable, Codable {
    let id: UUID
    let isVideo: Bool
    let createdAt: Date
    let fileName: String     // "<id>.enc"
    let thumbName: String    // "<id>.thumb.enc" ("" if none)
    let byteSize: Int64
}

/// Encrypted, Face-ID-gated media store. Files live in Application Support
/// (excluded from iCloud backup) and are encrypted at rest with an AES-256 key
/// kept in the Keychain. Importing copies the original into the vault and then
/// removes it from the system Photos library ("真隐藏").
@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var items: [VaultItem] = []
    @Published var isBusy = false

    private let dir: URL
    private let indexURL: URL
    private let key: SymmetricKey

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var folder = base.appendingPathComponent("Vault", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        dir = folder
        indexURL = folder.appendingPathComponent("index.json")
        key = VaultStore.loadOrCreateKey()
        loadIndex()
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.byteSize } }

    // MARK: - Index

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([VaultItem].self, from: data) else { return }
        items = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: - Crypto

    private func seal(_ data: Data) -> Data? { try? AES.GCM.seal(data, using: key).combined }
    private func open(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    func data(for item: VaultItem) -> Data? {
        guard let enc = try? Data(contentsOf: dir.appendingPathComponent(item.fileName)) else { return nil }
        return open(enc)
    }

    func thumbnail(for item: VaultItem) -> UIImage? {
        guard !item.thumbName.isEmpty,
              let enc = try? Data(contentsOf: dir.appendingPathComponent(item.thumbName)),
              let data = open(enc) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Import (copy → encrypt → remove original)

    @discardableResult
    func importAssets(_ assets: [PHAsset]) async -> (added: Int, removedOriginals: Bool) {
        guard !assets.isEmpty else { return (0, false) }
        isBusy = true
        defer { isBusy = false }

        var added: [VaultItem] = []
        for asset in assets {
            guard let payload = await Self.exportData(for: asset), let enc = seal(payload.data) else { continue }
            let id = UUID()
            let fileName = "\(id.uuidString).enc"
            do {
                try enc.write(to: dir.appendingPathComponent(fileName), options: .atomic)
            } catch { continue }

            var thumbName = ""
            if let thumb = await Self.thumbnailData(for: asset), let encThumb = seal(thumb) {
                thumbName = "\(id.uuidString).thumb.enc"
                try? encThumb.write(to: dir.appendingPathComponent(thumbName), options: .atomic)
            }

            added.append(VaultItem(id: id, isVideo: payload.isVideo, createdAt: Date(),
                                   fileName: fileName, thumbName: thumbName, byteSize: Int64(payload.data.count)))
        }

        guard !added.isEmpty else { return (0, false) }

        // Now remove the originals from Photos (system shows its own confirmation).
        let removed = await Self.deleteAssets(assets)

        items.insert(contentsOf: added, at: 0)
        saveIndex()
        return (added.count, removed)
    }

    // MARK: - Remove from vault (permanent)

    func remove(_ targets: Set<UUID>) {
        for item in items where targets.contains(item.id) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(item.fileName))
            if !item.thumbName.isEmpty {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(item.thumbName))
            }
        }
        items.removeAll { targets.contains($0.id) }
        saveIndex()
    }

    // MARK: - Export back to Photos (un-hide)

    @discardableResult
    func export(_ targets: Set<UUID>) async -> Int {
        isBusy = true
        defer { isBusy = false }
        var exported = 0
        let toExport = items.filter { targets.contains($0.id) }
        for item in toExport {
            guard let data = data(for: item) else { continue }
            let ext = item.isVideo ? "mov" : "jpg"
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.id.uuidString).\(ext)")
            try? data.write(to: tmp, options: .atomic)
            if await Self.saveToPhotos(url: tmp, isVideo: item.isVideo) { exported += 1 }
            try? FileManager.default.removeItem(at: tmp)
        }
        remove(targets)
        return exported
    }

    // MARK: - Keychain key

    private static func loadOrCreateKey() -> SymmetricKey {
        let account = "com.space.disk.slim.vault.key"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(add as CFDictionary, nil)
        return newKey
    }

    // MARK: - PHAsset helpers

    private struct Payload { let data: Data; let isVideo: Bool }

    private static func exportData(for asset: PHAsset) async -> Payload? {
        if asset.mediaType == .video {
            let resources = PHAssetResource.assetResources(for: asset)
            guard let res = resources.first(where: { $0.type == .video }) ?? resources.first else { return nil }
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            return await withCheckedContinuation { continuation in
                var acc = Data()
                PHAssetResourceManager.default().requestData(for: res, options: options) { chunk in
                    acc.append(chunk)
                } completionHandler: { error in
                    continuation.resume(returning: error == nil ? Payload(data: acc, isVideo: true) : nil)
                }
            }
        } else {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            return await withCheckedContinuation { continuation in
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                    continuation.resume(returning: data.map { Payload(data: $0, isVideo: false) })
                }
            }
        }
    }

    private static func thumbnailData(for asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 400, height: 400), contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image?.jpegData(compressionQuality: 0.8))
            }
        }
    }

    private static func deleteAssets(_ assets: [PHAsset]) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            } completionHandler: { success, _ in continuation.resume(returning: success) }
        }
    }

    private static func saveToPhotos(url: URL, isVideo: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: isVideo ? .video : .photo, fileURL: url, options: nil)
            } completionHandler: { success, _ in continuation.resume(returning: success) }
        }
    }
}
