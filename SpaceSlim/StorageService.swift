import Foundation
import Combine

class StorageService: ObservableObject {
    @Published var totalSpace: Int64 = 0
    @Published var usedSpace: Int64 = 0
    @Published var freeSpace: Int64 = 0

    var usedPercent: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace)
    }

    init() {
        refresh()
    }

    func refresh() {
        let fileManager = FileManager.default
        let path = NSHomeDirectory()

        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: path)
            if let total = attributes[.systemSize] as? Int64,
               let free = attributes[.systemFreeSize] as? Int64 {
                self.totalSpace = total
                self.freeSpace = free
                self.usedSpace = total - free
            }
        } catch {
            print("Error getting storage info: \(error)")
        }
    }

    func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
