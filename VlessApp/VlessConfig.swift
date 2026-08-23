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

private extension URL {
    var queryParameters: [String: String] {
        var result: [String: String] = [:]
        guard let query = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?
            .map({ ($0.name, $0.value ?? "") }) else { return result }
        // iOS 12: Dictionary(uniqueKeysWithValues:) падает на дублях
        for (k, v) in query { result[k] = v }
        return result
    }
}
