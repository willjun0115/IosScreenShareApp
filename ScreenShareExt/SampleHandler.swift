//
//  SampleHandler.swift
//  ScreenShareExt
//
//  Created by supercoder on 4/8/26.
//

import ReplayKit
import WebRTC
import SocketIO

class SampleHandler: RPBroadcastSampleHandler {
    var socketManager: SocketManager?
    var socket: SocketIOClient?
    var rtcManager: WebRTCManager?

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        let sharedSettings = UserDefaults(suiteName: "group.com.will115.screenshare")
        let roomID = sharedSettings?.string(forKey: "broadcastRoomID") ?? "testRoom"
        
        let serverURL = URL(string: "https://192.168.0.26:8000")!
        socketManager = SocketManager(socketURL: serverURL, config: [
            .log(false),
            .forceWebsockets(true),
            .reconnects(true),
            .reconnectWait(1),
            .secure(true)
        ])
        socket = socketManager?.defaultSocket
        
        // 매니저 생성
        rtcManager = WebRTCManager(socket: socket!)
        
        socket?.on(clientEvent: .connect) { [weak self] _, _ in
            NSLog("✅ 서버 연결 성공 (Room: \(roomID))")
            
            self?.socket?.emit("join", ["room": roomID, "type": "broadcast"])

            self?.socket?.on("my-id") { data, _ in
                if let id = data[0] as? String {
                    self?.rtcManager?.myId = id
                }
            }

            self?.socket?.on("root-broadcaster") { _, _ in
                NSLog("✅ Root 방송자로 지정됨. 시청자의 Offer를 대기합니다.")
            }

            self?.socket?.on("offer") { [weak self] data, _ in
                if let dict = data[0] as? [String: Any],
                   let fromId = dict["from"] as? String,
                   let sdpData = dict["data"] as? [String: Any],
                   let sdpString = sdpData["sdp"] as? String {
                    
                    self?.rtcManager?.handleOffer(from: fromId, sdp: sdpString)
                }
            }
            
            // 새 서버 규격에 맞춘 ICE Candidate 수신
            self?.socket?.on("candidate") { [weak self] data, _ in
                if let dict = data[0] as? [String: Any],
                   let fromId = dict["from"] as? String,
                   let candData = dict["data"] as? [String: Any],
                   let candidateDict = candData["candidate"] as? [String: Any] {
                    
                    self?.rtcManager?.handleCandidate(from: fromId, candidateDict: candidateDict)
                }
            }
        }
        
        socket?.connect()
    }
    
    override func broadcastPaused() {}
    override func broadcastResumed() {}
    
    override func broadcastFinished() {
        socket?.disconnect()
        socketManager = nil
        rtcManager = nil
        print("Broadcast finished. Disconnecting...")
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        autoreleasepool{
            switch sampleBufferType {
            case RPSampleBufferType.video:
                rtcManager?.sendVideoBuffer(sampleBuffer)
            case RPSampleBufferType.audioApp, RPSampleBufferType.audioMic:
                break
            @unknown default:
                break
            }
        }
    }
}
