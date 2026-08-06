import SwiftUI
import Photos
import PhotosUI
import AVKit
import LocalAuthentication

// MARK: - Vault (Face ID gated)

struct VaultView: View {
    @StateObject private var store = VaultStore()
    @Environment(\.dismiss) private var dismiss

    @State private var unlocked = false
    @State private var authFailed = false
    @State private var showPicker = false
    @State private var selection = Set<UUID>()
    @State private var previewItem: VaultItem?
    @State private var toast: String?

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 170), spacing: 6)]

    var body: some View {
        ZStack(alignment: .bottom) {
            HomeBackground()

            if !unlocked {
                lockedScreen
            } else if store.items.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                grid
            }

            if unlocked && !selection.isEmpty {
                actionBar
            }

            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Capsule().fill(Color.ssViolet))
                    .padding(.bottom, 120)
                    .transition(.opacity)
            }

            if store.isBusy {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView("Working…").tint(.white).foregroundStyle(.white)
                        .padding(24)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                }
            }
        }
        .navigationTitle("Private Vault")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tint(.ssViolet)
            }
            if unlocked {
                ToolbarItem(placement: .primaryAction) {
                    Button { showPicker = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.ssViolet)
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            VaultPicker { assets in
                Task {
                    let result = await store.importAssets(assets)
                    showToast(result.added > 0
                              ? "Added \(result.added)\(result.removedOriginals ? " · originals removed" : "")"
                              : "Nothing added")
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $previewItem) { item in
            VaultPreview(store: store, item: item)
        }
        .onAppear { if !unlocked { authenticate() } }
    }

    // MARK: Locked

    private var lockedScreen: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.ssViolet.opacity(0.14)).frame(width: 104, height: 104)
                Image(systemName: authFailed ? "lock.slash.fill" : "lock.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Color.ssViolet)
            }
            Text(authFailed ? "Locked" : "Private Vault")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ssTextPrimary)
            Text("Your hidden photos & videos are encrypted\nand unlocked with Face ID.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ssTextTertiary)
                .multilineTextAlignment(.center)

            Button(action: authenticate) {
                HStack(spacing: 8) {
                    Image(systemName: "faceid").font(.system(size: 16, weight: .bold))
                    Text("Unlock").font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 30).frame(height: 52)
                .background(Capsule().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .leading, endPoint: .trailing)))
                .shadow(color: .ssViolet.opacity(0.4), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Content

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.ssViolet.opacity(0.14)).frame(width: 96, height: 96)
                Image(systemName: "lock.rectangle.stack.fill").font(.system(size: 40, weight: .medium)).foregroundStyle(Color.ssViolet)
            }
            Text("Vault is empty")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ssTextPrimary)
            Text("Tap + to move photos & videos here.\nThey're removed from Photos and hidden.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ssTextTertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var grid: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ssTextPrimary)
                    Text(MediaFormat.bytes(store.totalBytes))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.ssTextTertiary)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)

                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(store.items) { item in
                        VaultThumbCell(store: store, item: item,
                                       isSelected: selection.contains(item.id),
                                       onOpen: { previewItem = item },
                                       onToggle: { toggle(item.id) })
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, selection.isEmpty ? 24 : 108)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Text("\(selection.count) selected")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ssTextPrimary)
            Spacer()
            Button {
                Task {
                    let n = await store.export(selection)
                    selection.removeAll()
                    showToast("\(n) restored to Photos")
                }
            } label: {
                barButton(icon: "square.and.arrow.up", title: "Restore", colors: [.ssViolet, Color(red: 0.42, green: 0.38, blue: 0.9)])
            }
            .buttonStyle(.plain)
            Button {
                store.remove(selection)
                selection.removeAll()
            } label: {
                barButton(icon: "trash.fill", title: "Delete", colors: [.ssCoral, Color(red: 0.91, green: 0.26, blue: 0.23)])
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
        .padding(.horizontal, 16).padding(.bottom, 14)
    }

    private func barButton(icon: String, title: String, colors: [Color]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
            Text(title).font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).frame(height: 44)
        .background(Capsule().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    // MARK: Actions

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation { toast = nil } }
    }

    private func authenticate() {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your Private Vault") { success, _ in
                DispatchQueue.main.async {
                    unlocked = success
                    authFailed = !success
                }
            }
        } else {
            // No passcode/biometrics available (e.g. a simulator without a
            // passcode) — nothing to protect against, so allow access.
            unlocked = true
        }
    }
}

// MARK: - Thumbnail cell

private struct VaultThumbCell: View {
    @ObservedObject var store: VaultStore
    let item: VaultItem
    let isSelected: Bool
    let onOpen: () -> Void
    let onToggle: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .topTrailing) {
                        Rectangle().fill(Color.ssTrack)
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height).clipped()
                        }
                        if isSelected { Color.ssViolet.opacity(0.18) }
                        if item.isVideo {
                            VStack { Spacer(); HStack {
                                Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                    .padding(6).background(Circle().fill(Color.black.opacity(0.4))).padding(6)
                                Spacer() } }
                        }
                        Button(action: onToggle) {
                            ZStack {
                                if isSelected {
                                    Circle().fill(LinearGradient(colors: [.ssViolet, .ssTeal], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 24, height: 24)
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                                } else {
                                    Circle().fill(Color.black.opacity(0.28)).frame(width: 24, height: 24)
                                    Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.6).frame(width: 24, height: 24)
                                }
                            }.padding(7)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Color.ssViolet : Color.white.opacity(0.12), lineWidth: isSelected ? 2.5 : 1))
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen() }
                }
            }
            .task { if image == nil { image = store.thumbnail(for: item) } }
    }
}

// MARK: - Full-screen preview

private struct VaultPreview: View {
    @ObservedObject var store: VaultStore
    let item: VaultItem
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if item.isVideo {
                if let player { VideoPlayer(player: player).ignoresSafeArea() } else { ProgressView().tint(.white) }
            } else {
                if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView().tint(.white) }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.9)).shadow(radius: 4)
                    }.padding(16)
                }
                Spacer()
            }
        }
        .onAppear(perform: load)
        .onDisappear { player?.pause() }
    }

    private func load() {
        guard let data = store.data(for: item) else { return }
        if item.isVideo {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.id.uuidString).mov")
            try? data.write(to: tmp, options: .atomic)
            player = AVPlayer(url: tmp)
            player?.play()
        } else {
            image = UIImage(data: data)
        }
    }
}

// MARK: - Photo picker → PHAssets

private struct VaultPicker: UIViewControllerRepresentable {
    let onPicked: ([PHAsset]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: ([PHAsset]) -> Void
        init(onPicked: @escaping ([PHAsset]) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let ids = results.compactMap { $0.assetIdentifier }
            guard !ids.isEmpty else { return }
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var assets: [PHAsset] = []
            fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
            onPicked(assets)
        }
    }
}
