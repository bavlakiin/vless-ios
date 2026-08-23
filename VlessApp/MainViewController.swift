import UIKit
import NetworkExtension

let appGroup = "group.vless.shared"   // == App Groups capability, одинаковый в app и extension

class MainViewController: UIViewController {

    private let statusLabel = UILabel()
    private let toggle = UIButton(type: .system)
    private let importField = UITextField()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "VLESS"

        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        importField.placeholder = "vless://... (вставьте и нажмите Import)"
        importField.borderStyle = .roundedRect
        importField.autocorrectionType = .no
        importField.font = UIFont.systemFont(ofSize: 13)

        toggle.setTitle("Connect", for: .normal)
        toggle.titleLabel?.font = UIFont.boldSystemFont(ofSize: 20)
        toggle.addTarget(self, action: #selector(toggleVPN), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [importField, importButton, toggle, statusLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(vpnChanged),
            name: .NEVPNStatusDidChange, object: nil)
        updateStatus()
    }

    private lazy var importButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Import profile", for: .normal)
        b.addTarget(self, action: #selector(importProfile), for: .touchUpInside)
        return b
    }()

    @objc private func importProfile() {
        guard let text = importField.text, let profile = VlessParser.parse(text) else {
            statusLabel.text = "Некорректная ссылка vless://"
            return
        }
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults(suiteName: appGroup)?.set(data, forKey: "profile")
        }
        statusLabel.text = "Профиль сохранён: \(profile.name)"
    }

    @objc private func toggleVPN() {
        VPNManager.shared.toggle { [weak self] error in
            if let error = error { self?.statusLabel.text = "Ошибка: \(error.localizedDescription)" }
            else { self?.updateStatus() }
        }
    }

    @objc private func vpnChanged() { updateStatus() }

    private func updateStatus() {
        let s = VPNManager.shared.status
        statusLabel.text = "VPN: \(s.rawValue)"
        toggle.setTitle(s == .connected ? "Disconnect" : "Connect", for: .normal)
    }
}

/// Управление VPN-конфигурацией (NETunnelProviderManager).
class VPNManager {

    static let shared = VPNManager()
    enum State: String { case off = "disconnected", connected = "connected", connecting = "connecting" }

    var status: State {
        switch session?.status ?? .invalid {
        case .connected: return .connected
        case .connecting, .reasserting: return .connecting
        default: return .off
        }
    }

    private var manager: NETunnelProviderManager?
    private var session: NETunnelProviderSession? { manager?.connection as? NETunnelProviderSession }

    func toggle(completion: @escaping (Error?) -> Void) {
        if status == .connected || status == .connecting {
            session?.stopVPNTunnel()
            completion(nil)
        } else {
            enable(completion: completion)
        }
    }

    private func enable(completion: @escaping (Error?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            let manager = managers?.first ?? NETunnelProviderManager()
            manager.loadFromPreferences { error in
                let proto = NETunnelProviderProtocol()
                proto.providerBundleIdentifier = "com.yourid.VlessApp.VlessPacketTunnel"
                proto.providerConfiguration = [:]
                proto.serverAddress = "VLESS"
                manager.protocolConfiguration = proto
                manager.localizedDescription = "VLESS"
                manager.isEnabled = true
                manager.saveToPreferences { error in
                    manager.loadFromPreferences { _ in
                        do {
                            self?.manager = manager
                            try (manager.connection as? NETunnelProviderSession)?
                                .startVPNTunnel()
                            completion(nil)
                        } catch { completion(error) }
                    }
                }
            }
        }
    }
}
