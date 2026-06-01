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
        view.videoContentMode = .scaleAspectFit // 비율 유지하며 꽉 차게 표시
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // 기존 트랙 제거 후 새 트랙 연결
        if let track = videoTrack {
            track.add(uiView)
        }
    }
}
