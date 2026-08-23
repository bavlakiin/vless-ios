import UIKit

/// Ручное добавление сервера.
class AddServerViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private var nameField: UITextField!
    private var hostField: UITextField!
    private var portField: UITextField!
    private var uuidField: UITextField!
    private var sniField: UITextField!
    private var pbkField: UITextField!
    private var sidField: UITextField!
    private var securityControl: UISegmentedControl!
    private var insecureSwitch: UISwitch!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = colorBg
        title = "Новый сервер"

        navigationItem.leftBarButtonItem =
            UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem =
            UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))

        setupForm()
    }

    private func labeledField(_ placeholder: String, keyboardType: UIKeyboardType = .default) -> UITextField {
        let container = UIView()
        let label = UILabel()
        label.text = placeholder
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = UIColor(white: 0.55, alpha: 1)

        let field = UITextField()
        field.borderStyle = .roundedRect
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.keyboardType = keyboardType
        field.font = UIFont.systemFont(ofSize: 14)
        field.backgroundColor = UIColor(white: 1, alpha: 0.07)
        field.textColor = colorText
        field.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        container.addSubview(field)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),

            field.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            field.heightAnchor.constraint(equalToConstant: 36)
        ])
        field.accessibilityLabel = placeholder
        stackView.addArrangedSubview(container)
        return field
    }

    private func setupForm() {
        scrollView.keyboardDismissMode = .onDrag
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
        ])

        nameField = labeledField("Название")
        hostField = labeledField("Адрес (домен или IP)", keyboardType: .URL)
        portField = labeledField("Порт", keyboardType: .numberPad)
        uuidField = labeledField("UUID")
        sniField = labeledField("SNI (для TLS/Reality)")
        pbkField = labeledField("Reality public key (pbk)")
        sidField = labeledField("Reality short id (sid)")

        // Security
        let secLabel = UILabel()
        secLabel.text = "Безопасность"
        secLabel.font = UIFont.systemFont(ofSize: 12)
        secLabel.textColor = UIColor(white: 0.55, alpha: 1)
        securityControl = UISegmentedControl(items: ["none", "tls", "reality"])
        securityControl.selectedSegmentIndex = 1
        securityControl.tintColor = colorAccent
        stackView.addArrangedSubview(secLabel)
        stackView.addArrangedSubview(securityControl)

        // allowInsecure
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let rowTitle = UILabel()
        rowTitle.text = "Разрешить самоподписанный TLS"
        rowTitle.font = UIFont.systemFont(ofSize: 13)
        rowTitle.textColor = colorText
        rowTitle.translatesAutoresizingMaskIntoConstraints = false
        insecureSwitch = UISwitch()
        insecureSwitch.tintColor = colorAccent
        insecureSwitch.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(rowTitle)
        row.addSubview(insecureSwitch)
        NSLayoutConstraint.activate([
            rowTitle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            rowTitle.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 4),
            insecureSwitch.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            insecureSwitch.trailingAnchor.constraint(equalTo: row.trailingAnchor)
        ])
        stackView.addArrangedSubview(row)
    }

    @objc private func cancel() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func save() {
        let host = (hostField.text ?? "").trimmingCharacters(in: .whitespaces)
        let uuidRaw = (uuidField.text ?? "").trimmingCharacters(in: .whitespaces)
        let uuid = uuidRaw.replacingOccurrences(of: "-", with: "").lowercased()
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        let port = Int(portField.text ?? "") ?? 443

        guard !host.isEmpty else {
            showAlert("Укажите адрес сервера"); return
        }
        guard uuid.count == 32,
              uuid.rangeOfCharacter(from: hexChars.inverted) == nil else {
            showAlert("UUID должен состоять из 32 hex-символов"); return
        }
        guard port > 0 && port < 65536 else {
            showAlert("Некорректный порт"); return
        }
        if securityControl.selectedSegmentIndex == 2 && (pbkField.text ?? "").isEmpty {
            showAlert("Для Reality укажите public key"); return
        }

        let securities = ["none", "tls", "reality"]
        let profile = VlessProfile(
            name: (nameField.text ?? "").isEmpty ? host : nameField.text!,
            uuid: uuid,
            address: host,
            port: port,
            encryption: "none",
            network: "tcp",
            security: securities[securityControl.selectedSegmentIndex],
            sni: emptyToNil(sniField.text),
            fingerprint: nil,
            publicKey: emptyToNil(pbkField.text),
            shortId: emptyToNil(sidField.text),
            path: nil,
            allowInsecure: insecureSwitch.isOn
        )
        ServerStore.shared.add(profile)
        NotificationCenter.default.post(name: Notification.Name("serversChanged"), object: nil)
        dismiss(animated: true, completion: nil)
    }

    private func emptyToNil(_ text: String?) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true, completion: nil)
    }
}
