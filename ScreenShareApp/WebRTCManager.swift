//
//  WebRTCManager.swift
//  ScreenShareApp
//

import WebRTC
import SocketIO

// <KAU> sdp 협상 프로토콜 모드를 정의
enum RTCClientMode {
    case broadcasterAsOfferer  // 송출자가 Offerer인 구조
    case viewerAsOfferer       // 수신자가 Offerer인 구조
}

class WebRTCManager: NSObject {
    var myId: String = ""
    private var factory: RTCPeerConnectionFactory
    private var peerConnections: [String: RTCPeerConnection] = [:]
    private var videoSource: RTCVideoSource
    private var videoTrack: RTCVideoTrack
    private var socket: SocketIOClient
    private var videoCapturer: RTCVideoCapturer?
    var onRemoteVideoTrackReceived: ((RTCVideoTrack) -> Void)?
    let currentMode: RTCClientMode
    
    init(socket: SocketIOClient, mode: RTCClientMode = .broadcasterAsOfferer) {
        self.socket = socket
        self.currentMode = mode
        RTCInitializeSSL()
        
        // let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoEncoderFactory = KAUEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()

//        let info = videoEncoderFactory.supportedCodecs()
//        if let first = info.first {
//            let _ = videoEncoderFactory.createEncoder(first)
//        }
        
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
    
    func handleOffer(from peerId: String, sdp: String) {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        
        let constraints: RTCMediaConstraints
        
        if currentMode == .viewerAsOfferer {
            // [모드 A] 내가 송신자인데 시청자의 Offer를 받은 상황
            constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        } else {
            // [모드 B] 내가 수신자(뷰어)이거나, Offerer 모드인데 방어 코드로 처리될 때
            config.sdpSemantics = .unifiedPlan
            constraints = RTCMediaConstraints(
                mandatoryConstraints: [
                    kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue,
                    kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue
                ],
                optionalConstraints: nil
            )
        }
        
        guard let newPc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else { return }
                
        if currentMode == .viewerAsOfferer {
            // 송신자이므로 내 화면(로컬 비디오 트랙)을 PC에 추가
            guard let sender = newPc.add(self.videoTrack, streamIds: ["stream0"]) else {return}
            
            // 네트워크 상태에 따른 해상도 자동 저하(BWE)를 막기 위해 해상도 유지(Maintain Resolution) 강제 적용
            let parameters = sender.parameters
            parameters.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainResolution.rawValue)
            sender.parameters = parameters
        }
        // 수신자의 경우 Offer 수신 시 자동 생성되므로 addTransceiver 불필요
        
        self.peerConnections[peerId] = newPc
        
        let remoteSdp = RTCSessionDescription(type: .offer, sdp: sdp)
        newPc.setRemoteDescription(remoteSdp) { [weak self, weak newPc] error in
            guard error == nil else {
                NSLog("❌ [\(peerId)] Remote Description 에러: \(String(describing: error))")
                return
            }
            
            newPc?.answer(for: constraints) { (answerSdp, answerError) in
                guard let answerSdp = answerSdp else { return }
                
                // let modifiedSdpString = self?.preferCodec(in: answerSdp.sdp, codecName: "H264") ?? answerSdp.sdp
                // let modifiedSdp = RTCSessionDescription(type: answerSdp.type, sdp: modifiedSdpString)
                
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
    
    // 시청자로부터 Offer 수신 시 해당 시청자 전용 PC를 생성하고 Answer 응답
//    func handleOffer(from peerId: String, sdp: String) {
//        let config = RTCConfiguration()
//        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
//        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
//        
//        let newPc = factory.peerConnection(with: config, constraints: constraints, delegate: self)
//        
//        // 내 화면 트랙 추가
//        newPc.add(self.videoTrack, streamIds: ["stream0"])
//        self.peerConnections[peerId] = newPc
//        
//        let remoteSdp = RTCSessionDescription(type: .offer, sdp: sdp)
//        newPc.setRemoteDescription(remoteSdp) { [weak self, weak newPc] error in
//            guard error == nil else {
//                NSLog("❌ [\(peerId)] Remote Description 에러: \(String(describing: error))")
//                return
//            }
//            
//            newPc?.answer(for: constraints) { (answerSdp, answerError) in
//                guard let answerSdp = answerSdp else { return }
//                
//                // answer sdp 코덱 우선순위 편집
//                let modifiedSdpString = self?.preferCodec(in: answerSdp.sdp, codecName: "H264") ?? answerSdp.sdp
//                let modifiedSdp = RTCSessionDescription(type: answerSdp.type, sdp: modifiedSdpString)
//                
//                newPc?.setLocalDescription(modifiedSdp) { _ in
//                    
//                    let payload: [String: Any] = [
//                        "to": peerId,
//                        "data": [
//                            "type": "answer",
//                            "sdp": modifiedSdp.sdp
//                        ]
//                    ]
//                    self?.socket.emit("answer", payload)
//                }
//            }
//        }
//    }
    
//    func handleOffer(from peerId: String, sdp: String) {
//        let config = RTCConfiguration()
//        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
//        config.sdpSemantics = .unifiedPlan
//        
//        // 수신 전용(recvonly) 제약 조건
//        let constraints = RTCMediaConstraints(
//            mandatoryConstraints: [
//                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue,
//                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue
//            ],
//            optionalConstraints: nil
//        )
//        
//        guard let newPc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else { return }
//        
//        // 수신자이므로 수신 전용 트랜시버로 방향을 고정합니다. (로컬 트랙 추가 안 함)
//        newPc.addTransceiver(of: .video)!.setDirection(.recvOnly, error: nil)
//        newPc.addTransceiver(of: .audio)!.setDirection(.recvOnly, error: nil)
//        
//        self.peerConnections[peerId] = newPc
//        
//        let remoteSdp = RTCSessionDescription(type: .offer, sdp: sdp)
//        newPc.setRemoteDescription(remoteSdp) { [weak self, weak newPc] error in
//            guard error == nil else {
//                NSLog("❌ [\(peerId)] Remote Description 에러: \(String(describing: error))")
//                return
//            }
//            
//            newPc?.answer(for: constraints) { (answerSdp, answerError) in
//                guard let answerSdp = answerSdp else { return }
//                
//                // let modifiedSdpString = self?.preferCodec(in: answerSdp.sdp, codecName: "H264") ?? answerSdp.sdp
//                // let modifiedSdp = RTCSessionDescription(type: answerSdp.type, sdp: modifiedSdpString)
//                
//                newPc?.setLocalDescription(answerSdp) { _ in
//                    let payload: [String: Any] = [
//                        "to": peerId,
//                        "data": [
//                            "type": "answer",
//                            "sdp": answerSdp.sdp
//                        ]
//                    ]
//                    self?.socket.emit("answer", payload)
//                }
//            }
//        }
//    }
    
    func createReceiverConnection(to parentId: String) {
        guard currentMode == .viewerAsOfferer else {
            NSLog("⚠️ 현재 모드가 viewerAsOfferer가 아니므로 수신자용 Offer를 생성하지 않습니다.")
            return
        }
        
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        
        // 수신 전용(recvonly) 제약 조건
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )
        
        guard let newPc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else { return }
        
        // 트랜시버를 수신 전용으로 설정
        newPc.addTransceiver(of: .video)!.setDirection(.recvOnly, error: nil)
        newPc.addTransceiver(of: .audio)!.setDirection(.recvOnly, error: nil)
        
        self.peerConnections[parentId] = newPc
        
        newPc.offer(for: constraints) { [weak self, weak newPc] (sdp, error) in
            guard let sdp = sdp else {
                NSLog("❌ Offer 생성 실패: \(String(describing: error))")
                return
            }
            
            // sdp 코덱 우선순위 편집
            // let modifiedSdpString = self?.preferCodec(in: sdp.sdp, codecName: "H264") ?? sdp.sdp
            // let modifiedSdp = RTCSessionDescription(type: sdp.type, sdp: modifiedSdpString)
            
            newPc?.setLocalDescription(sdp) { _ in
                let payload: [String: Any] = [
                    "to": parentId,
                    "data": [
                        "type": "offer",
                        "sdp": sdp.sdp
                    ]
                ]
                self?.socket.emit("offer", payload)
            }
        }
    }
    
    func createSenderConnection(to childId: String) {
        guard currentMode == .broadcasterAsOfferer else {
            NSLog("⚠️ 현재 모드가 broadcasterAsOfferer가 아니므로 송신자용 Offer를 생성하지 않습니다.")
            return
        }
        
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        guard let newPc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else { return }
        
        // 송출자이므로 내 화면/카메라 트랙을 추가합니다.
        guard let sender = newPc.add(self.videoTrack, streamIds: ["stream0"]) else {return}
        let parameters = sender.parameters
        parameters.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainResolution.rawValue)
        sender.parameters = parameters
        self.peerConnections[childId] = newPc
        
        newPc.offer(for: constraints) { [weak self, weak newPc] (sdp, error) in
            guard let sdp = sdp else {
                NSLog("❌ Offer 생성 실패: \(String(describing: error))")
                return
            }
            
            // sdp 코덱 우선순위 편집 (H264)
            // let modifiedSdpString = self?.preferCodec(in: sdp.sdp, codecName: "H264") ?? sdp.sdp
            // let modifiedSdp = RTCSessionDescription(type: sdp.type, sdp: modifiedSdpString)
            
            newPc?.setLocalDescription(sdp) { _ in
                let payload: [String: Any] = [
                    "to": childId,
                    "data": [
                        "type": "offer",
                        "sdp": sdp.sdp
                    ]
                ]
                self?.socket.emit("offer", payload)
            }
        }
    }
    
    func handleAnswer(from peerId: String, sdp: String) {
        guard let pc = peerConnections[peerId] else { return }
        let remoteSdp = RTCSessionDescription(type: .answer, sdp: sdp)
        
        pc.setRemoteDescription(remoteSdp) { error in
            if let error = error {
                NSLog("❌ [\(peerId)] Remote Description Answer 에러: \(error)")
            } else {
                NSLog("✅ [\(peerId)] Answer 설정 완료 (시청 파이프라인 개통)")
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

extension WebRTCManager {
    private func preferCodec(in sdp: String, codecName: String) -> String {
        var lines = sdp.components(separatedBy: "\r\n")
        var mLineIndex: Int? = nil
        var targetPayloadTypes: [String] = []
        
        // m=video 라인을 찾은 후, a=rtpmap 라인에서 타겟 코덱의 페이로드 타입을 수집
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("m=video") {
                mLineIndex = index
            } else if line.hasPrefix("a=rtpmap:"), line.lowercased().contains(codecName.lowercased()) {
                let parts = line.components(separatedBy: " ")
                if let pt = parts.first?.components(separatedBy: ":").last {
                    targetPayloadTypes.append(pt)
                }
            }
        }
        
        // 비디오 라인이 없거나 해당 코덱이 sdp에 아예 없다면 원본 반환
        guard let mLineIdx = mLineIndex, !targetPayloadTypes.isEmpty else {
            return sdp
        }
        
        let mLineParts = lines[mLineIdx].components(separatedBy: " ")
        guard mLineParts.count > 3 else { return sdp }
        
        let coreParts = Array(mLineParts[0..<3])
        let payloadTypes = Array(mLineParts[3...])
        
        // 페이로드 타입 순서 재배치
        var preferredPayloadTypes: [String] = []
        var otherPayloadTypes: [String] = []
        
        for pt in payloadTypes {
            if targetPayloadTypes.contains(pt) {
                preferredPayloadTypes.append(pt)
            } else {
                otherPayloadTypes.append(pt)
            }
        }
        
        // 재구성된 m=video 라인 덮어쓰기
        let newMLine = (coreParts + preferredPayloadTypes + otherPayloadTypes).joined(separator: " ")
        lines[mLineIdx] = newMLine
        
        NSLog("SDP Munged: \(newMLine)")
        return lines.joined(separator: "\r\n")
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let peerId = peerConnections.first(where: { $0.value == peerConnection })?.key else { return }
        
        NSLog("📤 [WebRTC] ICE Candidate 생성됨: \(candidate.sdp) (to: \(peerId))")
        
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
        guard let peerId = peerConnections.first(where: { $0.value == peerConnection })?.key else { return }
        
        NSLog("ℹ️ [\(peerId)] ICE Connection State: \(newState.rawValue)")
        
        // 연결이 완전히 끊기면 메모리(딕셔너리)에서 정리
        if newState == .disconnected || newState == .failed || newState == .closed {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                peerConnection.close()
                self.peerConnections.removeValue(forKey: peerId)
                NSLog("⚠️ [\(peerId)] 연결 종료됨. 메인 스레드에서 PC 정리 완료.")
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        NSLog("ℹ️ Signaling State: \(stateChanged.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        NSLog("✅ [WebRTC] 원격 스트림 수신됨: \(stream.streamId)")
        if let videoTrack = stream.videoTracks.first {
            DispatchQueue.main.async { [weak self] in
                self?.onRemoteVideoTrackReceived?(videoTrack)
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
