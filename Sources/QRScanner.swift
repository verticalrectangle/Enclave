//  QRScanner.swift
//  Camera scanner for the QR that `omp /collab` prints. Reads the QR's web link
//  (`https://my.omp.sh/#<roomId>.<key>`) and hands the string back; the Pair flow
//  validates and joins. Camera only — the simulator has none, so this is a device
//  feature.

import SwiftUI
import AVFoundation

struct QRScanner: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onFound = onFound
        return vc
    }
    func updateUIViewController(_ vc: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var handled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer

        Task.detached(priority: .userInitiated) { [session] in session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.layer.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !handled,
              let code = objects.first as? AVMetadataMachineReadableCodeObject,
              let text = code.stringValue
        else { return }
        handled = true
        session.stopRunning()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onFound?(text)
    }
}

/// Full-screen scanner with a viewfinder overlay, presented from Pair.
struct ScannerScreen: View {
    @EnvironmentObject var theme: ThemeStore
    var onFound: (String) -> Void
    var onCancel: () -> Void
    private var t: Theme { theme.t }

    var body: some View {
        ZStack {
            QRScanner(onFound: onFound).ignoresSafeArea()
            // dim + cut-out viewfinder
            GeometryReader { g in
                let side = min(g.size.width, g.size.height) * 0.66
                ZStack {
                    Color.black.opacity(0.45)
                        .mask {
                            Rectangle().overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .frame(width: side, height: side).blendMode(.destinationOut)
                            }.compositingGroup()
                        }
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(t.accent, lineWidth: 2)
                        .frame(width: side, height: side)
                }
            }
            .ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white).padding(12).background(.black.opacity(0.4), in: Circle())
                    }.padding(16)
                }
                Spacer()
                Text("Scan the QR from  omp /collab")
                    .font(.term(16)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
    }
}
