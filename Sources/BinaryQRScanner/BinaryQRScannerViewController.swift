import AVFoundation
import SwiftUI

extension BinaryQRScanner.View {
    public class Controller: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

        // MARK: - Properties

        var parentView: BinaryQRScanner.View!
        private let decoder = BinaryQRScanner.BinaryDecoder()

        private let session = AVCaptureSession()
        private var previewLayer = AVCaptureVideoPreviewLayer()
        private var isScanning = true

        //MARK: - Lifecycle

        public init(
            parentView: BinaryQRScanner.View
        ) {
            self.parentView = parentView
            super.init(nibName: nil, bundle: nil)
        }

        required init?(
            coder: NSCoder
        ) {
            super.init(coder: coder)
        }

        override public func viewDidLoad() {
            super.viewDidLoad()
            handleCameraPermission()
        }

        override public func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            finishScanning()
        }

        override public func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            
            coordinator.animate(alongsideTransition: { _ in
                self.updatePreviewLayerLayout()
            }, completion: nil)
        }

        override public func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            updatePreviewLayerLayout()
        }

        //MARK: - Private methods

        private func handleCameraPermission() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .restricted:
                    break
                case .denied:
                    fail(with: .permissionDenied)
                case .notDetermined:
                    requestCameraAccess {
                        self.setupCaptureDevice()
                        DispatchQueue.main.async {
                            self.setupSession()
                        }
                    }
                case .authorized:
                    setupCaptureDevice()
                    setupSession()
                default:
                    break
            }
        }

        private func requestCameraAccess(completion: (() -> Void)?) {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] status in
                guard status else {
                    self?.fail(with: .permissionDenied)
                    return
                }

                completion?()
            }
        }

        private func setupSession() {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            
            updatePreviewLayerLayout()
            setupSubview()

            DispatchQueue.global(qos: .userInteractive).async {
                self.session.startRunning()
            }
        }

        private func updatePreviewLayerLayout() {
            guard previewLayer.superlayer != nil else { return }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Update frame to match current view bounds
                self.previewLayer.frame = self.view.bounds
                
                // Update video orientation to match current interface orientation
                self.updateVideoOrientation()
            }
        }

        private func updateVideoOrientation() {
            guard let connection = previewLayer.connection,
                  connection.isVideoOrientationSupported else { return }
            
            let videoOrientation: AVCaptureVideoOrientation
            
            // Get current interface orientation
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                switch windowScene.interfaceOrientation {
                case .portrait:
                    videoOrientation = .portrait
                case .portraitUpsideDown:
                    videoOrientation = .portraitUpsideDown
                case .landscapeLeft:
                    videoOrientation = .landscapeLeft
                case .landscapeRight:
                    videoOrientation = .landscapeRight
                case .unknown:
                    videoOrientation = .portrait
                @unknown default:
                    videoOrientation = .portrait
                }
            } else {
                // Fallback to device orientation if interface orientation is unavailable
                switch UIDevice.current.orientation {
                case .portrait:
                    videoOrientation = .portrait
                case .portraitUpsideDown:
                    videoOrientation = .portraitUpsideDown
                case .landscapeLeft:
                    videoOrientation = .landscapeLeft
                case .landscapeRight:
                    videoOrientation = .landscapeRight
                default:
                    videoOrientation = .portrait
                }
            }
            
            connection.videoOrientation = videoOrientation
        }

        private func setupCaptureDevice() {
            guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                              for: .video,
                                                              position: parentView.isFrontCamera ? .front : .back) else {
                print("Error: Unable to find the camera of the device")
                return
            }

            let input: AVCaptureInput

            do {
                input = try AVCaptureDeviceInput(device: captureDevice)
            } catch {
                fail(with: .avCaptureError())
                return
            }

            guard session.canAddInput(input) else {
                fail(with: .avCaptureError())
                return
            }

            session.addInput(input)

            let output = AVCaptureMetadataOutput()

            guard session.canAddOutput(output) else {
                fail(with: .avCaptureError())
                return
            }

            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

        }

        private func setupSubview() {
            guard let (subview, position, indent) = parentView.subview else {
                return
            }

            self.view.addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
            switch position {
            case .center:
                subview.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
                subview.centerYAnchor.constraint(equalTo: self.view.centerYAnchor).isActive = true
            case .top:
                subview.topAnchor.constraint(equalTo: self.view.topAnchor, constant: indent).isActive = true
                subview.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
            case .bottom:
                subview.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: indent).isActive = true
                subview.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
            case .leading:
                subview.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: indent).isActive = true
                subview.centerYAnchor.constraint(equalTo: self.view.centerYAnchor).isActive = true
            case .trailing:
                subview.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: indent).isActive = true
                subview.centerYAnchor.constraint(equalTo: self.view.centerYAnchor).isActive = true
            }
        }

        private func finishScanning() {
            session.stopRunning()
            previewLayer.removeFromSuperlayer()
        }

        private func found(_ scanResult: BinaryQRScanner.ScanResult) {
            parentView.completion(
                .success(scanResult),
                {
                    self.parentView.dismiss()
                },
                {
                    self.isScanning = true
                }
            )
        }

        private func fail(with error: BinaryQRScanner.ScanError) {
            parentView.completion(
                .failure(error),
                {
                    self.parentView.dismiss()
                },
                {
                    self.isScanning = true
                }
            )
        }

        //MARK: - Public methods

        public func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject
            else {
                return
            }

            guard let descriptor = metadataObject.descriptor as? CIQRCodeDescriptor else {
                return
            }

            if metadataObject.type != .qr {
                return
            }

            if !isScanning {
                return
            }
            isScanning = false

            switch parentView.mode {
                case .text:
                    guard let text = metadataObject.stringValue else {
                        fail(with: .incorrectEncodingMode)
                        return
                    }

                    found(.text(text))
                case .binary:
                    guard
                        let data = decoder.decodeQRErrorCorrectedBytes(
                            descriptor.errorCorrectedPayload,
                            symbolVersion: descriptor.symbolVersion
                        )
                    else {
                        fail(with: .incorrectEncodingMode)
                        return
                    }

                    found(.binary(data))
            }
        }
    }
}
