import AVFoundation
import AVKit
import UIKit
import MuxPlayerSwift

class SimpleVideoPlayerViewController: UIViewController {
    private let downloadButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Download", for: .normal)
        button.addTarget(self, action: #selector(downloadButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let downloadProgressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.isHidden = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        return progressView
    }()

    lazy var playerViewController: AVPlayerViewController = {
        AVPlayerViewController(playbackID: playbackID)
    }()

    private let offlineManager = OfflineVideoManager.shared

    var playbackID: String {
        ProcessInfo.processInfo.playbackID ?? "PAP1WZVI007wgouokhmNHNTX6Z8U8gJw5mW01NubR9L7w"
    }

    var monitoringOptions: MonitoringOptions {
        if let environmentKey = ProcessInfo.processInfo.environmentKey {
            return MonitoringOptions(environmentKey: environmentKey, playerName: "OfflineSwiftMux")
        }
        return MonitoringOptions(playbackID: playbackID)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        setupPlayer()
        offlineManager.delegate = self
        updateDownloadUI()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        playerViewController.player?.pause()
    }

    deinit {
        playerViewController.stopMonitoring()
    }

    private func setupUI() {
        view.addSubview(downloadButton)
        view.addSubview(downloadProgressView)

        NSLayoutConstraint.activate([
            downloadButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            downloadButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            downloadProgressView.topAnchor.constraint(equalTo: downloadButton.bottomAnchor, constant: 10),
            downloadProgressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            downloadProgressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
    }

    private func setupPlayer() {
        if let offlineURL = offlineManager.getDownloadedAssetLocation(for: playbackID) {
            let asset = AVURLAsset(url: offlineURL)
            playerViewController.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        } else {
            playerViewController.prepare(playbackID: playbackID, playbackOptions: PlaybackOptions(), monitoringOptions: monitoringOptions)
        }

        addChild(playerViewController)
        view.addSubview(playerViewController.view)
        playerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerViewController.view.topAnchor.constraint(equalTo: downloadProgressView.bottomAnchor, constant: 20),
            playerViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        playerViewController.didMove(toParent: self)
    }

    @objc private func downloadButtonTapped() {
        let state = offlineManager.getDownloadState(for: playbackID)
        switch state {
        case .notDownloaded, .error:
            offlineManager.startDownload(for: playbackID)
        case .downloading:
            offlineManager.cancelDownload(for: playbackID)
        case .downloaded:
            offlineManager.deleteDownload(for: playbackID)
        }
    }

    private func updateDownloadUI() {
        let state = offlineManager.getDownloadState(for: playbackID)
        switch state {
        case .notDownloaded:
            downloadButton.setTitle("Download", for: .normal)
            downloadProgressView.isHidden = true
            downloadProgressView.progress = 0
        case .downloading:
            downloadButton.setTitle("Cancel", for: .normal)
            downloadProgressView.isHidden = false
        case .downloaded:
            downloadButton.setTitle("Delete", for: .normal)
            downloadProgressView.isHidden = true
            downloadProgressView.progress = 1.0
        case .error:
            downloadButton.setTitle("Retry", for: .normal)
            downloadProgressView.isHidden = true
            downloadProgressView.progress = 0
        }
    }
}

extension SimpleVideoPlayerViewController: OfflineVideoManagerDelegate {
    func downloadProgress(_ progress: Double, for playbackID: String) {
        guard playbackID == self.playbackID else { return }
        DispatchQueue.main.async {
            self.downloadProgressView.progress = Float(progress)
        }
    }

    func downloadStateChanged(_ state: DownloadState, for playbackID: String) {
        guard playbackID == self.playbackID else { return }
        DispatchQueue.main.async {
            self.updateDownloadUI()
        }
    }

    func downloadCompleted(for playbackID: String, location: URL) {
        guard playbackID == self.playbackID else { return }
        DispatchQueue.main.async {
            self.updateDownloadUI()
        }
    }

    func downloadFailed(for playbackID: String, error: Error) {
        guard playbackID == self.playbackID else { return }
        DispatchQueue.main.async {
            self.updateDownloadUI()
        }
    }
}
