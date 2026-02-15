//
//  PhotoCameraView.swift
//  GrandparentMemories
//
//  Custom camera implementation using AVFoundation
//  Avoids UIImagePickerController orientation bugs
//

import SwiftUI
import AVFoundation
import Combine
import Photos

struct PhotoCameraView: View {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = PhotoCameraManager()

    var body: some View {
        ZStack {
            // Camera preview
            if let previewLayer = camera.previewLayer {
                CameraPreviewView(previewLayer: previewLayer)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)  // Let touches pass through to buttons
            } else {
                Color.black
                    .ignoresSafeArea()
            }

            // Camera controls overlay
            VStack {
                // Top bar with close button
                HStack {
                    Button {
                        print("📸 Close button tapped")
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding()
                            .background(Circle().fill(.black.opacity(0.5)))
                    }
                    .padding()

                    Spacer()

                    // Camera flip button
                    Button {
                        print("📸 Flip camera button tapped")
                        camera.flipCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding()
                            .background(Circle().fill(.black.opacity(0.5)))
                    }
                    .padding()
                }

                Spacer()

                // Bottom bar with capture button
                HStack {
                    Spacer()

                    Button {
                        print("📸 Capture button tapped")
                        camera.capturePhoto { image in
                            if let image = image {
                                print("📸 Photo captured successfully")
                                onCapture(image)
                                dismiss()
                            } else {
                                print("📸 ❌ Photo capture failed")
                            }
                        }
                    } label: {
                        Circle()
                            .strokeBorder(.white, lineWidth: 4)
                            .background(Circle().fill(.white.opacity(0.3)))
                            .frame(width: 70, height: 70)
                    }
                    .disabled(camera.isCapturing)

                    Spacer()
                }
                .padding(.bottom, 40)
            }

            // Flash overlay for capture feedback
            if camera.isCapturing {
                Color.white
                    .ignoresSafeArea()
                    .opacity(0.7)
                    .animation(.easeInOut(duration: 0.2), value: camera.isCapturing)
            }
        }
        .onAppear {
            Task {
                await camera.requestPermissionsAndSetup()
            }
        }
        .onDisappear {
            camera.stopSession()
        }
    }
}

@MainActor
class PhotoCameraManager: NSObject, ObservableObject {
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var isCapturing = false

    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var currentCamera: AVCaptureDevice.Position = .back
    private var photoCaptureCompletion: ((UIImage?) -> Void)?
    private var orientationObserver: NSObjectProtocol?

    deinit {
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func requestPermissionsAndSetup() async {
        print("📸 Requesting camera permissions...")
        
        // Request camera permission
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool

        switch status {
        case .authorized:
            granted = true
            print("📸 Camera already authorized")
        case .notDetermined:
            print("📸 Requesting camera access...")
            granted = await AVCaptureDevice.requestAccess(for: .video)
            print("📸 Camera access granted: \(granted)")
        default:
            granted = false
            print("📸 Camera access denied or restricted")
        }

        guard granted else {
            print("📸 ❌ Camera permission denied")
            return
        }

        await setupCaptureSession()
    }

    private func setupCaptureSession() async {
        print("📸 Setting up capture session...")
        
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        // Add video input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCamera),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("📸 ❌ Failed to create camera input")
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
            print("📸 ✅ Added camera input")
        } else {
            print("📸 ❌ Cannot add camera input")
            return
        }

        // Add photo output
        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            photoOutput = output
            print("📸 ✅ Added photo output")
        } else {
            print("📸 ❌ Cannot add photo output")
            return
        }

        // Create preview layer
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill

        // Handle orientation properly
        if let connection = preview.connection {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = currentVideoOrientation()
            }
        }

        // Update on main thread
        captureSession = session
        previewLayer = preview
        print("📸 ✅ Preview layer created")

        // Add orientation observer to update preview layer on rotation
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePreviewOrientation()
        }

        // Start session on background thread
        Task.detached {
            print("📸 Starting capture session...")
            session.startRunning()
            print("📸 ✅ Capture session running")
        }
    }

    private func updatePreviewOrientation() {
        guard let connection = previewLayer?.connection,
              connection.isVideoOrientationSupported else {
            print("📸 ❌ Cannot update orientation - connection not available")
            return
        }

        let newOrientation = currentVideoOrientation()
        print("📸 Updating preview orientation to: \(newOrientation.rawValue)")
        connection.videoOrientation = newOrientation
    }

    func flipCamera() {
        guard let session = captureSession else { return }

        session.beginConfiguration()

        // Remove existing inputs
        session.inputs.forEach { session.removeInput($0) }

        // Switch camera position
        currentCamera = currentCamera == .back ? .front : .back

        // Add new input with switched camera
        if let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCamera),
           let newInput = try? AVCaptureDeviceInput(device: newCamera),
           session.canAddInput(newInput) {
            session.addInput(newInput)
        }

        session.commitConfiguration()
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard let photoOutput = photoOutput else {
            completion(nil)
            return
        }

        photoCaptureCompletion = completion
        isCapturing = true

        let settings = AVCapturePhotoSettings()

        // Set highest quality supported by this device
        settings.photoQualityPrioritization = photoOutput.maxPhotoQualityPrioritization

        // Set the correct orientation for the captured photo
        if let photoOutputConnection = photoOutput.connection(with: .video) {
            photoOutputConnection.videoOrientation = currentVideoOrientation()
            print("📸 Capturing with orientation: \(photoOutputConnection.videoOrientation.rawValue)")
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func stopSession() {
        captureSession?.stopRunning()
    }

    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        let interfaceOrientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation ?? .portrait

        switch interfaceOrientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portrait
        }
    }
}

// MARK: - Photo Capture Delegate
extension PhotoCameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Task { @MainActor in
            isCapturing = false

            guard error == nil,
                  let imageData = photo.fileDataRepresentation(),
                  let image = UIImage(data: imageData) else {
                photoCaptureCompletion?(nil)
                return
            }

            savePhotoToLibrary(image)
            // Image already has correct orientation from capture settings
            photoCaptureCompletion?(image)
        }
    }

    private func savePhotoToLibrary(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: nil)
        }
    }
}

// MARK: - UIImage Extension for Orientation Fix
extension UIImage {
    func fixOrientation() -> UIImage {
        if imageOrientation == .up {
            return self
        }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage ?? self
    }
}
