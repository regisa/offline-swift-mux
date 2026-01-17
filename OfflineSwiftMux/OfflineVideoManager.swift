import AVFoundation
import Foundation

enum DownloadState {
    case notDownloaded
    case downloading
    case downloaded
    case error(String)
}

protocol OfflineVideoManagerDelegate: AnyObject {
    func downloadProgress(_ progress: Double, for playbackID: String)
    func downloadStateChanged(_ state: DownloadState, for playbackID: String)
    func downloadCompleted(for playbackID: String, location: URL)
    func downloadFailed(for playbackID: String, error: Error)
}

class OfflineVideoManager: NSObject {
    static let shared = OfflineVideoManager()
    weak var delegate: OfflineVideoManagerDelegate?

    private var downloadSession: AVAssetDownloadURLSession!
    private var activeDownloads: [String: AVAssetDownloadTask] = [:]
    private let userDefaults = UserDefaults.standard
    private let downloadedAssetsKey = "downloadedAssets"
    private let downloadStateKey = "downloadState"

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.regisa.OfflineSwiftMux.download")
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        downloadSession = AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: OperationQueue.main
        )
    }

    func hlsURL(for playbackID: String) -> URL? {
        return URL(string: "https://stream.mux.com/\(playbackID).m3u8")
    }

    func startDownload(for playbackID: String) {
        if isDownloaded(playbackID: playbackID) {
            delegate?.downloadStateChanged(.downloaded, for: playbackID)
            return
        }

        if activeDownloads[playbackID] != nil { return }

        guard let hlsURL = hlsURL(for: playbackID) else {
            let error = NSError(domain: "OfflineVideoManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid playback ID"])
            updateDownloadState(.error(error.localizedDescription), for: playbackID)
            delegate?.downloadFailed(for: playbackID, error: error)
            return
        }

        let asset = AVURLAsset(url: hlsURL)
        guard let downloadTask = downloadSession.makeAssetDownloadTask(asset: asset, assetTitle: "Video \(playbackID)", assetArtworkData: nil, options: nil) else {
            let error = NSError(domain: "OfflineVideoManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create download task"])
            updateDownloadState(.error(error.localizedDescription), for: playbackID)
            delegate?.downloadFailed(for: playbackID, error: error)
            return
        }

        activeDownloads[playbackID] = downloadTask
        downloadTask.resume()
        updateDownloadState(.downloading, for: playbackID)
        delegate?.downloadStateChanged(.downloading, for: playbackID)
    }

    func cancelDownload(for playbackID: String) {
        guard let downloadTask = activeDownloads[playbackID] else { return }
        downloadTask.cancel()
        activeDownloads.removeValue(forKey: playbackID)
        updateDownloadState(.notDownloaded, for: playbackID)
        delegate?.downloadStateChanged(.notDownloaded, for: playbackID)
    }

    func isDownloaded(playbackID: String) -> Bool {
        guard let assetLocation = getDownloadedAssetLocation(for: playbackID),
              FileManager.default.fileExists(atPath: assetLocation.path) else {
            if getDownloadedAssetLocation(for: playbackID) != nil {
                deleteDownload(for: playbackID)
            }
            return false
        }
        return true
    }

    func getDownloadedAssetLocation(for playbackID: String) -> URL? {
        guard let locationString = userDefaults.string(forKey: "\(downloadedAssetsKey)_\(playbackID)") else { return nil }
        return URL(fileURLWithPath: locationString)
    }

    func getDownloadState(for playbackID: String) -> DownloadState {
        if isDownloaded(playbackID: playbackID) { return .downloaded }
        if activeDownloads[playbackID] != nil { return .downloading }
        if let stateString = userDefaults.string(forKey: "\(downloadStateKey)_\(playbackID)"), stateString == "error" {
            let errorMessage = userDefaults.string(forKey: "\(downloadStateKey)_\(playbackID)_error") ?? "Unknown error"
            return .error(errorMessage)
        }
        return .notDownloaded
    }

    func deleteDownload(for playbackID: String) {
        if let downloadTask = activeDownloads[playbackID] {
            downloadTask.cancel()
            activeDownloads.removeValue(forKey: playbackID)
        }
        userDefaults.removeObject(forKey: "\(downloadedAssetsKey)_\(playbackID)")
        userDefaults.removeObject(forKey: "\(downloadStateKey)_\(playbackID)")
        userDefaults.removeObject(forKey: "\(downloadStateKey)_\(playbackID)_error")
        delegate?.downloadStateChanged(.notDownloaded, for: playbackID)
    }

    private func updateDownloadState(_ state: DownloadState, for playbackID: String) {
        let key = "\(downloadStateKey)_\(playbackID)"
        switch state {
        case .notDownloaded:
            userDefaults.removeObject(forKey: key)
            userDefaults.removeObject(forKey: "\(key)_error")
        case .downloading:
            userDefaults.set("downloading", forKey: key)
        case .downloaded:
            userDefaults.set("downloaded", forKey: key)
        case .error(let message):
            userDefaults.set("error", forKey: key)
            userDefaults.set(message, forKey: "\(key)_error")
        }
    }

    private func saveDownloadedAssetLocation(_ location: URL, for playbackID: String) {
        userDefaults.set(location.path, forKey: "\(downloadedAssetsKey)_\(playbackID)")
    }
}

extension OfflineVideoManager: AVAssetDownloadDelegate {
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let playbackID = activeDownloads.first(where: { $0.value == assetDownloadTask })?.key else { return }
        activeDownloads.removeValue(forKey: playbackID)
        saveDownloadedAssetLocation(location, for: playbackID)
        updateDownloadState(.downloaded, for: playbackID)
        delegate?.downloadCompleted(for: playbackID, location: location)
        delegate?.downloadStateChanged(.downloaded, for: playbackID)
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        guard let playbackID = activeDownloads.first(where: { $0.value == assetDownloadTask })?.key else { return }
        let progress = timeRangeExpectedToLoad.duration.seconds > 0 ? timeRange.duration.seconds / timeRangeExpectedToLoad.duration.seconds : 0.0
        delegate?.downloadProgress(progress, for: playbackID)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let assetDownloadTask = task as? AVAssetDownloadTask,
              let playbackID = activeDownloads.first(where: { $0.value == assetDownloadTask })?.key else { return }
        activeDownloads.removeValue(forKey: playbackID)

        if let error = error {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                updateDownloadState(.notDownloaded, for: playbackID)
                delegate?.downloadStateChanged(.notDownloaded, for: playbackID)
                return
            }
            let errorMessage = error.localizedDescription
            updateDownloadState(.error(errorMessage), for: playbackID)
            delegate?.downloadFailed(for: playbackID, error: error)
            delegate?.downloadStateChanged(.error(errorMessage), for: playbackID)
        }
    }
}
