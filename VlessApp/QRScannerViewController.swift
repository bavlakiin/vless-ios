import UIKit
import AVFoundation

/// Сканер QR-кодов (ссылки vless://).
class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onResult: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Сканировать QR"

        navigationItem.leftBarButtonItem =
            UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.setupCamera() } else { self?.showDenied() }
                }
            }
        default:
            showDenied()
        }
    }

    @objc private func close() {
        session.stopRunning()
        navigationController?.popViewController(animated: true)
    }

    private func showDenied() {
        let label = UILabel()
        label.text = "Нет доступа к камере.\nРазрешите его в Настройках."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupCamera() {
        guard !isConfigured,
              let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showDenied()
            return
        }
        isConfigured = true
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        if output.availableMetadataObjectTypes.contains(.qr) {
            output.metadataObjectTypes = [.qr]
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.layer.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        // Рамка прицела
        let box = UIView()
        box.layer.borderColor = colorAccent.cgColor
        box.layer.borderWidth = 2
        box.layer.cornerRadius = 12
        box.translatesAutoresizingMaskIntoConstraints = false
        box.isUserInteractionEnabled = false
        view.addSubview(box)
        NSLayoutConstraint.activate([
            box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            box.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            box.widthAnchor.constraint(equalToConstant: 240),
            box.heightAnchor.constraint(equalToConstant: 240)
        ])

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }
        session.stopRunning()
        onResult?(value)
        navigationController?.popViewController(animated: true)
    }
}
