import SwiftUI
import Photos
import UIKit
import Combine
import AVFoundation

// MARK: - SwiftUI bridge

/// UIKit-backed video compression list. Kept as a `UIViewControllerRepresentable`
/// named `VideoCompressionView` so existing SwiftUI call sites (HomeView /
/// ContentView) don't change.
struct VideoCompressionView: UIViewControllerRepresentable {
    @ObservedObject var videoService: VideoService

    func makeUIViewController(context: Context) -> VideoCompressionViewController {
        VideoCompressionViewController(videoService: videoService)
    }

    func updateUIViewController(_ uiViewController: VideoCompressionViewController, context: Context) {}
}

// MARK: - View controller

final class VideoCompressionViewController: UIViewController {
    /// UserDefaults flag: whether the one-time "replace original" notice was shown.
    private static let didWarnReplaceKey = "SpaceSlim.didWarnReplaceOriginal"

    private let videoService: VideoService
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let imageManager = PHCachingImageManager()
    private var videos: [PHAsset] = []
    private var selectedIDs = Set<String>()
    private var cancellables = Set<AnyCancellable>()

    // Bottom action bar with the single "Compress" button.
    private let bottomBar = UIView()
    private let compressButton = UIButton(type: .system)

    // Loading overlay shown while exports run.
    private let overlayView = UIView()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let progressLabel = UILabel()

    // Empty-state label.
    private let emptyLabel = UILabel()

    init(videoService: VideoService) {
        self.videoService = videoService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Video Compression"
        view.backgroundColor = .systemGroupedBackground
        setupBottomBar()
        setupTableView()
        setupEmptyState()
        setupOverlay()
        bind()
        fetchVideos()
        updateCompressButton()
    }

    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = .secondarySystemBackground

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        bottomBar.addSubview(separator)

        compressButton.translatesAutoresizingMaskIntoConstraints = false
        compressButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor(red: 0.486, green: 0.435, blue: 0.941, alpha: 1) // ssViolet
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        compressButton.configuration = config
        compressButton.addTarget(self, action: #selector(compressTapped), for: .touchUpInside)

        bottomBar.addSubview(compressButton)
        view.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            separator.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            compressButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 10),
            compressButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            compressButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            compressButton.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 84
        tableView.allowsMultipleSelection = true
        tableView.register(VideoCompressionCell.self, forCellReuseIdentifier: VideoCompressionCell.reuseID)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
        ])
    }

    private func setupEmptyState() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No videos found"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func setupOverlay() {
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        overlayView.isHidden = true

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 14

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.text = "Compressing… 0%"
        progressLabel.font = .preferredFont(forTextStyle: .subheadline)
        progressLabel.textColor = .label
        progressLabel.textAlignment = .center
        progressLabel.numberOfLines = 0

        card.addSubview(progressView)
        card.addSubview(progressLabel)
        overlayView.addSubview(card)
        view.addSubview(overlayView)

        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            card.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 260),

            progressLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            progressLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            progressLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            progressView.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 16),
            progressView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            progressView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            progressView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
        ])
    }

    /// Subscribe to the shared VideoService so the overlay tracks real export progress.
    private func bind() {
        videoService.$compressionProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                self?.progressView.setProgress(Float(progress), animated: true)
            }
            .store(in: &cancellables)
    }

    private func fetchVideos() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: .video, options: options)
            var assets: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in assets.append(asset) }

            DispatchQueue.main.async {
                guard let self else { return }
                self.videos = assets
                // Drop selections that no longer exist.
                let existing = Set(assets.map(\.localIdentifier))
                self.selectedIDs.formIntersection(existing)
                self.emptyLabel.isHidden = !assets.isEmpty
                self.tableView.reloadData()
                self.updateCompressButton()
            }
        }
    }

    private func updateCompressButton() {
        let count = selectedIDs.count
        compressButton.isEnabled = count > 0
        compressButton.alpha = count > 0 ? 1 : 0.5
        var config = compressButton.configuration
        config?.title = count > 0 ? "Compress \(count) video\(count == 1 ? "" : "s")" : "Select videos to compress"
        compressButton.configuration = config
    }

    // MARK: - Compression flow

    @objc private func compressTapped() {
        guard !selectedIDs.isEmpty else { return }
        promptCompression()
    }

    /// Step 1 — pick the resolution ratio.
    private func promptCompression() {
        let sheet = UIAlertController(
            title: "Compression ratio",
            message: "Lower keeps less detail but saves more space.",
            preferredStyle: .actionSheet
        )
        let ratios: [(String, CGFloat)] = [
            ("High quality · 90%", 0.9),
            ("Balanced · 70%", 0.7),
            ("Small size · 50%", 0.5),
        ]
        for (title, scale) in ratios {
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.promptFrameRate(scale: scale)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet)
    }

    /// Step 2 — pick the frame rate.
    private func promptFrameRate(scale: CGFloat) {
        let sheet = UIAlertController(title: "Frame rate", message: nil, preferredStyle: .actionSheet)
        let options: [(String, Int?)] = [
            ("Keep original", nil),
            ("30 fps", 30),
            ("24 fps", 24),
            ("15 fps", 15),
        ]
        for (title, fps) in options {
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.promptDisposition(scale: scale, frameRate: fps)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet)
    }

    /// Step 3 — keep the originals, or replace them with the compressed copies.
    private func promptDisposition(scale: CGFloat, frameRate: Int?) {
        let sheet = UIAlertController(
            title: "Original videos",
            message: "Keep the originals, or replace them with the compressed copies?",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Keep originals", style: .default) { [weak self] _ in
            self?.runBatch(scale: scale, frameRate: frameRate, replaceOriginal: false)
        })
        sheet.addAction(UIAlertAction(title: "Replace originals", style: .destructive) { [weak self] _ in
            self?.confirmReplaceIfNeeded(scale: scale, frameRate: frameRate)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet)
    }

    /// One-time notice the first time the user chooses to replace originals.
    private func confirmReplaceIfNeeded(scale: CGFloat, frameRate: Int?) {
        if UserDefaults.standard.bool(forKey: Self.didWarnReplaceKey) {
            runBatch(scale: scale, frameRate: frameRate, replaceOriginal: true)
            return
        }
        let alert = UIAlertController(
            title: "Replace originals?",
            message: "Each original video will be deleted from Photos after its compressed copy is saved. This notice is shown only once.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .destructive) { [weak self] _ in
            UserDefaults.standard.set(true, forKey: Self.didWarnReplaceKey)
            self?.runBatch(scale: scale, frameRate: frameRate, replaceOriginal: true)
        })
        present(alert, animated: true)
    }

    private func runBatch(scale: CGFloat, frameRate: Int?, replaceOriginal: Bool) {
        let targets = videos.filter { selectedIDs.contains($0.localIdentifier) }
        guard !targets.isEmpty else { return }

        overlayView.isHidden = false
        Task {
            var okCount = 0
            for (index, asset) in targets.enumerated() {
                await MainActor.run {
                    self.progressLabel.text = "Compressing \(index + 1) of \(targets.count)…"
                    self.progressView.setProgress(0, animated: false)
                }
                let success = await videoService.compressVideo(asset: asset, scale: scale, frameRate: frameRate)
                if success {
                    okCount += 1
                    if replaceOriginal { _ = await videoService.deleteVideo(asset: asset) }
                }
            }

            await MainActor.run {
                self.overlayView.isHidden = true
                self.selectedIDs.removeAll()
                self.fetchVideos()
                self.showBatchResult(okCount: okCount, total: targets.count, replaced: replaceOriginal)
            }
        }
    }

    private func showBatchResult(okCount: Int, total: Int, replaced: Bool) {
        let title = okCount == total ? "Done" : (okCount == 0 ? "Failed" : "Partly done")
        var message = "\(okCount) of \(total) video\(total == 1 ? "" : "s") compressed and saved to Photos."
        if replaced && okCount > 0 { message += " Originals removed." }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// Anchors action sheets for iPad/regular-width presentation.
    private func presentSheet(_ sheet: UIAlertController) {
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = compressButton
            popover.sourceRect = compressButton.bounds
        }
        present(sheet, animated: true)
    }
}

// MARK: - Data source / delegate

extension VideoCompressionViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        videos.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VideoCompressionCell.reuseID, for: indexPath) as! VideoCompressionCell
        let asset = videos[indexPath.row]
        cell.configure(with: asset, imageManager: imageManager, isSelected: selectedIDs.contains(asset.localIdentifier))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let asset = videos[indexPath.row]
        let id = asset.localIdentifier
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        if let cell = tableView.cellForRow(at: indexPath) as? VideoCompressionCell {
            cell.setChecked(selectedIDs.contains(id))
        }
        updateCompressButton()
    }
}

// MARK: - Cell

final class VideoCompressionCell: UITableViewCell {
    static let reuseID = "VideoCompressionCell"

    private let thumbnailView = UIImageView()
    private let durationBadge = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let checkmark = UIImageView()

    private var representedAssetID: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        selectionStyle = .none

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 8
        thumbnailView.backgroundColor = .tertiarySystemFill

        durationBadge.translatesAutoresizingMaskIntoConstraints = false
        durationBadge.font = .systemFont(ofSize: 10, weight: .semibold)
        durationBadge.textColor = .white
        durationBadge.textAlignment = .center
        durationBadge.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        durationBadge.layer.cornerRadius = 4
        durationBadge.clipsToBounds = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .label

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabel

        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkmark.contentMode = .scaleAspectFit
        checkmark.tintColor = UIColor(red: 0.486, green: 0.435, blue: 0.941, alpha: 1) // ssViolet
        checkmark.setContentHuggingPriority(.required, for: .horizontal)

        contentView.addSubview(thumbnailView)
        thumbnailView.addSubview(durationBadge)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(checkmark)

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 60),
            thumbnailView.heightAnchor.constraint(equalToConstant: 60),

            durationBadge.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: -3),
            durationBadge.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: -3),
            durationBadge.heightAnchor.constraint(equalToConstant: 15),
            durationBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),

            titleLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: thumbnailView.topAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkmark.leadingAnchor, constant: -8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkmark.leadingAnchor, constant: -8),

            checkmark.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmark.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 24),
            checkmark.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    func configure(with asset: PHAsset, imageManager: PHCachingImageManager, isSelected: Bool) {
        representedAssetID = asset.localIdentifier

        titleLabel.text = "Video · \(Self.durationString(asset.duration))"
        if let date = asset.creationDate {
            subtitleLabel.text = "Created \(Self.dateFormatter.string(from: date))"
        } else {
            subtitleLabel.text = "Created —"
        }
        durationBadge.text = " \(Self.durationString(asset.duration)) "
        setChecked(isSelected)

        thumbnailView.image = nil
        let targetSize = CGSize(width: 120, height: 120)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        let assetID = asset.localIdentifier
        imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { [weak self] image, _ in
            guard let self, self.representedAssetID == assetID else { return }
            self.thumbnailView.image = image
        }
    }

    func setChecked(_ checked: Bool) {
        let name = checked ? "checkmark.circle.fill" : "circle"
        checkmark.image = UIImage(systemName: name)
        checkmark.tintColor = checked
            ? UIColor(red: 0.486, green: 0.435, blue: 0.941, alpha: 1)
            : .tertiaryLabel
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.image = nil
        representedAssetID = nil
    }

    // MARK: Formatting helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static func durationString(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
