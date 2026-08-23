import UIKit
import NetworkExtension

let colorBg = UIColor(red: 13/255, green: 16/255, blue: 32/255, alpha: 1)      // #0D1020
let colorAccent = UIColor(red: 255/255, green: 158/255, blue: 44/255, alpha: 1) // #FF9E2C
let colorText = UIColor(white: 0.92, alpha: 1)

/// Главный экран: статус, кнопка подключения, список серверов,
/// добавление по QR / ссылке / подписке / вручную.
class MainViewController: UIViewController {

    private let statusLabel = UILabel()
    private let trafficLabel = UILabel()
    private let connectButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    private var servers: [VlessProfile] = []
    private var refreshTimer: Timer?

    // MARK: - Жизненный цикл

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = colorBg
        title = "VLESS"
        setupHeader()
        setupTable()
        setupBarButtons()

        NotificationCenter.default.addObserver(
            self, selector: #selector(vpnStatusChanged),
            name: .NEVPNStatusDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(serversChanged),
            name: Notification.Name("serversChanged"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(externalImport(_:)),
            name: Notification.Name("importLink"), object: nil)

        VPNManager.shared.prepare { _ in }
        updateUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadServers()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTraffic()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc private func vpnStatusChanged() {
        DispatchQueue.main.async { [weak self] in self?.updateUI() }
    }

    @objc private func serversChanged() {
        DispatchQueue.main.async { [weak self] in self?.reloadServers() }
    }

    @objc private func externalImport(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            if let link = note.object as? String {
                self?.importLink(link)
            }
        }
    }

    // MARK: - Интерфейс

    private func setupHeader() {
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.textColor = colorText
        statusLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)

        trafficLabel.textAlignment = .center
        trafficLabel.textColor = UIColor(white: 0.65, alpha: 1)
        trafficLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        connectButton.setTitle("Connect", for: .normal)
        connectButton.setTitleColor(colorBg, for: .normal)
        connectButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        connectButton.backgroundColor = colorAccent
        connectButton.layer.cornerRadius = 34
        connectButton.translatesAutoresizingMaskIntoConstraints = false
        connectButton.addTarget(self, action: #selector(toggleVPN), for: .touchUpInside)

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = .clear
        header.addSubview(connectButton)
        header.addSubview(statusLabel)
        header.addSubview(trafficLabel)

        view.addSubview(header)
        view.addSubview(tableView)
        tableView.backgroundColor = .clear
        tableView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 170),

            connectButton.topAnchor.constraint(equalTo: header.topAnchor, constant: 10),
            connectButton.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            connectButton.widthAnchor.constraint(equalToConstant: 68),
            connectButton.heightAnchor.constraint(equalToConstant: 68),

            statusLabel.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),

            trafficLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),
            trafficLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            trafficLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: header.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorColor = UIColor(white: 1, alpha: 0.08)

        emptyLabel.text = "Нет серверов\nДобавьте по QR, ссылке или подписке"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = UIColor(white: 0.45, alpha: 1)
        emptyLabel.frame = CGRect(x: 0, y: 40, width: UIScreen.main.bounds.width, height: 80)
        tableView.tableFooterView = emptyLabel

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(longPress)
    }

    private func setupBarButtons() {
        let qr = UIBarButtonItem(title: "QR", style: .plain, target: self, action: #selector(openScanner))
        let sub = UIBarButtonItem(title: "Подписка", style: .plain, target: self, action: #selector(openSubscription))
        let add = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addServerTapped))
        navigationItem.rightBarButtonItems = [add, sub, qr]
    }

    // MARK: - Данные

    private func reloadServers() {
        servers = ServerStore.shared.servers
        emptyLabel.isHidden = !servers.isEmpty
        tableView.reloadData()
        updateUI()
    }

    private func updateUI() {
        let state = VPNManager.shared.status
        switch state {
        case .connected:
            let serverName = ServerStore.shared.selected?.name ?? ""
            statusLabel.text = "Подключено · \(serverName)"
            connectButton.setTitle("Stop", for: .normal)
            connectButton.backgroundColor = UIColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 1)
        case .connecting:
            statusLabel.text = "Подключение…"
            connectButton.setTitle("Stop", for: .normal)
            connectButton.backgroundColor = UIColor(white: 0.35, alpha: 1)
        case .off:
            statusLabel.text = "Отключено"
            connectButton.setTitle("Connect", for: .normal)
            connectButton.backgroundColor = colorAccent
        }
        tableView.reloadData()
    }

    private func updateTraffic() {
        let fmt: (Int64) -> String = { bytes in
            switch bytes {
            case ..<1024: return "\(bytes) Б"
            case ..<(1024 * 1024): return String(format: "%.1f КБ", Double(bytes) / 1024)
            default: return String(format: "%.1f МБ", Double(bytes) / (1024 * 1024))
            }
        }
        trafficLabel.text = "↓ \(fmt(ServerStore.shared.bytesIn))   ↑ \(fmt(ServerStore.shared.bytesOut))"
    }

    // MARK: - Действия

    @objc private func toggleVPN() {
        if VPNManager.shared.status != .off {
            VPNManager.shared.disconnect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.updateUI() }
            return
        }
        guard ServerStore.shared.selected != nil else {
            showAlert(title: "Нет сервера", message: "Сначала добавьте и выберите сервер")
            return
        }
        connectButton.isEnabled = false
        VPNManager.shared.connect { [weak self] error in
            DispatchQueue.main.async {
                self?.connectButton.isEnabled = true
                if let error = error {
                    self?.showAlert(title: "Ошибка", message: error.localizedDescription)
                }
                self?.updateUI()
            }
        }
    }

    @objc private func openScanner() {
        let vc = QRScannerViewController()
        vc.onResult = { [weak self] text in
            self?.importLink(text)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func openSubscription() {
        navigationController?.pushViewController(SubscriptionViewController(), animated: true)
    }

    @objc private func addServerTapped() {
        let sheet = UIAlertController(title: "Добавить сервер", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Вставить ссылку из буфера", style: .default) { [weak self] _ in
            if let text = UIPasteboard.general.string {
                self?.importLink(text)
            } else {
                self?.showAlert(title: "Буфер пуст", message: nil)
            }
        })
        sheet.addAction(UIAlertAction(title: "Вручную", style: .default) { [weak self] _ in
            let nav = UINavigationController(rootViewController: AddServerViewController())
            self?.present(nav, animated: true, completion: nil)
        })
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        present(sheet, animated: true, completion: nil)
    }

    private func importLink(_ text: String) {
        let candidates = text.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        var imported = 0
        for candidate in candidates where candidate.lowercased().hasPrefix("vless://") {
            if let profile = VlessParser.parse(candidate), ServerStore.shared.add(profile) {
                imported += 1
            }
        }
        reloadServers()
        if imported > 0 {
            showAlert(title: "Готово", message: "Импортировано серверов: \(imported)")
        } else {
            showAlert(title: "Некорректная ссылка", message: "Ожидается vless://…")
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point),
              servers.indices.contains(indexPath.row) else { return }
        let link = servers[indexPath.row].url
        let activity = UIActivityViewController(activityItems: [link], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        present(activity, animated: true, completion: nil)
    }

    private func confirmReconnect(completion: @escaping () -> Void) {
        let alert = UIAlertController(title: "Переподключить?",
                                      message: "Выбран другой сервер",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Да", style: .default) { _ in completion() })
        alert.addAction(UIAlertAction(title: "Позже", style: .cancel))
        present(alert, animated: true, completion: nil)
    }

    private func showAlert(title: String, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true, completion: nil)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension MainViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return servers.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "server")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "server")
        let profile = servers[indexPath.row]

        cell.backgroundColor = .clear
        cell.textLabel?.text = profile.name
        cell.textLabel?.textColor = colorText
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)

        var detail = profile.hostLabel
        if profile.security != "none" { detail += "  ·  \(profile.security.uppercased())" }
        if profile.network != "tcp" { detail += "  ·  \(profile.network)" }
        cell.detailTextLabel?.text = detail
        cell.detailTextLabel?.textColor = UIColor(white: 0.55, alpha: 1)
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)

        cell.accessoryType = indexPath.row == ServerStore.shared.selectedIndex ? .checkmark : .none
        cell.tintColor = colorAccent
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let wasSelected = ServerStore.shared.selectedIndex == indexPath.row
        ServerStore.shared.select(at: indexPath.row)

        if VPNManager.shared.status != .off && !wasSelected {
            confirmReconnect { [weak self] in
                VPNManager.shared.reconnect { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self?.showAlert(title: "Ошибка", message: error.localizedDescription)
                        }
                        self?.updateUI()
                    }
                }
            }
        }
        updateUI()
    }

    func tableView(_ tableView: UITableView,
                   commit editingStyle: UITableViewCell.EditingStyle,
                   forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        ServerStore.shared.remove(at: indexPath.row)
        reloadServers()
    }
}
