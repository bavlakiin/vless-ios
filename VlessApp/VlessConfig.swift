import Foundation

struct VlessProfile: Codable {
    var name: String
    var uuid: String
    var address: String
    var port: Int
    var encryption: String        // обычно "none"
    var network: String           // tcp / ws / grpc ...
    var security: String          // none / tls / reality
    var sni: String?
    var fingerprint: String?
    var publicKey: String?        // reality pbk
    var shortId: String?          // reality sid
    var path: String?             // ws path / grpc serviceName
    var allowInsecure: Bool = false

    var hostLabel: String { return "\(address):\(port)" }
}

enum VlessParser {

    static func parse(_ uri: String) -> VlessProfile? {
        guard uri.lowercased().hasPrefix("vless://"),
              let url = URL(string: uri) else { return nil }

        let uuid = url.user ?? ""
        let host = url.host ?? ""
        let port = url.port ?? 443
        guard !uuid.isEmpty, !host.isEmpty else { return nil }

        var profile = VlessProfile(
            name: url.queryParameters["name"] ?? (url.fragment ?? host),
            uuid: uuid, address: host, port: port,
            encryption: url.queryParameters["encryption"] ?? "none",
            network: url.queryParameters["type"] ?? "tcp",
            security: url.queryParameters["security"] ?? "none"
        )
        profile.sni = url.queryParameters["sni"] ?? url.queryParameters["peer"]
        profile.fingerprint = url.queryParameters["fp"]
        profile.publicKey = url.queryParameters["pbk"]
        profile.shortId = url.queryParameters["sid"]
        profile.path = url.queryParameters["path"] ?? url.queryParameters["serviceName"]
        profile.allowInsecure = url.queryParameters["allowInsecure"] == "1"
        return profile
    }
}

extension VlessProfile {

    /// Обратная сборка ссылки vless:// (для «Поделиться»).
    var url: String {
        var components = URLComponents()
        components.scheme = "vless"
        components.user = uuid
        components.host = address
        components.port = port

        var items: [(String, String)] = [("type", network), ("security", security)]
        if let sni = sni { items.append(("sni", sni)) }
        if let fp = fingerprint { items.append(("fp", fp)) }
        if security == "reality" {
            if let pbk = publicKey { items.append(("pbk", pbk)) }
            if let sid = shortId { items.append(("sid", sid)) }
        } else if security == "tls" {
            if let path = path { items.append(("path", path)) }
        }
        if allowInsecure { items.append(("allowInsecure", "1")) }
        components.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        components.fragment = name
        return components.string ?? ""
    }

    /// Разбор тела подписки: список ссылок построчно либо base64.
    static func parseSubscription(_ body: String) -> [VlessProfile] {
        var text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("vless://") {
            var base64 = text
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            while base64.count % 4 != 0 { base64 += "=" }
            if let data = Data(base64Encoded: base64),
               let decoded = String(data: data, encoding: .utf8) {
                text = decoded
            }
        }

        var result: [VlessProfile] = []
        for line in text.components(separatedBy: CharacterSet.newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("vless://"),
                  let profile = VlessParser.parse(trimmed) else { continue }
            result.append(profile)
        }
        return result
    }
}

private extension URL {
    var queryParameters: [String: String] {
        var result: [String: String] = [:]
        guard let query = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?
            .map({ ($0.name, $0.value ?? "") }) else { return result }
        // iOS 12: Dictionary(uniqueKeysWithValues:) падает на дублях
        for (key, value) in query { result[key] = value }
        return result
    }
}
