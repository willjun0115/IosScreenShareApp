//
//  KAUBroadcastManager.swift
//  ScreenShareApp
//

import Foundation
import WebRTC
import SocketIO

enum captureSource {
    case screen
    case camera
}

class KAUBroadcastManager: ObservableObject {
    static let shared = KAUBroadcastManager()
    private let cameraCapturer = KAUCameraCapturer()
    
    #if canImport(ScreenCaptureKit)
    private var _macCapturer: Any?
    @available(macOS 12.3, iOS 18.0, macCatalyst 18.2, *)
    private var macCapturer: KAUMacScreenCapturer {
        if _macCapturer == nil {
            _macCapturer = KAUMacScreenCapturer()
        }
        return _macCapturer as! KAUMacScreenCapturer
    }
    #endif
    
    var socketManager: SocketManager?
    var socket: SocketIOClient?
    var rtcManager: WebRTCManager?
    
    @Published var isConnected = false
    @Published var remoteVideoTrack: RTCVideoTrack?
    
    func startStreaming(source: captureSource, roomID: String, mode: RTCClientMode = .broadcasterAsOfferer) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            startConnection(roomID: roomID, mode: mode)
            
            guard let rtc = rtcManager else { return }
            
            switch source {
            case .screen:
                cameraCapturer.stopCapture()
                #if canImport(ScreenCaptureKit)
                if #available(macOS 12.3, iOS 18.0, macCatalyst 18.2, *) {
                    var isMac = false
                    #if os(macOS) || targetEnvironment(macCatalyst)
                    isMac = true
                    #else
                    if ProcessInfo.processInfo.isiOSAppOnMac {
                        isMac = true
                    }
                    #endif
                    
                    if isMac {
                        NSLog("✅ [Manager] Mac 캡처 분기 진입 (ScreenCaptureKit)")
                        KAUReceiver.shared.stopReceiving()
                        self.macCapturer.startCapture(rtcManager: rtc)
                    } else {
                        NSLog("✅ [Manager] iOS 캡처 분기 진입 (mmap)")
                        KAUReceiver.shared.startReceiving(rtcManager: rtc)
                    }
                } else {
                    NSLog("⚠️ [Manager] ScreenCaptureKit 지원 안 됨 (버전 낮음)")
                    KAUReceiver.shared.startReceiving(rtcManager: rtc)
                }
                #else
                NSLog("⚠️ [Manager] ScreenCaptureKit Import 실패 (iOS 전용 빌드)")
                // 익스텐션으로부터 프레임을 받는 mmap 수신기 시작
                KAUReceiver.shared.startReceiving(rtcManager: rtc)
                #endif
            case .camera:
                KAUReceiver.shared.stopReceiving()
                #if canImport(ScreenCaptureKit)
                if #available(macOS 12.3, iOS 18.0, macCatalyst 18.2, *) {
                    self.macCapturer.stopCapture()
                }
                #endif
                // 메인 앱 직접 카메라 캡처 시작
                cameraCapturer.startCapture(rtcManager: rtc)
            }
        }
    }
    
<<<<<<< HEAD
    func startConnection(roomID: String, mode: RTCClientMode = .broadcasterAsOfferer) {
        let serverURL = URL(string: "https://192.168.1.62:8000")!
=======
    func startConnection(roomID: String) {
        let serverURL = URL(string: "https://192.168.0.5:8000")!
>>>>>>> 835c90c13002b16854a3a969c0353bdeb6e9e679
        socketManager = SocketManager(socketURL: serverURL, config: [
            .log(false),
            .forceWebsockets(true),
            .reconnects(true),
            .reconnectWait(1),
            .secure(true)
        ])
        socket = socketManager?.defaultSocket
        BackgroundAudioPlayer.shared.start()
        
<<<<<<< HEAD
        rtcManager = WebRTCManager(socket: socket!, mode: mode)
=======
        rtcManager = WebRTCManager(socket: socket!, mode: .viewerAsOfferer)
>>>>>>> 835c90c13002b16854a3a969c0353bdeb6e9e679
        
        rtcManager?.onRemoteVideoTrackReceived = { [weak self] track in
            self?.remoteVideoTrack = track
        }
        
        // 1. connect 안에는 join emit만 남깁니다. (재연결 시 다시 방에 들어가야 하므로)
        socket?.on(clientEvent: .connect) { [weak self] _, _ in
            NSLog("✅ 서버 연결 성공 (Room: \(roomID))")
            self?.socket?.emit("join", ["room": roomID, "type": "broadcast"])
            DispatchQueue.main.async {
                self?.isConnected = true
            }
        }

        // ----------------------------------------------------
        // ✨ 2. 이벤트 리스너들을 .connect 클로저 밖으로 분리합니다!
        // ----------------------------------------------------
        socket?.on("my-id") { [weak self] data, _ in
            if let id = data[0] as? String {
                self?.rtcManager?.myId = id
            }
        }

        socket?.on("root-broadcaster") { _, _ in
            NSLog("✅ Root 방송자로 지정됨. 시청자의 Offer를 대기합니다.")
        }
        
        socket?.on("new-parent") { [weak self] data, _ in
            if let parentId = data[0] as? String {
                NSLog("✅ [Signaling] 새 부모 할당됨: \(parentId). 시청용 Offer 전송...")
                self?.rtcManager?.createReceiverConnection(to: parentId)
            }
        }
        
        socket?.on("new-child") { [weak self] data, _ in
            if let childId = data[0] as? String {
                NSLog("✅ [Signaling] 새 시청자 접속: \(childId). 시청자에게 Offer 전송 시작...")
                self?.rtcManager?.createSenderConnection(to: childId)
            }
        }

        socket?.on("offer") { [weak self] data, _ in
            if let dict = data[0] as? [String: Any],
               let fromId = dict["from"] as? String,
               let sdpData = dict["data"] as? [String: Any],
               let sdpString = sdpData["sdp"] as? String {
                self?.rtcManager?.handleOffer(from: fromId, sdp: sdpString)
            }
        }
        
        socket?.on("answer") { [weak self] data, _ in
            if let dict = data[0] as? [String: Any],
               let fromId = dict["from"] as? String,
               let sdpData = dict["data"] as? [String: Any],
               let sdpString = sdpData["sdp"] as? String {
                self?.rtcManager?.handleAnswer(from: fromId, sdp: sdpString)
            }
        }
        
        socket?.on("candidate") { [weak self] data, _ in
            NSLog("📥 [Signaling] candidate 수신 데이터: \(data)")
            if let dict = data[0] as? [String: Any],
               let fromId = dict["from"] as? String,
               let candData = dict["data"] as? [String: Any],
               let candidateDict = candData["candidate"] as? [String: Any] {
                NSLog("✅ [Signaling] candidate 파싱 성공 from: \(fromId)")
                self?.rtcManager?.handleCandidate(from: fromId, candidateDict: candidateDict)
            } else {
                NSLog("❌ [Signaling] candidate 파싱 실패")
            }
        }
        
        socket?.connect()
    }
    
    func stopConnection() {
        KAUReceiver.shared.stopReceiving() // frame receiver 종료
        cameraCapturer.stopCapture() // camera capturer 종료
        #if canImport(ScreenCaptureKit)
        if #available(macOS 12.3, iOS 18.0, macCatalyst 18.2, *) {
            macCapturer.stopCapture()
        }
        #endif
        BackgroundAudioPlayer.shared.stop() // background audio 종료
        socket?.disconnect()
        socketManager = nil
        rtcManager = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.remoteVideoTrack = nil
        }
    }
}
