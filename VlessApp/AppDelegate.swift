import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let vc = UINavigationController(rootViewController: MainViewController())
        window?.rootViewController = vc
        return true
    }

    /// Импорт ссылки по схеме vlesslite://<vless://...>
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        let raw = url.absoluteString
        var payload = raw
        if raw.lowercased().hasPrefix("vlesslite://") {
            payload = String(raw.dropFirst("vlesslite://".count))
            payload = payload.removingPercentEncoding ?? payload
        }
        guard payload.lowercased().hasPrefix("vless://") else { return false }
        NotificationCenter.default.post(name: Notification.Name("importLink"),
                                        object: payload)
        return true
    }
}
