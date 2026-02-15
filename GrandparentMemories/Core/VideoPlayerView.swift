//
//  VideoPlayerView.swift
//  GrandparentMemories
//
//  Created by Tony Smith on 05/02/2026.
//

import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL
    let autoPlay: Bool
    
    init(url: URL, autoPlay: Bool = false) {
        self.url = url
        self.autoPlay = autoPlay
    }
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        // Optimize for fast loading
        player.automaticallyWaitsToMinimizeStalling = false
        playerItem.preferredForwardBufferDuration = 2.0 // Small buffer
        
        controller.player = player
        controller.videoGravity = .resizeAspectFill
        controller.showsPlaybackControls = true
        
        if autoPlay {
            context.coordinator.setupAutoPlay(for: player)
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Only update if URL changed
        if let currentPlayer = uiViewController.player,
           let currentAsset = currentPlayer.currentItem?.asset as? AVURLAsset,
           currentAsset.url != url {
            
            let asset = AVAsset(url: url)
            let playerItem = AVPlayerItem(asset: asset)
            let newPlayer = AVPlayer(playerItem: playerItem)
            
            newPlayer.automaticallyWaitsToMinimizeStalling = false
            playerItem.preferredForwardBufferDuration = 2.0
            
            uiViewController.player = newPlayer
            
            if autoPlay {
                context.coordinator.setupAutoPlay(for: newPlayer)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        private var statusObserver: NSKeyValueObservation?
        
        func setupAutoPlay(for player: AVPlayer) {
            statusObserver = player.observe(\.currentItem?.status, options: [.new]) { player, _ in
                if player.currentItem?.status == .readyToPlay {
                    DispatchQueue.main.async {
                        player.play()
                    }
                }
            }
        }
        
        deinit {
            statusObserver?.invalidate()
        }
    }
}
