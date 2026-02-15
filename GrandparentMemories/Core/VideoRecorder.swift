//
//  VideoRecorder.swift
//  GrandparentMemories
//
//  Created by Tony Smith on 05/02/2026.
//

import Foundation
import AVFoundation
import SwiftUI
import Photos

@Observable
class VideoRecorder: NSObject {
    var isRecording = false
    var isPlaying = false
    var recordingDuration: TimeInterval = 0
    var videoURL: URL?
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var recordingTimer: Timer?
    private var currentVideoInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    
    override init() {
        super.init()
    }

    func setPreferredPosition(_ position: AVCaptureDevice.Position) {
        guard !isRecording else { return }
        currentPosition = position
    }
    
    func requestPermissions(completion: @escaping (Bool) -> Void) async {
        print("🎥 VideoRecorder: Requesting permissions")
        
        // Request camera permission
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let cameraGranted: Bool
        
        switch cameraStatus {
        case .authorized:
            cameraGranted = true
        case .notDetermined:
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            cameraGranted = false
        }
        
        // Request microphone permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let micGranted: Bool
        
        switch micStatus {
        case .authorized:
            micGranted = true
        case .notDetermined:
            micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            micGranted = false
        }
        
        await MainActor.run {
            completion(cameraGranted && micGranted)
        }
    }
    
    func setupCaptureSession() async -> AVCaptureVideoPreviewLayer? {
        print("🎥 VideoRecorder: Setting up capture session")
        
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        // Add video input (default to back camera)
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            print("🎥 VideoRecorder: ❌ Failed to add video input")
            return nil
        }
        session.addInput(videoInput)
        currentVideoInput = videoInput
        currentPosition = videoDevice.position
        
        // Add audio input
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
              session.canAddInput(audioInput) else {
            print("🎥 VideoRecorder: ❌ Failed to add audio input")
            return nil
        }
        session.addInput(audioInput)
        
        // Add movie file output
        let output = AVCaptureMovieFileOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            videoOutput = output
        }
        
        captureSession = session
        
        // Create preview layer
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        previewLayer = preview
        
        print("🎥 VideoRecorder: Capture session ready")
        return preview
    }
    
    func startSession() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
                print("🎥 VideoRecorder: Session started")
                continuation.resume()
            }
        }
        
        // Give the camera a moment to warm up
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        print("🎥 VideoRecorder: Session ready for recording")
    }
    
    func stopSession() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.stopRunning()
                print("🎥 VideoRecorder: Session stopped")
                continuation.resume()
            }
        }
    }

    func switchCamera() async {
        guard let session = captureSession else { return }
        guard !isRecording else { return }

        let newPosition: AVCaptureDevice.Position = (currentPosition == .back) ? .front : .back
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
            print("🎥 VideoRecorder: ❌ Failed to switch camera")
            return
        }

        session.beginConfiguration()
        if let currentVideoInput {
            session.removeInput(currentVideoInput)
        }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            currentVideoInput = newInput
            currentPosition = newPosition
        } else if let currentVideoInput {
            session.addInput(currentVideoInput)
        }
        session.commitConfiguration()
    }
    
    func startRecording() {
        print("🎥 VideoRecorder: startRecording called")
        guard let output = videoOutput else {
            print("🎥 VideoRecorder: ❌ No video output")
            return
        }
        
        Task {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            
            await MainActor.run {
                output.startRecording(to: tempURL, recordingDelegate: self)
                isRecording = true
                recordingDuration = 0
            }
            
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.recordingDuration += 0.1
                }
            }
            
            print("🎥 VideoRecorder: Recording started to: \(tempURL)")
        }
    }
    
    func stopRecording() {
        print("🎥 VideoRecorder: stopRecording called")
        Task {
            videoOutput?.stopRecording()
            recordingTimer?.invalidate()
            recordingTimer = nil
            
            await MainActor.run {
                isRecording = false
            }
        }
    }
    
    func deleteRecording() {
        if let url = videoURL {
            try? FileManager.default.removeItem(at: url)
        }
        videoURL = nil
        recordingDuration = 0
    }
    
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension VideoRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("🎥 VideoRecorder: ❌ Recording error: \(error)")
                isRecording = false
            } else {
                print("🎥 VideoRecorder: ✅ Recording saved to: \(outputFileURL)")
                videoURL = outputFileURL
                isRecording = false
                saveVideoToLibrary(outputFileURL)
            }
        }
    }

    private func saveVideoToLibrary(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }, completionHandler: nil)
        }
    }
}
