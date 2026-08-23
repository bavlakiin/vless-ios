import UIKit

/// Загрузка списка серверов по ссылке-подписке.
class SubscriptionViewController: UIViewController {

    private let urlField = UITextField()
    private let spinner = UIActivityIndicatorView(style: .whiteLarge)
    private let hintLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = colorBg
        title = "Подписка"
        setupUI()
    }

    private func setupUI() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        urlField.placeholder = "https://…/sub"
        urlField.borderStyle = .roundedRect
        urlField.keyboardType = .URL
        urlField.autocorrectionType = .no
        urlField.autocapitalizationType = .none
        urlField.font = UIFont.systemFont(ofSize: 13)
        urlField.backgroundColor = UIColor(white: 1, alpha: 0.07)
        urlField.textColor = colorText

        let button = UIButton(type: .system)
        button.setTitle("Загрузить и добавить", for: .normal)
        button.setTitleColor(colorBg, for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 15)
        button.backgroundColor = colorAccent
        button.layer.cornerRadius = 20
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.addTarget(self, action: #selector(fetchSubscription), for: .touchUpInside)

        spinner.hidesWhenStopped = true

        hintLabel.numberOfLines = 0
        hintLabel.font = UIFont.systemFont(ofSize: 12)
        hintLabel.textColor = UIColor(white: 0.5, alpha: 1)
        hintLabel.text = "Подписка — обычный URL со списком ссылок vless://\nв текстовом виде или в base64."

        stack.addArrangedSubview(urlField)
        stack.addArrangedSubview(button)
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(hintLabel)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    @objc private func fetchSubscription() {
        let raw = (urlField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, let url = URL(string: raw), url.scheme != nil else {
            alert("Введите корректный URL"); return
        }

        spinner.startAnimating()
        var request = URLRequest(url: url)
        request.timeoutInterval = 25

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.spinner.stopAnimating()
                if error != nil || data == nil {
                    strongSelf.alert("Не удалось загрузить подписку")
                    return
                }
                let body = String(data: data!, encoding: .utf8) ?? ""
                let profiles = VlessProfile.parseSubscription(body)
                guard !profiles.isEmpty else {
                    strongSelf.alert("В подписке не найдено ссылок vless://")
                    return
                }
                var added = 0
                for profile in profiles where ServerStore.shared.add(profile) {
                    added += 1
                }
                NotificationCenter.default.post(name: Notification.Name("serversChanged"), object: nil)
                strongSelf.alert("Добавлено серверов: \(added)" +
                    (added < profiles.count ? " (дубликатов пропущено: \(profiles.count - added))" : ""))
            }
        }.resume()
    }

    private func alert(_ message: String) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true, completion: nil)
    }
}
