import NetworkExtension

/// Управление VPN-профилем (NETunnelProviderManager).
final class VPNManager {

    static let shared = VPNManager()
    static let extBundleID = "com.yourid.VlessApp.VlessPacketTunnel"

    enum State: String {
        case off = "disconnected"
        case connecting = "connecting"
        case connected = "connected"
    }

    private(set) var manager: NETunnelProviderManager?

    var status: State {
        switch manager?.connection.status ?? .invalid {
        case .connected: return .connected
        case .connecting, .reasserting: return .connecting
        default: return .off
        }
    }

    var session: NETunnelProviderSession? {
        return manager?.connection as? NETunnelProviderSession
    }

    /// Загружает (или создаёт) наш профиль. Фильтрует только профили
    /// нашего extension — чужие VPN не трогаем, дубликаты удаляем.
    func prepare(completion: @escaping (Error?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error { completion(error); return }

            let ours = (managers ?? []).filter { manager in
                let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
                return proto?.providerBundleIdentifier == VPNManager.extBundleID
            }
            for extra in ours.dropFirst() { extra.removeFromPreferences() }

            let manager = ours.first ?? NETunnelProviderManager()
            manager.loadFromPreferences { loadError in
                if loadError != nil || !VPNManager.isConfigured(manager) {
                    let proto = NETunnelProviderProtocol()
                    proto.providerBundleIdentifier = VPNManager.extBundleID
                    proto.serverAddress = ServerStore.shared.selected?.address ?? "VLESS"
                    proto.providerConfiguration = ["version": NSNumber(value: 1)]
                    manager.protocolConfiguration = proto
                    manager.localizedDescription = "VLESS"
                } else if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol {
                    proto.serverAddress = ServerStore.shared.selected?.address ?? proto.serverAddress ?? "VLESS"
                    manager.protocolConfiguration = proto
                }
                manager.isEnabled = true
                manager.saveToPreferences { saveError in
                    manager.loadFromPreferences { _ in
                        self.manager = manager
                        completion(saveError)
                    }
                }
            }
        }
    }

    private static func isConfigured(_ manager: NETunnelProviderManager) -> Bool {
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
              proto.providerBundleIdentifier == VPNManager.extBundleID else {
            return false
        }
        return manager.localizedDescription == "VLESS"
    }

    func connect(completion: @escaping (Error?) -> Void) {
        prepare { [weak self] error in
            if let error = error { completion(error); return }
            guard let strongSelf = self, let session = strongSelf.session else {
                completion(NSError(domain: "Vless", code: 10,
                                   userInfo: [NSLocalizedDescriptionKey: "Не удалось создать VPN-профиль"]))
                return
            }
            do {
                try session.startVPNTunnel()
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func disconnect() {
        session?.stopVPNTunnel()
    }

    /// Переподключение с новым выбранным сервером.
    func reconnect(completion: @escaping (Error?) -> Void) {
        disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.connect(completion: completion)
        }
    }
}
