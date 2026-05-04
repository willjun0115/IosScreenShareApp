//
//  WebRTCManager.swift
//  ScreenShareApp
//
//  Created by supercoder on 4/8/26.
//

import WebRTC
import SocketIO

class WebRTCManager: NSObject {
    var myId: String = ""
    private var factory: RTCPeerConnectionFactory
    private var peerConnections: [String: RTCPeerConnection] = [:]
    private var videoSource: RTCVideoSource
    private var videoTrack: RTCVideoTrack
    private var socket: SocketIOClient
    private var videoCapturer: RTCVideoCapturer?
    
    init(socket: SocketIOClient) {
        self.socket = socket
        RTCInitializeSSL()
        
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        // let videoEncoderFactory = KAUEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
        
        self.videoSource = factory.videoSource()
        self.videoSource.adaptOutputFormat(toWidth: 720, height: 1280, fps: 15)
        self.videoCapturer = RTCVideoCapturer(delegate: self.videoSource)
        self.videoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
        super.init()
    }
    
    // 시청자로부터 Offer 수신 시 해당 시청자 전용 PC를 생성하고 Answer 응답
    func handleOffer(from peerId: String, sdp: String) {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        let newPc = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        
        // 내 화면 트랙 추가
        newPc.add(self.videoTrack, streamIds: ["stream0"])
        self.peerConnections[peerId] = newPc
        
        let remoteSdp = RTCSessionDescription(type: .offer, sdp: sdp)
        newPc.setRemoteDescription(remoteSdp) { [weak self, weak newPc] error in
            guard error == nil else {
                NSLog("❌ [\(peerId)] Remote Description 에러: \(String(describing: error))")
                return
            }
            
            newPc?.answer(for: constraints) { (answerSdp, answerError) in
                guard let answerSdp = answerSdp else { return }
                newPc?.setLocalDescription(answerSdp) { _ in
                    
                    let payload: [String: Any] = [
                        "to": peerId,
                        "data": [
                            "type": "answer",
                            "sdp": answerSdp.sdp
                        ]
                    ]
                    self?.socket.emit("answer", payload)
                }
            }
        }
    }
    
    // 뷰어의 ICE Candidate 처리
    func handleCandidate(from peerId: String, candidateDict: [String: Any]) {
        guard let pc = peerConnections[peerId] else {
            NSLog("⚠️ [\(peerId)] PC를 찾을 수 없어 Candidate를 무시합니다.")
            return
        }
        
        let candidate = RTCIceCandidate(
            sdp: candidateDict["candidate"] as? String ?? "",
            sdpMLineIndex: Int32(candidateDict["sdpMLineIndex"] as? Int ?? 0),
            sdpMid: candidateDict["sdpMid"] as? String
        )
        pc.add(candidate)
    }
    
    func sendVideoBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timeStampNs = Int64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000_000)
        
        let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: timeStampNs)
        
        if let capturer = self.videoCapturer {
            self.videoSource.capturer(capturer, didCapture: videoFrame)
        }
    }
    
    func sendPixelBuffer(_ pixelBuffer: CVPixelBuffer, timeStampNs: Int64) {
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: timeStampNs)
        
        if let capturer = self.videoCapturer {
            self.videoSource.capturer(capturer, didCapture: videoFrame)
        }
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let peerId = peerConnections.first(where: { $0.value == peerConnection })?.key else { return }
        
        let candidateDict: [String: Any] = [
            "sdpMLineIndex": candidate.sdpMLineIndex,
            "sdpMid": candidate.sdpMid ?? "",
            "candidate": candidate.sdp
        ]
        
        let payload: [String: Any] = [
            "to": peerId,
            "data": [
                "type": "candidate",
                "candidate": candidateDict
            ]
        ]
        
        socket.emit("candidate", payload)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        // 연결이 완전히 끊기면 메모리(딕셔너리)에서 정리
        if newState == .disconnected || newState == .failed || newState == .closed {
            if let peerId = peerConnections.first(where: { $0.value == peerConnection })?.key {
                peerConnections.removeValue(forKey: peerId)
                NSLog("⚠️ [\(peerId)] 연결 종료됨. PC 정리 완료.")
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
