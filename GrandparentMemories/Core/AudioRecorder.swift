//
//  AudioRecorder.swift
//  GrandparentMemories
//
//  Created by Tony Smith on 05/02/2026.
//

import Foundation
import AVFoundation
import SwiftUI

@Observable
class AudioRecorder: NSObject {
    var isRecording = false
    var isPlaying = false
    var recordingDuration: TimeInterval = 0
    var audioData: Data?
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var recordingURL: URL?
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        Task {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try audioSession.setActive(true)
            } catch {
                print("Failed to set up audio session: \(error)")
            }
        }
    }
    
    func requestPermission(completion: @escaping (Bool) -> Void) async {
        print("🎤 AudioRecorder: Requesting permission")
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                print("🎤 AudioRecorder: Permission callback received: \(granted)")
                Task { @MainActor in
                    print("🎤 AudioRecorder: On main actor")
                    completion(granted)
                    continuation.resume()
                }
            }
        }
        print("🎤 AudioRecorder: Permission request completed")
    }
    
    func startRecording() {
        print("🎤 AudioRecorder: startRecording called")
        Task {
            print("🎤 AudioRecorder: In Task")
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            recordingURL = tempURL
            print("🎤 AudioRecorder: Temp URL created: \(tempURL)")
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            do {
                print("🎤 AudioRecorder: Setting up audio session")
                // Set up audio session
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try audioSession.setActive(true)
                print("🎤 AudioRecorder: Audio session active")
                
                audioRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
                audioRecorder?.delegate = self
                audioRecorder?.record()
                print("🎤 AudioRecorder: Recording started")
                
                await MainActor.run {
                    print("🎤 AudioRecorder: Setting isRecording = true")
                    isRecording = true
                    recordingDuration = 0
                }
                
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    Task { @MainActor in
                        self.recordingDuration = self.audioRecorder?.currentTime ?? 0
                    }
                }
                print("🎤 AudioRecorder: Timer started")
            } catch {
                print("🎤 AudioRecorder: ❌ Failed to start recording: \(error)")
                await MainActor.run {
                    isRecording = false
                }
            }
        }
    }
    
    func stopRecording() {
        Task {
            audioRecorder?.stop()
            recordingTimer?.invalidate()
            recordingTimer = nil
            
            await MainActor.run {
                isRecording = false
            }
            
            // Convert recording to Data
            if let url = recordingURL {
                do {
                    let data = try Data(contentsOf: url)
                    await MainActor.run {
                        audioData = data
                    }
                } catch {
                    print("Failed to load audio data: \(error)")
                }
            }
        }
    }
    
    func playAudio(from data: Data) {
        Task {
            do {
                // Configure audio session for playback
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .default)
                try audioSession.setActive(true)
                
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.prepareToPlay()
                player.play()
                
                await MainActor.run {
                    audioPlayer = player
                    audioData = data
                    recordingDuration = player.duration
                    isPlaying = true
                }
            } catch {
                print("Failed to play audio: \(error)")
                await MainActor.run {
                    isPlaying = false
                }
            }
        }
    }
    
    func stopPlaying() {
        audioPlayer?.stop()
        isPlaying = false
    }
    
    func deleteRecording() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioData = nil
        recordingDuration = 0
        recordingURL = nil
    }
    
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            isRecording = false
        }
    }
}

extension AudioRecorder: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
        }
    }
}
