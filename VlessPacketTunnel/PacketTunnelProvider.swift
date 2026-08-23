import NetworkExtension
import VlessCore   // фреймворк из scripts/build-core.sh

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var xrayStarted = false
    private var tunStarted = false

    override func startTunnel(options: [String: Any]?,
                              completionHandler: @escaping (Error?) -> Void) {
        guard let data = UserDefaults(suiteName: "group.vless.shared")?.data(forKey: "profile"),
              let profile = try? JSONDecoder().decode(VlessProfile.self, from: data) else {
            completionHandler(NSError(domain: "Vless", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Профиль не найден — импортируйте vless:// в приложении"]))
            return
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        settings.mtu = 1400

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let strongSelf = self else { return }
            if let error = error { completionHandler(error); return }

            // 1. Xray-core: локальный SOCKS5 127.0.0.1:10808 с VLESS-outbound
            do {
                let json = Self.xrayConfig(for: profile)
                try VlessCoreXrayStart(json)
                strongSelf.xrayStarted = true
            } catch {
                completionHandler(error); return
            }

            // 2. tun2socks: пакеты из packetFlow -> SOCKS5 Xray
            let fd = strongSelf.packetFlow.value(forKey: "socketFileDescriptor") as? Int32 ?? -1
            guard fd >= 0 else {
                completionHandler(NSError(domain: "Vless", code: 2,
                                          userInfo: [NSLocalizedDescriptionKey: "Не удалось получить дескриптор tun"]))
                return
            }
            do {
                try VlessCoreTun2SocksStart(fd, "socks5://127.0.0.1:10808", "198.18.0.1/24")
                strongSelf.tunStarted = true
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        if tunStarted { try? VlessCoreTun2SocksStop() }
        if xrayStarted { try? VlessCoreXrayStop() }
        completionHandler()
    }

    /// JSON-конфиг Xray под VLESS-профиль.
    static func xrayConfig(for p: VlessProfile) -> String {
        var stream: [String: Any] = ["network": p.network, "security": p.security]
        if p.network == "ws" {
            stream["wsSettings"] = ["path": p.path ?? "/",
                                    "headers": ["Host": p.sni ?? p.address]]
        } else if p.network == "grpc" {
            stream["grpcSettings"] = ["serviceName": p.path ?? ""]
        }
        if p.security == "reality" {
            stream["realitySettings"] = [
                "serverName": p.sni ?? "",
                "fingerprint": p.fingerprint ?? "chrome",
                "publicKey": p.publicKey ?? "",
                "shortId": p.shortId ?? ""
            ] as [String: Any]
        } else if p.security == "tls" {
            stream["tlsSettings"] = [
                "serverName": p.sni ?? "",
                "allowInsecure": p.allowInsecure
            ] as [String: Any]
        }

        let flow = (p.security == "reality") ? "xtls-rprx-vision" : ""
        let config: [String: Any] = [
            "log": ["loglevel": "warning"],
            "inbounds": [[
                "tag": "socks-in", "listen": "127.0.0.1", "port": 10808,
                "protocol": "socks",
                "settings": ["udp": true, "auth": "noauth"],
                "sniffing": ["enabled": true, "destOverride": ["http", "tls"]]
            ]],
            "outbounds": [[
                "tag": "vless-out", "protocol": "vless",
                "settings": ["vnext": [[
                    "address": p.address, "port": p.port,
                    "users": [["id": p.uuid, "encryption": p.encryption, "flow": flow]]
                ]]],
                "streamSettings": stream
            ]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: config)
        return String(data: data, encoding: .utf8)!
    }
}
