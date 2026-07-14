//
//  RemoteVideoView.swift
//  ScreenShareApp
//

import SwiftUI
import WebRTC

struct RemoteVideoView: UIViewRepresentable {
    var videoTrack: RTCVideoTrack?

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFit
        view.backgroundColor = .black
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // 기존 트랙 제거 후 새 트랙 연결
        if let track = videoTrack {
            track.add(uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, RTCVideoViewDelegate {
        var parent: RemoteVideoView

        init(_ parent: RemoteVideoView) {
            self.parent = parent
        }

        func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
            NSLog("[RemoteVideoView] First frame received or Resize: \(size.width) x \(size.height)")
        }
    }
}
