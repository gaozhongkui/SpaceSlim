import SwiftUI

struct HomeView: View {
    @StateObject private var storageService = StorageService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. 存储概览
                    StorageSummaryCard(storageService: storageService)

                    // 2. Image Analysis
                    VStack(alignment: .leading) {
                        Text("Image Analysis")
                            .font(.headline)
                            .padding(.horizontal)

                        HStack(spacing: 15) {
                            NavigationLink(destination: SimilarPhotosView()) {
                                FeatureCard(title: "Similar Photos", icon: "photo.on.rectangle.angled", color: .blue)
                            }
                            .buttonStyle(.plain)

                            FeatureCard(title: "Duplicates", icon: "photo.stack", color: .purple)
                        }
                        .padding(.horizontal)
                    }

                    // 3. Video Management
                    VStack(alignment: .leading) {
                        Text("Video Management")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 12) {
                            NavigationLink(destination: VideoClassificationView()) {
                                WideFeatureCard(title: "Screen Recording", subtitle: "Auto-identify screen recordings", icon: "rectangle.inset.filled.and.person.filled", color: .orange)
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: VideoCompressionView()) {
                                WideFeatureCard(title: "Video Compression", subtitle: "Reduce size, save space", icon: "arrow.down.right.and.arrow.up.left.anywhere", color: .green)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("SpaceSlim")
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Subviews

struct StorageSummaryCard: View {
    @ObservedObject var storageService: StorageService

    var body: some View {
        VStack(spacing: 15) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Storage")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Used \(Int(storageService.usedPercent * 100))%")
                        .font(.title2.bold())
                }
                Spacer()
                Image(systemName: "chart.pie.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
            }

            ProgressView(value: storageService.usedPercent)
                .tint(.blue)

            HStack {
                Text("Free: \(storageService.formatBytes(storageService.freeSpace))")
                Spacer()
                Text("Total: \(storageService.formatBytes(storageService.totalSpace))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(15)
        .padding(.horizontal)
        .onAppear {
            storageService.refresh()
        }
    }
}

struct FeatureCard: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)

            Text(title)
                .font(.body.weight(.medium))

            Text("Scan")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct WideFeatureCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(color)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

#Preview {
    HomeView()
}
