import Foundation

/// Хранилище серверов в App Group (доступно и приложению, и extension).
///
/// ВАЖНО: файл подключён к обоим таргетам (см. project.yml) и не должен
/// импортировать UIKit.
final class ServerStore {

    static let shared = ServerStore()
    static let groupName = "group.vless.shared"

    private let defaults: UserDefaults?

    private init() {
        defaults = UserDefaults(suiteName: ServerStore.groupName)
    }

    private(set) var servers: [VlessProfile] {
        get {
            guard let data = defaults?.data(forKey: "servers"),
                  let list = try? JSONDecoder().decode([VlessProfile].self, from: data) else {
                return []
            }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults?.set(data, forKey: "servers")
            } else {
                defaults?.removeObject(forKey: "servers")
            }
        }
    }

    var selectedIndex: Int {
        get {
            if let v = defaults?.object(forKey: "selected") as? Int { return v }
            return -1
        }
        set { defaults?.set(newValue, forKey: "selected") }
    }

    var selected: VlessProfile? {
        let i = selectedIndex
        let list = servers
        guard i >= 0 && i < list.count else { return nil }
        return list[i]
    }

    func select(at index: Int) {
        guard servers.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// Добавляет профиль; false, если такой уже есть.
    @discardableResult
    func add(_ profile: VlessProfile) -> Bool {
        var list = servers
        if list.contains(profile) { return false }
        list.append(profile)
        servers = list
        if selectedIndex < 0 { selectedIndex = list.count - 1 }
        return true
    }

    func remove(at index: Int) {
        var list = servers
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        servers = list

        var sel = selectedIndex
        if index == sel {
            sel = -1
        } else if index < sel {
            sel -= 1
        }
        if sel >= list.count { sel = list.isEmpty ? -1 : list.count - 1 }
        selectedIndex = sel
    }

    // MARK: - Трафик (пишет extension, читает приложение)

    var bytesIn: Int64 { Int64(defaults?.integer(forKey: "tun.bytes.in") ?? 0) }
    var bytesOut: Int64 { Int64(defaults?.integer(forKey: "tun.bytes.out") ?? 0) }

    func resetTraffic() {
        defaults?.set(0, forKey: "tun.bytes.in")
        defaults?.set(0, forKey: "tun.bytes.out")
    }
}
