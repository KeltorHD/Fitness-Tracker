import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    if UserDefaults.standard.bool(forKey: "cloudSync"),
      !ProcessInfo.processInfo.arguments.contains("--ui-testing")
    {
      application.registerForRemoteNotifications()
    }
    return true
  }
}
