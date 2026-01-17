import AVFoundation
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Task {
            let audioSession = AVAudioSession.sharedInstance()
            var mediaServicesResetNotifications = NotificationCenter.default
                .notifications(named: AVAudioSession.mediaServicesWereResetNotification, object: audioSession)
                .compactMap { _ in }
                .makeAsyncIterator()

            repeat {
                try? audioSession.setCategory(.playback)
                await mediaServicesResetNotifications.next()
            } while true
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
