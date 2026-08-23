import NetworkExtension
import VlessCore   // фреймворк из scripts/build-core.sh (gomobile bind)

/// Ключи счётчиков трафика в App Group (читает MainViewController).
let tunBytesInKey = "tun.bytes.in"
let tunBytesOutKey = "tun.bytes.out"

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var xrayStarted = false
    private var tunStarted = false

    private var bytesIn: Int64 = 0
    private var bytesOut: Int64 = 0
    // Все мутации счётчиков — через барьеры этой очереди.
    private let statsQueue = DispatchQueue(label: "vless.stats")
    private var statsTimer: DispatchSourceTimer?

    // MARK: - Старт туннеля

    override func startTunnel(options: [String: Any]?,
                              completionHandler: @escaping (Error?) -> Void) {
        guard let profile = ServerStore.shared.selected else {
            completionHandler(NSError(domain: "Vless", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Профиль не выбран — добавьте сервер в приложении"]))
            return
        }

        resetTraffic()
        writeStats()

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: profile.address)
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        // DNS внутри туннеля: запросы уйдут через lwIP -> SOCKS5 -> Xray (VLESS UDP).
        settings.dnsSettings = NEDNSSettings(servers: ["198.18.0.53"])
        settings.mtu = NSNumber(value: 1400)

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let strongSelf = self else { return }
            if let error = error { completionHandler(error); return }

            // 1. Ядро Xray: локальный SOCKS5 на 127.0.0.1:10808 с VLESS-outbound.
            do {
                try VlesscoreXrayStart(PacketTunnelProvider.xrayConfig(for: profile))
                strongSelf.xrayStarted = true
            } catch {
                completionHandler(error); return
            }

            // 2. TCP/IP-стек (lwIP) без файлового дескриптора TUN:
            //    исходящие пакеты уходят в packetFlow через FlowPacketSink,
            //    входящие подаются из readPackets в TunInput.
            do {
                weak var weakProvider = strongSelf
                let sink = FlowPacketSink(onBytes: { count in
                    weakProvider?.addOutgoingBytes(count)
                }, flow: strongSelf.packetFlow)
                try VlesscoreTunStart(sink, "127.0.0.1:10808", 1400, 60)
                strongSelf.tunStarted = true
            } catch {
                completionHandler(error); return
            }

            strongSelf.startPump()
            strongSelf.startStats()
            completionHandler(nil)
        }
    }

    /// Непрерывное чтение пакетов из TUN и подача их в стек.
    private func startPump() {
        packetFlow.readPackets { [weak self] packets in
            guard let strongSelf = self else { return }
            if strongSelf.tunStarted && !packets.isEmpty {
                var total = 0
                for packet in packets {
                    total += packet.count
                    VlesscoreTunInput(packet)
                }
                strongSelf.addIncomingBytes(Int64(total))
            }
            strongSelf.startPump()
        }
    }

    // MARK: - Остановка

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        statsTimer?.cancel()
        statsTimer = nil

        if tunStarted { try? VlesscoreTunStop() }
        tunStarted = false
        if xrayStarted { try? VlesscoreXrayStop() }
        xrayStarted = false

        writeStats()
        completionHandler()
    }

    // MARK: - Трафик

    func addIncomingBytes(_ count: Int64) {
        statsQueue.async(flags: .barrier) { self.bytesIn += count }
    }

    func addOutgoingBytes(_ count: Int64) {
        statsQueue.async(flags: .barrier) { self.bytesOut += count }
    }

    private func resetTraffic() {
        statsQueue.sync(flags: .barrier) {
            bytesIn = 0
            bytesOut = 0
        }
    }

    private func startStats() {
        let timer = DispatchSource.makeTimerSource(queue: statsQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.writeStats() }
        timer.resume()
        statsTimer = timer
    }

    /// Вызывается только из очереди statsQueue — прямой доступ к счётчикам безопасен.
    private func writeStats() {
        guard let defaults = UserDefaults(suiteName: ServerStore.groupName) else { return }
        defaults.set(Int(bytesIn), forKey: tunBytesInKey)
        defaults.set(Int(bytesOut), forKey: tunBytesOutKey)
    }

    // MARK: - Отладка

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: @escaping (Data?) -> Void) {
        var info = "stopped"
        if tunStarted { info = "running" }
        else if xrayStarted { info = "xray only" }
        completionHandler("state=\(info)".data(using: .utf8))
    }

    // MARK: - JSON-конфиг Xray под VLESS-профиль

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

        // Vision имеет смысл только для Reality поверх TCP
        let flow = (p.security == "reality" && p.network == "tcp") ? "xtls-rprx-vision" : ""

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

/// Мост «стек lwIP -> packetFlow». Реализует сгенерированный gomobile-протокол.
final class FlowPacketSink: NSObject, VlesscorePacketSink {

    private let flow: NEPacketTunnelFlow
    private let writeQueue = DispatchQueue(label: "vless.sink")
    private let onBytesHandler: (Int64) -> Void

    init(onBytes: @escaping (Int64) -> Void, flow: NEPacketTunnelFlow) {
        self.onBytesHandler = onBytes
        self.flow = flow
        super.init()
    }

    /// Каждый исходящий IP-пакет из стека уходит в TUN.
    /// Вызывается из Go-горутин — сериализуем запись.
    func writePacket(_ pkt: Data!) throws {
        guard let data = pkt, !data.isEmpty else { return }
        onBytesHandler(Int64(data.count))
        writeQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.flow.writePackets([data], withProtocols: [NSNumber(value: AF_INET)])
        }
    }
}
