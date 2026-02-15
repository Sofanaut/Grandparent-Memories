//
//  CameraPreviewView.swift
//  GrandparentMemories
//
//  Created by Tony Smith on 05/02/2026.
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.previewLayer = previewLayer

        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Force layout update
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            uiView.previewLayer?.frame = uiView.bounds
            CATransaction.commit()
        }
    }
}

// Custom UIView that updates the preview layer on layout changes
class PreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()

        // Update preview layer frame whenever the view's layout changes
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}
