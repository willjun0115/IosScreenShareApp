//
//  WebRTCManager.swift
//  ScreenShareApp
//

import WebRTC
import SocketIO
import Foundation
import Darwin

// sdp 협상 프로토콜 모드를 정의
enum RTCClientMode: String, CaseIterable, Identifiable {
    case broadcasterAsOfferer = "송출자가 Offerer (Broadcaster)"
    case viewerAsOfferer = "수신자가 Offerer (Viewer)"
    
    var id: String { self.rawValue }
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
    private var statsTimer: Timer?
    
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
        startStatsTimer()
    }
    
    deinit {
        statsTimer?.invalidate()
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
            // 내 화면(로컬 비디오 트랙)을 PC에 추가
            guard let sender = newPc.add(self.videoTrack, streamIds: ["stream0"]) else {return}
            
            // 해상도 자동 저하(BWE)를 막기 위해 해상도 유지(Maintain Resolution) 강제 적용
            let parameters = sender.parameters
            parameters.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainResolution.rawValue)
            sender.parameters = parameters
        }
        
        self.peerConnections[peerId] = newPc
        
        let remoteSdp = RTCSessionDescription(type: .offer, sdp: sdp)
        newPc.setRemoteDescription(remoteSdp) { [weak self, weak newPc] error in
            guard error == nil else {
                NSLog("❌ [\(peerId)] Remote Description Error: \(String(describing: error))")
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
                NSLog("❌ Failed to create Offer: \(String(describing: error))")
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
        
        // 내 화면/카메라 트랙을 추가
        guard let sender = newPc.add(self.videoTrack, streamIds: ["stream0"]) else {return}
        let parameters = sender.parameters
        parameters.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainResolution.rawValue)
        sender.parameters = parameters
        self.peerConnections[childId] = newPc
        
        newPc.offer(for: constraints) { [weak self, weak newPc] (sdp, error) in
            guard let sdp = sdp else {
                NSLog("❌ Failed to create Offer: \(String(describing: error))")
                return
            }
            
            // sdp 코덱 우선순위 편집
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
                NSLog("❌ [\(peerId)] Remote Description Answer Error: \(error)")
            } else {
                NSLog("✅ [\(peerId)] success to set Answer sdp.")
            }
        }
    }
    
    // 뷰어의 ICE Candidate 처리
    func handleCandidate(from peerId: String, candidateDict: [String: Any]) {
        guard let pc = peerConnections[peerId] else {
            NSLog("⚠️ [\(peerId)] Cannot find PC. Disregard Candidate.")
            return
        }
        
        let candidate = RTCIceCandidate(
            sdp: candidateDict["candidate"] as? String ?? "",
            sdpMLineIndex: Int32((candidateDict["sdpMLineIndex"] as? NSNumber)?.int32Value ?? 0),
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let peerId = self.peerConnections.first(where: { $0.value == peerConnection })?.key else { return }
            
            NSLog("📤 [WebRTC] ICE Candidate created: \(candidate.sdp) (to: \(peerId))")
            
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
            
            self.socket.emit("candidate", payload)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let peerId = self.peerConnections.first(where: { $0.value == peerConnection })?.key else { return }
            
            NSLog("ℹ️ [\(peerId)] ICE Connection State: \(newState.rawValue)")
            
            // 연결이 완전히 끊기면 메모리(딕셔너리)에서 정리
            if newState == .disconnected || newState == .failed || newState == .closed {
                peerConnection.close()
                self.peerConnections.removeValue(forKey: peerId)
                NSLog("⚠️ [\(peerId)] Disconnected. PC deleted from main thread.")
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        NSLog("ℹ️ Signaling State: \(stateChanged.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        NSLog("✅ [WebRTC] Remote Stream received: \(stream.streamId)")
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

// MARK: - WebRTC Statistics Collection
extension WebRTCManager {
    private func startStatsTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statsTimer?.invalidate()
            self.statsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.collectStatistics()
            }
            NSLog("📊 [Stats] Statistics collection started")
        }
    }
    
    private func collectStatistics() {
        let activeConnections = self.peerConnections
        guard !activeConnections.isEmpty else { return }
        
        // Measure CPU and Memory usage
        let cpu = SystemResourceMonitor.getCPUUsage()
        let memory = SystemResourceMonitor.getMemoryUsage()
        
        for (peerId, pc) in activeConnections {
            pc.statistics { [weak self] report in
                let codableReport = CodableStatisticsReport(from: report, cpu: cpu, memory: memory)
                self?.saveStatsReport(codableReport, for: peerId)
            }
        }
    }
    
    private func getStatsFileURL(for peerId: String) -> URL {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = urls[0]
        return documentsDirectory.appendingPathComponent("webrtc_stats_\(peerId).json")
    }
    
    private func saveStatsReport(_ codableReport: CodableStatisticsReport, for peerId: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let fileURL = self.getStatsFileURL(for: peerId)
            
            var reports: [CodableStatisticsReport] = []
            if let data = try? Data(contentsOf: fileURL) {
                if let decoded = try? JSONDecoder().decode([CodableStatisticsReport].self, from: data) {
                    reports = decoded
                }
            }
            
            reports.append(codableReport)
            
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(reports)
                try data.write(to: fileURL, options: .atomic)
                // NSLog("📊 [Stats] Saved stats for \(peerId) to \(fileURL.path) (total points: \(reports.count))")
            } catch {
                NSLog("❌ [Stats] Error saving stats for peer \(peerId): \(error)")
            }
        }
    }
}

// MARK: - Codable WebRTC Statistics Models
enum CodableValue: Codable {
    case string(String)
    case number(Double)
    case array([CodableValue])
    case dictionary([String: Double])
    
    init?(from object: NSObject) {
        if let str = object as? String {
            self = .string(str)
        } else if let num = object as? NSNumber {
            self = .number(num.doubleValue)
        } else if let arr = object as? [NSObject] {
            var codableArr: [CodableValue] = []
            for item in arr {
                if let val = CodableValue(from: item) {
                    codableArr.append(val)
                }
            }
            self = .array(codableArr)
        } else if let dict = object as? [String: NSNumber] {
            var codableDict: [String: Double] = [:]
            for (k, v) in dict {
                codableDict[k] = v.doubleValue
            }
            self = .dictionary(codableDict)
        } else {
            return nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let val):
            try container.encode(val)
        case .number(let val):
            try container.encode(val)
        case .array(let val):
            try container.encode(val)
        case .dictionary(let val):
            try container.encode(val)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let val = try? container.decode(String.self) {
            self = .string(val)
        } else if let val = try? container.decode(Double.self) {
            self = .number(val)
        } else if let val = try? container.decode([CodableValue].self) {
            self = .array(val)
        } else if let val = try? container.decode([String: Double].self) {
            self = .dictionary(val)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode CodableValue")
        }
    }
}

struct CodableStatistics: Codable {
    let id: String
    let timestampUs: Double
    let type: String
    let values: [String: CodableValue]
}

struct CodableStatisticsReport: Codable {
    let timestampUs: Double
    let statistics: [String: CodableStatistics]
    let cpuUsage: Double?
    let memoryUsage: Double?
    
    init(from report: RTCStatisticsReport, cpu: Double? = nil, memory: Double? = nil) {
        self.timestampUs = report.timestamp_us
        self.cpuUsage = cpu
        self.memoryUsage = memory
        var codableStats: [String: CodableStatistics] = [:]
        for (key, stats) in report.statistics {
            var codableValues: [String: CodableValue] = [:]
            for (valKey, valObj) in stats.values {
                if let codableVal = CodableValue(from: valObj) {
                    codableValues[valKey] = codableVal
                }
            }
            codableStats[key] = CodableStatistics(
                id: stats.id,
                timestampUs: stats.timestamp_us,
                type: stats.type,
                values: codableValues
            )
        }
        self.statistics = codableStats
    }
}

// MARK: - System Resource Monitor Helper
class SystemResourceMonitor {
    // 현재 메모리 사용량 (MB) 반환
    static func getMemoryUsage() -> Double {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(taskInfo.resident_size) / 1024.0 / 1024.0 // Convert bytes to MB
        } else {
            return 0.0
        }
    }
    
    // 현재 CPU 사용량 (%) 반환
    static func getCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let kernReturn = withUnsafeMutablePointer(to: &threadList) {
            task_threads(mach_task_self_, $0, &threadCount)
        }
        
        guard kernReturn == KERN_SUCCESS, let threads = threadList else {
            return 0.0
        }
        
        var totalCPU: Double = 0.0
        let THREAD_FLAGS_IDLE: integer_t = 4
        
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            
            let infoReturn = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }
            
            if infoReturn == KERN_SUCCESS {
                if (threadInfo.flags & THREAD_FLAGS_IDLE) == 0 {
                    totalCPU += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                }
            }
        }
        
        // Free thread list memory
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(threadCount * mach_msg_type_number_t(MemoryLayout<thread_t>.size)))
        
        return totalCPU
    }
}
