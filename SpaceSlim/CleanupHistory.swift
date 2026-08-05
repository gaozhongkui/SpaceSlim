import Foundation
import SwiftUI
import Combine

// MARK: - Model

struct CleanupRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let freedBytes: Int64
    let itemCount: Int
    let kind: Kind

    enum Kind: String, Codable {
        case cleanup
        case compression

        var label: String {
            switch self {
            case .cleanup: return "Cleanup"
            case .compression: return "Compression"
            }
        }

        var icon: String {
            switch self {
            case .cleanup: return "trash.fill"
            case .compression: return "rectangle.compress.vertical"
            }
        }
    }

    init(id: UUID = UUID(), date: Date, freedBytes: Int64, itemCount: Int, kind: Kind) {
        self.id = id
        self.date = date
        self.freedBytes = freedBytes
        self.itemCount = itemCount
        self.kind = kind
    }
}

// MARK: - Store

/// Persists cleanup/compression events so the History page can show what the
/// user has reclaimed over time. Backed by UserDefaults (JSON).
final class CleanupHistoryStore: ObservableObject {
    @Published private(set) var records: [CleanupRecord] = []

    private let key = "SpaceSlim.cleanupHistory"

    init() { load() }

    var totalFreed: Int64 { records.reduce(0) { $0 + $1.freedBytes } }

    func add(freedBytes: Int64, itemCount: Int, kind: CleanupRecord.Kind) {
        guard freedBytes > 0 || itemCount > 0 else { return }
        let record = CleanupRecord(date: Date(), freedBytes: freedBytes, itemCount: itemCount, kind: kind)
        records.insert(record, at: 0)
        save()
    }

    func clear() {
        records = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CleanupRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - History page

struct HistoryView: View {
    @ObservedObject var store: CleanupHistoryStore

    var body: some View {
        Group {
            if store.records.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        HStack {
                            Text("Total reclaimed")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text(Self.bytes(store.totalFreed))
                                .font(.system(size: 17, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.ssViolet)
                        }
                    }

                    Section("Activity") {
                        ForEach(store.records) { record in
                            HStack(spacing: 12) {
                                Image(systemName: record.kind.icon)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(record.kind == .compression ? Color.ssViolet : Color.ssCoral)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.kind.label)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Self.bytes(record.freedBytes))
                                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    Text("\(record.itemCount) item\(record.itemCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.records.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear", role: .destructive) { store.clear() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(Color.ssTextTertiary)
            Text("No history yet")
                .font(.headline)
            Text("Cleanups and compressions you run will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: value)
    }
}
